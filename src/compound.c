/* Compound datasets through Rhdf5lib (ADR 0008).
 *
 * rhdf5 cannot see or build the members of an HDF5 compound type, so this file
 * reads member types by file path and writes compound datasets to a file. The
 * library is a static copy private to this package, so no HDF5 id is shared
 * with rhdf5.
 */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <hdf5.h>

#define ERR_LEN 512

static void set_error(char *err, const char *msg) {
  strncpy(err, msg, ERR_LEN - 1);
  err[ERR_LEN - 1] = '\0';
}

static const char *class_name(H5T_class_t cls) {
  switch (cls) {
  case H5T_INTEGER:
    return "integer";
  case H5T_FLOAT:
    return "float";
  case H5T_STRING:
    return "string";
  case H5T_ENUM:
    return "enum";
  case H5T_COMPOUND:
    return "compound";
  case H5T_VLEN:
    return "vlen";
  default:
    return "other";
  }
}

/* Describes one member type (the base type for array members) */
typedef struct {
  const char *cls;
  int size;
  int sign;      /* 1 signed, 0 unsigned, -1 not an integer */
  int big;       /* 1 big endian */
  int variable;  /* 1 variable-length string */
  int utf8;      /* 1 UTF-8 string */
  SEXP enum_names;
} member_info;

static void describe_type(hid_t type, member_info *info) {
  H5T_class_t cls = H5Tget_class(type);
  info->cls = class_name(cls);
  info->size = (int)H5Tget_size(type);
  info->sign = -1;
  info->big = 0;
  info->variable = 0;
  info->utf8 = 0;
  info->enum_names = R_NilValue;
  if (cls == H5T_INTEGER) {
    info->sign = H5Tget_sign(type) == H5T_SGN_2 ? 1 : 0;
    info->big = H5Tget_order(type) == H5T_ORDER_BE;
  } else if (cls == H5T_FLOAT) {
    info->big = H5Tget_order(type) == H5T_ORDER_BE;
  } else if (cls == H5T_STRING) {
    info->variable = H5Tis_variable_str(type) > 0;
    info->utf8 = H5Tget_cset(type) == H5T_CSET_UTF8;
  } else if (cls == H5T_ENUM) {
    int n = H5Tget_nmembers(type);
    info->enum_names = PROTECT(allocVector(STRSXP, n));
    for (int i = 0; i < n; i++) {
      char *name = H5Tget_member_name(type, (unsigned)i);
      SET_STRING_ELT(info->enum_names, i, mkChar(name));
      H5free_memory(name);
    }
    UNPROTECT(1);
  }
}

/* Opens a file read-only without file locking, so a file that rhdf5 holds open
 * can still be read */
static hid_t open_readonly(const char *path) {
  hid_t fapl = H5Pcreate(H5P_FILE_ACCESS);
  if (fapl < 0) {
    return -1;
  }
  H5Pset_file_locking(fapl, 0, 1);
  hid_t file = H5Fopen(path, H5F_ACC_RDONLY, fapl);
  H5Pclose(fapl);
  return file;
}

static SEXP string_vector(int n) {
  return allocVector(STRSXP, n);
}

