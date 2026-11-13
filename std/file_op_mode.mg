mod file_op_mode
# Composable flags controlling how files are opened.

# File open mode flags.
# @complexity O(1).
pub const FLAG_READ     u8 = 1
pub const FLAG_WRITE    u8 = 2
pub const FLAG_APPEND   u8 = 4
pub const FLAG_CREATE   u8 = 8
pub const FLAG_TRUNCATE u8 = 16

pub OpenMode(
    bits u8
)

# Returns a copy of the mode with read access enabled.
# @complexity O(1)
# @example
#   openMode := file.mode().read()
OpenMode.read() OpenMode:
    op OpenMode = *this
    op.bits = op.bits | FLAG_READ
    ret op
..

# Returns a copy of the mode with write access enabled.
# @complexity O(1)
OpenMode.write() OpenMode:
    op OpenMode = *this
    op.bits = op.bits | FLAG_WRITE
    ret op
..

# Returns a copy configured to append writes at the end of the file.
# This also enables write access.
# @complexity O(1)
OpenMode.append() OpenMode:
    op OpenMode = *this
    op.bits = op.bits | FLAG_APPEND | FLAG_WRITE
    ret op
..

# Creates the file when it does not exist. Existing contents are preserved.
# @complexity O(1)
OpenMode.create() OpenMode:
    op OpenMode = *this
    op.bits = op.bits | FLAG_CREATE
    ret op
..

# Truncates an existing file to zero bytes when opened. This also enables
# writing, but does not imply creation.
# @complexity O(1)
# @warning Opening with this mode destroys existing file contents.
# @example
#   openMode := file.mode().write().create().truncate()
OpenMode.truncate() OpenMode:
    op OpenMode = *this
    op.bits = op.bits | FLAG_TRUNCATE | FLAG_WRITE
    ret op
..
