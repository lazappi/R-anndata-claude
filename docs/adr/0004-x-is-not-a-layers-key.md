# X is not exposed as a key of layers

Since anndata 0.13 Python stores `X` in `layers` under the `None` key, so `None` appears in `layers.keys()` and the repr shows `layers: None (.X), ...`.
R lists cannot have a `NULL` name, and any string key (e.g. `"X"`) would collide with a user layer of that name, so in R `X` is held separately and `names(adata$layers)` lists only named layers.
Observable behaviour is otherwise matched: the printed repr includes `None (.X)` exactly as Python does, clearing or replacing `layers` keeps `X` (with Python's warning), and the on-disk layout is unchanged because Python writes `X` to `/X` and not inside `/layers`.