SEXP c_compound_members(SEXP path, SEXP dataset) {
  char err[ERR_LEN] = "";
  hid_t file = -1, dset = -1, type = -1;
  SEXP result = R_NilValue;

  H5Eset_auto2(H5E_DEFAULT, NULL, NULL);
  file = open_readonly(CHAR(STRING_ELT(path, 0)));
  if (file < 0) {
    set_error(err, "cannot open the file");
    goto done;
  }
  dset = H5Dopen2(file, CHAR(STRING_ELT(dataset, 0)), H5P_DEFAULT);
  if (dset < 0) {
    set_error(err, "cannot open the dataset");
    goto done;
  }
  type = H5Dget_type(dset);
  if (type < 0 || H5Tget_class(type) != H5T_COMPOUND) {
    set_error(err, "the dataset is not a compound dataset");
    goto done;
  }

  int n = H5Tget_nmembers(type);
  const char *fields[] = {"name",  "class", "size",     "sign", "order",
                          "variable", "utf8", "enum_names", "dims", ""};
  result = PROTECT(mkNamed(VECSXP, fields));
  SEXP names = SET_VECTOR_ELT(result, 0, string_vector(n));
  SEXP classes = SET_VECTOR_ELT(result, 1, string_vector(n));
  SEXP sizes = SET_VECTOR_ELT(result, 2, allocVector(INTSXP, n));
  SEXP signs = SET_VECTOR_ELT(result, 3, string_vector(n));
  SEXP orders = SET_VECTOR_ELT(result, 4, string_vector(n));
  SEXP variable = SET_VECTOR_ELT(result, 5, allocVector(LGLSXP, n));
  SEXP utf8 = SET_VECTOR_ELT(result, 6, allocVector(LGLSXP, n));
  SEXP enums = SET_VECTOR_ELT(result, 7, allocVector(VECSXP, n));
  SEXP dims = SET_VECTOR_ELT(result, 8, allocVector(VECSXP, n));

  for (int i = 0; i < n; i++) {
    char *name = H5Tget_member_name(type, (unsigned)i);
    SET_STRING_ELT(names, i, mkCharCE(name, CE_UTF8));
    H5free_memory(name);

    hid_t member = H5Tget_member_type(type, (unsigned)i);
    hid_t base = member;
    SEXP shape = allocVector(INTSXP, 0);
    SET_VECTOR_ELT(dims, i, shape);
    if (H5Tget_class(member) == H5T_ARRAY) {
      int nd = H5Tget_array_ndims(member);
      hsize_t *d = (hsize_t *)R_alloc((size_t)nd, sizeof(hsize_t));
      H5Tget_array_dims2(member, d);
      shape = allocVector(INTSXP, nd);
      SET_VECTOR_ELT(dims, i, shape);
      for (int k = 0; k < nd; k++) {
        INTEGER(shape)[k] = (int)d[k];
      }
      base = H5Tget_super(member);
    }
    member_info info;
    describe_type(base, &info);
    /* Store the unprotected enum names before anything else allocates */
    SET_VECTOR_ELT(enums, i, info.enum_names);
    SET_STRING_ELT(classes, i, mkChar(info.cls));
    INTEGER(sizes)[i] = info.size;
    SET_STRING_ELT(signs, i,
                   info.sign < 0 ? NA_STRING
                                 : mkChar(info.sign ? "signed" : "unsigned"));
    SET_STRING_ELT(orders, i, mkChar(info.big ? "BE" : "LE"));
    LOGICAL(variable)[i] = info.variable;
    LOGICAL(utf8)[i] = info.utf8;
    if (base != member) {
      H5Tclose(base);
    }
    H5Tclose(member);
  }
  UNPROTECT(1);

done:
  if (type >= 0) {
    H5Tclose(type);
  }
  if (dset >= 0) {
    H5Dclose(dset);
  }
  if (file >= 0) {
    H5Fclose(file);
  }
  if (err[0] != '\0') {
    Rf_error("%s", err);
  }
  return result;
}

