# X is stored in layers under the NA key

Since anndata 0.13 Python stores `X` in `layers` under the `None` key, so `None` appears in `layers.keys()` and the repr shows `layers: None (.X), ...`.
R lists cannot have a `NULL` name, so `X` is stored in `layers` under the `NA` key instead: `adata$X` is an alias for `adata$layers[[NA]]` and `names(adata$layers)` includes `NA` when X is present.
`NA` was chosen over a string key such as `"X"`, which would collide with a user layer of that name.
Base R `[[` returns `NULL` for an `NA` name, so the layers class provides its own `[[`, `[[<-` and `$` methods that treat `NA` as the X key.
The on-disk layout is unchanged because Python writes `X` to `/X` and not inside `/layers`.
