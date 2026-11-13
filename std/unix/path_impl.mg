mod path_impl
# Unix path rules used by the portable path module.

use "std:strings" as strings

pub separator() u8:
    ret 47
..

pub isAbsolute(path str) bool:
    ret strings.byteAt(path, 0) == 47
..
