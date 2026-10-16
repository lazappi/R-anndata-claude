"""Pack the zarr fixture directory into one gzipped tar archive.

Usage: pack_zarr_fixtures.py <zarr fixtures dir> <archive>

R CMD check notes the hidden files (`.zarray`) and long paths of a zarr
directory tree inside a package, so the fixtures are committed as an archive
that the tests unpack. Entries are sorted and carry no owner or time, so
packing the same stores twice gives the same archive.
"""

import gzip
import sys
import tarfile
from pathlib import Path


def main(directory, archive):
    directory = Path(directory)
    with open(archive, "wb") as raw:
        # mtime 0 keeps the gzip header the same between runs
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w") as tar:
                for path in sorted(directory.rglob("*")):
                    info = tar.gettarinfo(path, arcname=str(path.relative_to(directory)))
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    if path.is_file():
                        with open(path, "rb") as f:
                            tar.addfile(info, f)
                    else:
                        tar.addfile(info)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