/* Builds the type of one field from its specification list */
static hid_t field_type(SEXP spec, int native, char *err) {
  const char *cls = CHAR(STRING_ELT(VECTOR_ELT(spec, 1), 0));
  int size = INTEGER(VECTOR_ELT(spec, 2))[0];
  int is_signed = LOGICAL(VECTOR_ELT(spec, 3))[0];
  int variable = LOGICAL(VECTOR_ELT(spec, 4))[0];
  int utf8 = LOGICAL(VECTOR_ELT(spec, 5))[0];
  hid_t type = -1;

  if (strcmp(cls, "integer") == 0) {
    hid_t base = -1;
    switch (size) {
    case 1:
      base = is_signed ? (native ? H5T_NATIVE_INT8 : H5T_STD_I8LE)
                       : (native ? H5T_NATIVE_UINT8 : H5T_STD_U8LE);
      break;
    case 2:
      base = is_signed ? (native ? H5T_NATIVE_INT16 : H5T_STD_I16LE)
                       : (native ? H5T_NATIVE_UINT16 : H5T_STD_U16LE);
      break;
    case 4:
      base = is_signed ? (native ? H5T_NATIVE_INT32 : H5T_STD_I32LE)
                       : (native ? H5T_NATIVE_UINT32 : H5T_STD_U32LE);
      break;
    case 8:
      base = is_signed ? (native ? H5T_NATIVE_INT64 : H5T_STD_I64LE)
                       : (native ? H5T_NATIVE_UINT64 : H5T_STD_U64LE);
      break;
    default:
      set_error(err, "integer fields have a size of 1, 2, 4 or 8 bytes");
      return -1;
    }
    type = H5Tcopy(base);
  } else if (strcmp(cls, "float") == 0) {
    if (size == 4) {
      type = H5Tcopy(native ? H5T_NATIVE_FLOAT : H5T_IEEE_F32LE);
    } else if (size == 8) {
      type = H5Tcopy(native ? H5T_NATIVE_DOUBLE : H5T_IEEE_F64LE);
    } else {
      set_error(err, "float fields have a size of 4 or 8 bytes");
      return -1;
    }
  } else if (strcmp(cls, "bool") == 0) {
    int8_t zero = 0, one = 1;
    type = H5Tenum_create(native ? H5T_NATIVE_INT8 : H5T_STD_I8LE);
    H5Tenum_insert(type, "FALSE", &zero);
    H5Tenum_insert(type, "TRUE", &one);
  } else if (strcmp(cls, "string") == 0) {
    type = H5Tcopy(H5T_C_S1);
    H5Tset_size(type, variable ? H5T_VARIABLE : (size_t)size);
    H5Tset_cset(type, utf8 ? H5T_CSET_UTF8 : H5T_CSET_ASCII);
    if (!variable) {
      H5Tset_strpad(type, H5T_STR_NULLPAD);
    }
  } else {
    set_error(err, "unknown field class");
    return -1;
  }
  if (type < 0) {
    set_error(err, "cannot create a field type");
  }
  return type;
}

static double value_at(SEXP values, R_xlen_t row, char *err) {
  double v;
  if (TYPEOF(values) == INTSXP) {
    int x = INTEGER(values)[row];
    if (x == NA_INTEGER) {
      set_error(err, "integer fields cannot hold missing values");
      return 0;
    }
    v = x;
  } else if (TYPEOF(values) == LGLSXP) {
    int x = LOGICAL(values)[row];
    if (x == NA_LOGICAL) {
      set_error(err, "logical fields cannot hold missing values");
      return 0;
    }
    v = x;
  } else {
    v = REAL(values)[row];
  }
  return v;
}

/* Whether a double is a whole number the integer field can hold */
static int fits_integer(int size, int is_signed, double v) {
  double bits = size * 8.0;
  double low = is_signed ? -ldexp(1.0, (int)bits - 1) : 0.0;
  double high = is_signed ? ldexp(1.0, (int)bits - 1) : ldexp(1.0, (int)bits);
  return v == floor(v) && v >= low && v < high;
}

