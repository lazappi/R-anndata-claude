# printing lists settings, values and descriptions

    Code
      print(anndata_settings)
    Output
      <anndata_settings>
        remove_unused_categories                       TRUE   Remove unused categories from factors
        check_uniqueness                               TRUE   Check uniqueness of obs names on creation
        allow_write_nullable_strings                   NULL   Allow writing nullable string arrays (NULL infers it)
        disallow_forward_slash_in_h5ad                 TRUE   Disallow `/` in keys for h5ad files
        write_csr_csc_indices_with_min_possible_dtype  FALSE  Write sparse indices with the minimum unsigned dtype
        restrict_index_types                           TRUE   Force string indices on creation and when setting obs/var

---

    Code
      print(anndata_settings)
    Output
      <anndata_settings>
        remove_unused_categories                       TRUE   Remove unused categories from factors
        check_uniqueness                               FALSE  Check uniqueness of obs names on creation
        allow_write_nullable_strings                   TRUE   Allow writing nullable string arrays (NULL infers it)
        disallow_forward_slash_in_h5ad                 TRUE   Disallow `/` in keys for h5ad files
        write_csr_csc_indices_with_min_possible_dtype  FALSE  Write sparse indices with the minimum unsigned dtype
        restrict_index_types                           TRUE   Force string indices on creation and when setting obs/var

