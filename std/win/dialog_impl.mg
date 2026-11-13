mod dialog_impl_win
# Modern Windows file dialogs implemented directly with IFileDialog.
# Derived from Native File Dialog 1.1.6; see licenses/NATIVE_FILE_DIALOG.txt.

use "std:allocator" as allocator
use "std:builder" as builder
use "std:win/types" as win
use "std:cast" as cast
use "std:errors" as errors
use "std:slices" as slices
use "std:strings" as strings
use "std:utf8" as utf8

link "ole32"
link "shell32"

Guid(
    data1 i32
    data2 i16
    data3 i16
    data40 i8
    data41 i8
    data42 i8
    data43 i8
    data44 i8
    data45 i8
    data46 i8
    data47 i8
)

const clsidOpen := Guid(data1=-602121572, data2=-6006, data3=19934, data40=-91, data41=-95, data42=96, data43=-8, data44=42, data45=32, data46=-82, data47=-9)
const clsidSave := Guid(data1=-1061887245, data2=-17887, data3=18291, data40=-115, data41=-70, data42=51, data43=94, data44=-55, data45=70, data46=-21, data47=-117)
const iidOpen := Guid(data1=-713264504, data2=-11091, data3=18280, data40=-66, data41=2, data42=-99, data43=-106, data44=-107, data45=50, data46=-39, data47=96)
const iidSave := Guid(data1=-2068001501, data2=24542, data3=19675, data40=-82, data41=-92, data42=-81, data43=100, data44=-72, data45=61, data46=120, data47=-85)
const iidShellItem := Guid(data1=1132621086, data2=-6376, data3=17134, data40=-68, data41=85, data42=-95, data43=-30, data44=97, data45=-61, data46=123, data47=-2)

ext ext_CoInitializeEx CoInitializeEx(reserved win.LPVOID, flags win.DWORD) win.HRESULT
ext ext_CoUninitialize CoUninitialize() void
ext ext_CoCreateInstance CoCreateInstance(classId win.LPCVOID, outer win.LPVOID, context win.DWORD, interfaceId win.LPCVOID, result win.LPVOID*) win.HRESULT
ext ext_CoTaskMemFree CoTaskMemFree(value win.LPVOID) void
ext ext_SHCreateItemFromParsingName SHCreateItemFromParsingName(path win.LPCWSTR, context win.LPVOID, interfaceId win.LPCVOID, result win.LPVOID*) win.HRESULT

guidOpenClass() ptr:
    ret addrof clsidOpen
..
guidSaveClass() ptr:
    ret addrof clsidSave
..
guidOpenInterface() ptr:
    ret addrof iidOpen
..
guidSaveInterface() ptr:
    ret addrof iidSave
..
guidShellItem() ptr:
    ret addrof iidShellItem
..

InputFilter(
    name str
    extensions str
)

FilterSpec(
    name u16*
    pattern u16*
)

FileDialogVtable(
    queryInterface fn(ptr, ptr, ptr*) i32
    addRef fn(ptr) u32
    release fn(ptr) u32
    show fn(ptr, ptr) i32
    setFileTypes fn(ptr, u32, FilterSpec*) i32
    setFileTypeIndex ptr
    getFileTypeIndex ptr
    advise ptr
    unadvise ptr
    setOptions fn(ptr, u32) i32
    getOptions fn(ptr, u32*) i32
    setDefaultFolder fn(ptr, ptr) i32
    setFolder ptr
    getFolder ptr
    getCurrentSelection ptr
    setFileName fn(ptr, u16*) i32
    getFileName ptr
    setTitle fn(ptr, u16*) i32
    setOkButtonLabel ptr
    setFileNameLabel ptr
    getResult fn(ptr, ptr*) i32
    addPlace ptr
    setDefaultExtension ptr
    close ptr
    setClientGuid ptr
    clearClientData ptr
    setFilter ptr
)

ShellItemVtable(
    queryInterface ptr
    addRef ptr
    release fn(ptr) u32
    bindToHandler ptr
    getParent ptr
    getDisplayName fn(ptr, u32, u16**) i32
    getAttributes ptr
    compare ptr
)

succeeded(result i32) bool:
    ret result >= 0
..

cancelled(result i32) bool:
    ret result == cast.u32toi32(0x800704C7)
..

dialogTable(dialog ptr) FileDialogVtable*:
    address ptr* = dialog
    ret cast.reinterpret[FileDialogVtable](*address)
..

shellTable(item ptr) ShellItemVtable*:
    address ptr* = item
    ret cast.reinterpret[ShellItemVtable](*address)
..

releaseDialog(dialog ptr) void:
    if dialog != none:
        table := dialogTable(dialog)
        table.release(dialog)
    ..
..

releaseShell(item ptr) void:
    if item != none:
        table := shellTable(item)
        table.release(item)
    ..
..

finishCom(result i32) void:
    if result == 0 || result == 1:
        ext_CoUninitialize()
    ..
..

startCom() !i32:
    result := ext_CoInitializeEx(none, 2)
    # RPC_E_CHANGED_MODE means COM was already initialized in another model.
    if succeeded(result) == false && result != cast.u32toi32(0x80010106):
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "CoInitializeEx failed")
    ..
    ret result
..

createDialog(save bool) !ptr:
    dialog ptr = none
    result i32 = 0
    if save:
        result = ext_CoCreateInstance(guidSaveClass(), none, 23, guidSaveInterface(), addrof dialog)
    else:
        result = ext_CoCreateInstance(guidOpenClass(), none, 23, guidOpenInterface(), addrof dialog)
    ..
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "CoCreateInstance for IFileDialog failed")
    ..
    ret dialog
..

