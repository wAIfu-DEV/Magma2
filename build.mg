mod main

use "std:process" proc
use "std:fs"      fs

main() !u32:
    fs.removeFile("./magma")

    process := try proc.spawn("magma", []str(
        "--preset", "fast-runtime",
        "--std", "std",
        "--out", "magma",
        "main.mg",
    ))

    code := try process.await()
    ret code
..