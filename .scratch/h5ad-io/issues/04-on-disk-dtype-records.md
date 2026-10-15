# On-disk dtype preservation mechanism

Status: ready-for-agent
Type: task
Blocked by: 02, 03, core-object/01, core-object/10, core-object/11

## What

Implement the mechanism from "On-disk dtype preservation": record the On-disk dtype on read where R's native type differs (float32, int8, int16, int64, unsigned ints, sparse index dtypes) and restore it on write.

- Values no longer representable raise a classed error naming the path, and are never truncated or wrapped
- The record survives subset, copy and transpose from `core-object` and is invisible to arithmetic and printing
- 64-bit integer policy from the encoding table
- Helper used by every encoding ticket below

## Acceptance criteria

- Tested for vectors, matrices and arrays of every dtype
- Survival through subset, copy and transpose is tested
- Overflow on write errors with the documented class
- `scripts/check.sh` passes

## Decisions (human, 2026-10-15)

- int64 and uint64: read as double when every value has magnitude below 2^53, otherwise a classed error naming the path.
  `bit64` is not a dependency.
- An int32 dataset containing -2147483648 (R's `NA_integer_` bit pattern) is read as double with an int32 record, so it writes back unchanged and is never silently `NA`
- rec-array fields have no dtype records (ADR 0005)

## Comments