extensionPattern(a allocator.Allocator, extensions str) !$str:
    out := try builder.new()
    defer out.free()
    start u64 = 0
    i u64 = 0
    loop i <= extensions.countBytes():
        if i == extensions.countBytes() || strings.byteAt(extensions, i) == 44:
            if i > start:
                if out.isEmpty() == false:
                    try out.appendBorrowed(";")
                ..
                try out.appendBorrowed("*.")
                try out.appendBorrowed(strings.fromPtrNoCopy(cast.utop(cast.ptou(strings.toPtr(extensions)) + start), i - start))
            ..
            start = i + 1
        ..
        i = i + 1
    ..
    if out.isEmpty():
        try out.appendBorrowed("*.*")
    ..
    ret try out.build()
..

setFilters(a allocator.Allocator, dialog ptr, rawFilters ptr, count u64) !void:
    if count == 0:
        ret
    ..
    filters InputFilter* = rawFilters
    specs := try a.allocT[FilterSpec](count)
    names := try a.allocT[u16*](count)
    patterns := try a.allocT[u16*](count)
    for built u64 = 0 to count:
        names[built] = none
        patterns[built] = none
    ..
    for built u64 = 0 to count:
        nameUnits := try utf8.utf8To16NT(filters[built].name)
        pattern := try extensionPattern(a, filters[built].extensions)
        patternUnits := try utf8.utf8To16NT(pattern)
        pattern.free()
        names[built] = slices.toPtr(nameUnits)
        patterns[built] = slices.toPtr(patternUnits)
        specs[built] = FilterSpec(name=names[built], pattern=patterns[built])
    ..
    table := dialogTable(dialog)
    result := table.setFileTypes(dialog, cast.u64to32(count), specs)
    for i u64 = 0 to count:
        a.free(names[i])
        a.free(patterns[i])
    ..
    a.free(names)
    a.free(patterns)
    a.free(specs)
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.SetFileTypes failed")
    ..
..

setDefaultPath(a allocator.Allocator, dialog ptr, path str) !void:
    if path.countBytes() == 0:
        ret
    ..
    wide := try utf8.utf8To16NT(path)
    defer slices.free(wide)
    item ptr = none
    result := ext_SHCreateItemFromParsingName(slices.toPtr(wide), none, guidShellItem(), addrof item)
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "default dialog path is invalid")
    ..
    defer releaseShell(item)
    table := dialogTable(dialog)
    result = table.setDefaultFolder(dialog, item)
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.SetDefaultFolder failed")
    ..
..

configureText(a allocator.Allocator, dialog ptr, title str, defaultName str) !void:
    table := dialogTable(dialog)
    if title.countBytes() > 0:
        wideTitle := try utf8.utf8To16NT(title)
        result := table.setTitle(dialog, slices.toPtr(wideTitle))
        slices.free(wideTitle)
        if succeeded(result) == false:
            throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.SetTitle failed")
        ..
    ..
    if defaultName.countBytes() > 0:
        wideName := try utf8.utf8To16NT(defaultName)
        result := table.setFileName(dialog, slices.toPtr(wideName))
        slices.free(wideName)
        if succeeded(result) == false:
            throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.SetFileName failed")
        ..
    ..
..

selectionFromDialog(a allocator.Allocator, dialog ptr) !$str:
    table := dialogTable(dialog)
    item ptr = none
    result := table.getResult(dialog, addrof item)
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.GetResult failed")
    ..
    defer releaseShell(item)
    shell := shellTable(item)
    wide u16* = none
    result = shell.getDisplayName(item, 0x80058000, addrof wide)
    if succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IShellItem.GetDisplayName failed")
    ..
    defer ext_CoTaskMemFree(wide)
    count u64 = 0
    loop wide[count] != 0:
        count = count + 1
    ..
    path := try utf8.utf16to8(slices.fromPtr(wide, count))
    ret path
..

show(a allocator.Allocator, save bool, directory bool, rawFilters ptr, filterCount u64, defaultPath str, defaultName str, title str, parent ptr) !$str:
    comResult := try startCom()
    defer finishCom(comResult)
    dialog := try createDialog(save)
    defer releaseDialog(dialog)
    try setFilters(a, dialog, rawFilters, filterCount)
    try setDefaultPath(a, dialog, defaultPath)
    try configureText(a, dialog, title, defaultName)
    if directory:
        table := dialogTable(dialog)
        options u32 = 0
        result := table.getOptions(dialog, addrof options)
        if succeeded(result) == false:
            throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.GetOptions failed")
        ..
        result = table.setOptions(dialog, options | 0x20)
        if succeeded(result) == false:
            throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.SetOptions failed")
        ..
    ..
    table := dialogTable(dialog)
    result := table.show(dialog, parent)
    if cancelled(result):
        throw errors.cancelled("file dialog cancelled")
    elif succeeded(result) == false:
        throw errors.native(cast.u64to32(cast.itou(cast.i32to64(result))), "IFileDialog.Show failed")
    ..
    ret try selectionFromDialog(a, dialog)
..

pub openFile(a allocator.Allocator, filters ptr, filterCount u64, defaultPath str, title str, parent ptr) !$str:
    ret try show(a, false, false, filters, filterCount, defaultPath, "", title, parent)
..

pub saveFile(a allocator.Allocator, filters ptr, filterCount u64, defaultPath str, defaultName str, title str, parent ptr) !$str:
    ret try show(a, true, false, filters, filterCount, defaultPath, defaultName, title, parent)
..

pub openDir(a allocator.Allocator, defaultPath str, title str, parent ptr) !$str:
    ret try show(a, false, true, none, 0, defaultPath, "", title, parent)
..
