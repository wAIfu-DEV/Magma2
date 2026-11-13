mod path_impl
# Windows path rules used by the portable path module.

use "std:strings" as strings

pub separator() u8:
    ret 92
..

pub isAbsolute(path str) bool:
    n := path.countBytes()
    if strings.byteAt(path, 0) == 47 || strings.byteAt(path, 0) == 92:
        ret true
    ..
    ret n >= 3 && strings.byteAt(path, 1) == 58 && (strings.byteAt(path, 2) == 47 || strings.byteAt(path, 2) == 92)
..
