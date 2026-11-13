mod types
# Common Windows API scalar, handle, pointer, and string types.
#
# These aliases follow the names used by the Windows SDK. They are aliases,
# not wrappers, so they preserve the ABI of the underlying C types.

use "std:c" as c

# Fixed-width Windows scalar types.
pub alias BOOL      = c.int
pub alias BOOLEAN   = c.unsigned_char
pub alias BYTE      = c.unsigned_char
pub alias CHAR      = c.char
pub alias WCHAR     = c.wchar_t
pub alias SHORT     = c.short
pub alias USHORT    = c.unsigned_short
pub alias INT       = c.int
pub alias UINT      = c.unsigned_int
pub alias LONG      = c.long
pub alias ULONG     = c.unsigned_long
pub alias LONGLONG  = c.long_long
pub alias ULONGLONG = c.unsigned_long_long
pub alias WORD      = c.unsigned_short
pub alias DWORD     = c.unsigned_long
pub alias HRESULT   = LONG
pub alias ATOM      = WORD
pub alias LANGID    = WORD
pub alias LCID      = DWORD
pub alias COLORREF  = DWORD
pub alias ACCESS_MASK = DWORD

# Pointer-sized integer types.
pub alias INT_PTR   = c.intptr_t
pub alias UINT_PTR  = c.uintptr_t
pub alias LONG_PTR  = c.intptr_t
pub alias ULONG_PTR = c.uintptr_t
pub alias DWORD_PTR = c.uintptr_t
pub alias LPARAM    = LONG_PTR
pub alias WPARAM    = UINT_PTR
pub alias LRESULT   = LONG_PTR
pub alias SIZE_T    = c.size_t
pub alias SSIZE_T   = c.ptrdiff_t

# Opaque handles. Windows declares the individual handle kinds as distinct C
# pointer types, but Magma's FFI represents opaque native pointers as `ptr`.
pub alias HANDLE    = ptr
pub alias HINSTANCE = ptr
pub alias HMODULE   = ptr
pub alias HWND      = ptr
pub alias HLOCAL    = ptr
pub alias HGLOBAL   = ptr
pub alias HDC       = ptr
pub alias HGDIOBJ   = ptr
pub alias HBITMAP   = ptr
pub alias HBRUSH    = ptr
pub alias HCURSOR   = ptr
pub alias HICON     = ptr
pub alias HMENU     = ptr
pub alias HKEY      = ptr

# Generic pointer and UTF-16 string pointer types.
pub alias PVOID   = ptr
pub alias LPVOID  = ptr
pub alias LPCVOID = ptr
pub alias PBOOL   = BOOL*
pub alias LPBOOL  = BOOL*
pub alias PBYTE   = BYTE*
pub alias LPBYTE  = BYTE*
pub alias PWORD   = WORD*
pub alias LPWORD  = WORD*
pub alias PDWORD  = DWORD*
pub alias LPDWORD = DWORD*
pub alias PINT    = INT*
pub alias LPINT   = INT*
pub alias PUINT   = UINT*
pub alias LPUINT  = UINT*
pub alias PLONG   = LONG*
pub alias LPLONG  = LONG*
pub alias PULONG  = ULONG*
pub alias LPULONG = ULONG*
pub alias PSTR    = CHAR*
pub alias LPSTR   = CHAR*
pub alias PCSTR   = CHAR*
pub alias LPCSTR  = CHAR*
pub alias PWSTR   = WCHAR*
pub alias LPWSTR  = WCHAR*
pub alias PCWSTR  = WCHAR*
pub alias LPCWSTR = WCHAR*

# Common subsystem-specific scalar aliases.
pub alias INTERNET_PORT = WORD