/* Writes one value of a numeric field into the row buffer */
static void put_number(char *dst, const char *cls, int size, int is_signed,
                       double v) {
  if (strcmp(cls, "float") == 0) {
    if (size == 4) {
      float f = (float)v;
      memcpy(dst, &f, 4);
    } else {
      memcpy(dst, &v, 8);
    }
    return;
  }
  switch (size) {
  case 1:
    if (is_signed) {
      int8_t x = (int8_t)v;
      memcpy(dst, &x, 1);
    } else {
      uint8_t x = (uint8_t)v;
      memcpy(dst, &x, 1);
    }
    break;
  case 2:
    if (is_signed) {
      int16_t x = (int16_t)v;
      memcpy(dst, &x, 2);
    } else {
      uint16_t x = (uint16_t)v;
      memcpy(dst, &x, 2);
    }
    break;
  case 4:
    if (is_signed) {
      int32_t x = (int32_t)v;
      memcpy(dst, &x, 4);
    } else {
      uint32_t x = (uint32_t)v;
      memcpy(dst, &x, 4);
    }
    break;
  default:
    if (is_signed) {
      int64_t x = (int64_t)v;
      memcpy(dst, &x, 8);
    } else {
      uint64_t x = (uint64_t)v;
      memcpy(dst, &x, 8);
    }
  }
}

/* fields is a list of field lists (name, class, size, signed, variable, utf8,
 * values). level is the gzip level (0 for none). */
