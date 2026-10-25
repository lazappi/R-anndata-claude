# anndata.claude

`anndata.claude` is an R port of Python
[anndata](https://anndata.readthedocs.io) for annotated data matrices.

Its first priority is full compatibility with the anndata on-disk
formats (h5ad, and zarr later). An object read from a file is equal
whichever language wrote it, and files written by R are structurally
equivalent to files written by Python. The in-memory `AnnData` object
supports that goal, with full feature parity as the long-term aim.

## Relationship to Python anndata

Python anndata release 0.13.4 is the only reference for behaviour. This
package matches its observable behaviour (values, errors, warnings and
files written) but is idiomatic R rather than a line-by-line
translation.

The package is developed with an autonomous loop and is at an early
stage. Nothing is exported yet.

## Acknowledgements

Thanks to the authors of Python anndata, whose design and file formats
this package follows.

## License

BSD 3-Clause, see `LICENSE.md`.
