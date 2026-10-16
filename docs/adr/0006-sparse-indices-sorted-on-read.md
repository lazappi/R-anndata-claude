# Sparse indices are sorted on read

scipy allows the indices within a row of a CSR matrix (or a column of a CSC matrix) to be unsorted, and h5py writes them in whatever order they are in, but `Matrix` requires them sorted.
So reading a `csr_matrix` or `csc_matrix` Element with unsorted indices sorts them, with their `data`, and writing it back stores them sorted.
The matrix is the same, Python reads both files as equal and only the on-disk order of `indices` and `data` differs.
We accept this deviation from "on disk is non-negotiable" rather than keep a permutation outside `Matrix`, because the order carries no meaning and anndata itself does not promise to keep it.
Round-trip tests compare such matrices by value, and Structural equivalence still holds for every Element whose indices were already sorted, which includes everything anndata and R write.