SEXP c_compound_write(SEXP path, SEXP dataset, SEXP fields, SEXP nrow_,
                      SEXP level_) {
  char err[ERR_LEN] = "";
  hid_t file = -1, file_type = -1, mem_type = -1, space = -1, dcpl = -1,
        dset = -1;
  char *buffer = NULL;
  int nfields = (int)XLENGTH(fields);
  R_xlen_t nrow = (R_xlen_t)asReal(nrow_);
  int level = asInteger(level_);
  size_t *offsets = (size_t *)R_alloc((size_t)nfields, sizeof(size_t));
  size_t *sizes = (size_t *)R_alloc((size_t)nfields, sizeof(size_t));
  size_t row_size = 0;

  H5Eset_auto2(H5E_DEFAULT, NULL, NULL);

  /* Sizes come from the memory types, so build those first */
  hid_t *mem_types = (hid_t *)R_alloc((size_t)nfields, sizeof(hid_t));
  hid_t *file_types = (hid_t *)R_alloc((size_t)nfields, sizeof(hid_t));
  for (int i = 0; i < nfields; i++) {
    mem_types[i] = -1;
    file_types[i] = -1;
  }
  for (int i = 0; i < nfields; i++) {
    SEXP spec = VECTOR_ELT(fields, i);
    mem_types[i] = field_type(spec, 1, err);
    if (mem_types[i] < 0) {
      goto done;
    }
    file_types[i] = field_type(spec, 0, err);
    if (file_types[i] < 0) {
      goto done;
    }
    sizes[i] = H5Tget_size(mem_types[i]);
    offsets[i] = row_size;
    row_size += sizes[i];
  }
  mem_type = H5Tcreate(H5T_COMPOUND, row_size > 0 ? row_size : 1);
  size_t file_size = 0;
  for (int i = 0; i < nfields; i++) {
    file_size += H5Tget_size(file_types[i]);
  }
  file_type = H5Tcreate(H5T_COMPOUND, file_size > 0 ? file_size : 1);
  size_t file_offset = 0;
  for (int i = 0; i < nfields; i++) {
    const char *name = CHAR(STRING_ELT(VECTOR_ELT(VECTOR_ELT(fields, i), 0), 0));
    if (H5Tinsert(mem_type, name, offsets[i], mem_types[i]) < 0 ||
        H5Tinsert(file_type, name, file_offset, file_types[i]) < 0) {
      set_error(err, "cannot add a field to the compound type");
      goto done;
    }
    file_offset += H5Tget_size(file_types[i]);
  }

  if (nrow > 0) {
    buffer = (char *)calloc((size_t)nrow, row_size > 0 ? row_size : 1);
    if (buffer == NULL) {
      set_error(err, "cannot allocate the row buffer");
      goto done;
    }
  }
  for (int i = 0; i < nfields; i++) {
    SEXP spec = VECTOR_ELT(fields, i);
    const char *cls = CHAR(STRING_ELT(VECTOR_ELT(spec, 1), 0));
    int size = INTEGER(VECTOR_ELT(spec, 2))[0];
    int is_signed = LOGICAL(VECTOR_ELT(spec, 3))[0];
    int variable = LOGICAL(VECTOR_ELT(spec, 4))[0];
    SEXP values = VECTOR_ELT(spec, 6);
    if (XLENGTH(values) != nrow) {
      set_error(err, "every field needs one value per row");
      goto done;
    }
    for (R_xlen_t row = 0; row < nrow; row++) {
      char *dst = buffer + (size_t)row * row_size + offsets[i];
      if (strcmp(cls, "string") == 0) {
        SEXP elt = STRING_ELT(values, row);
        if (elt == NA_STRING) {
          set_error(err, "string fields cannot hold missing values");
          goto done;
        }
        const char *text = translateCharUTF8(elt);
        size_t len = strlen(text);
        if (variable) {
          char *copy = (char *)R_alloc(len + 1, 1);
          memcpy(copy, text, len + 1);
          memcpy(dst, &copy, sizeof(char *));
        } else {
          if (len > (size_t)size) {
            set_error(err, "a string is longer than its fixed field");
            goto done;
          }
          memcpy(dst, text, len);
        }
      } else {
        double v = value_at(values, row, err);
        if (err[0] != '\0') {
          goto done;
        }
        if (strcmp(cls, "bool") == 0) {
          int8_t b = v != 0;
          memcpy(dst, &b, 1);
        } else {
          if (strcmp(cls, "integer") == 0 && !fits_integer(size, is_signed, v)) {
            set_error(err, "a value does not fit its integer field");
            goto done;
          }
          put_number(dst, cls, size, is_signed, v);
        }
      }
    }
  }

  file = H5Fcreate(CHAR(STRING_ELT(path, 0)), H5F_ACC_TRUNC, H5P_DEFAULT,
                   H5P_DEFAULT);
  if (file < 0) {
    set_error(err, "cannot create the file");
    goto done;
  }
  hsize_t dims[1] = {(hsize_t)nrow};
  space = H5Screate_simple(1, dims, NULL);
  dcpl = H5Pcreate(H5P_DATASET_CREATE);
  if (level > 0) {
    hsize_t chunk[1] = {nrow > 0 ? (hsize_t)(nrow < 1048576 ? nrow : 1048576)
                                 : 1};
    H5Pset_chunk(dcpl, 1, chunk);
    H5Pset_deflate(dcpl, (unsigned)level);
  }
  dset = H5Dcreate2(file, CHAR(STRING_ELT(dataset, 0)), file_type, space,
                    H5P_DEFAULT, dcpl, H5P_DEFAULT);
  if (dset < 0) {
    set_error(err, "cannot create the dataset");
    goto done;
  }
  if (nrow > 0 &&
      H5Dwrite(dset, mem_type, H5S_ALL, H5S_ALL, H5P_DEFAULT, buffer) < 0) {
    set_error(err, "cannot write the dataset");
    goto done;
  }

done:
  free(buffer);
  for (int i = 0; i < nfields; i++) {
    if (mem_types[i] >= 0) {
      H5Tclose(mem_types[i]);
    }
    if (file_types[i] >= 0) {
      H5Tclose(file_types[i]);
    }
  }
  if (dset >= 0) {
    H5Dclose(dset);
  }
  if (dcpl >= 0) {
    H5Pclose(dcpl);
  }
  if (space >= 0) {
    H5Sclose(space);
  }
  if (mem_type >= 0) {
    H5Tclose(mem_type);
  }
  if (file_type >= 0) {
    H5Tclose(file_type);
  }
  if (file >= 0) {
    H5Fclose(file);
  }
  if (err[0] != '\0') {
    Rf_error("%s", err);
  }
  return R_NilValue;
}

static const R_CallMethodDef call_methods[] = {
    {"c_compound_members", (DL_FUNC)&c_compound_members, 2},
    {"c_compound_write", (DL_FUNC)&c_compound_write, 5},
    {NULL, NULL, 0}};

void R_init_anndata_claude(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
