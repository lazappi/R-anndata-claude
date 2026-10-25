# Chunks of X

Internal helpers behind `AnnData$chunked_X()` and `AnnData$chunk_X()`.
Chunks are read through `[` on X, so a backed X reads only the rows it
needs.

## Usage

``` r
chunked_x(adata, chunk_size, call)

chunk_x(adata, select, replace, call)
```

## Arguments

- adata:

  An `AnnData`.

- chunk_size, select, replace:

  As the methods' arguments.

- call:

  The call reported by errors.
