mod destr_register

use "std:cast" as cast
use "std:list" as list

# internal
DestrCall(
    arg ptr
    func ptr
    hasArg bool
)

pub DestrRegister(
    data list.List[DestrCall]
)

pub new() !$DestrRegister:
    data := try list.new[DestrCall](ctx.alloc, none)
    ret DestrRegister(data=move data)
..

DestrRegister.add[T](arg T*, fn (T*) void) !void:
    try this.data.pushRight(DestrCall(arg=arg,func=func,hasArg=true))
..

DestrRegister.addNoArg(fn () void) !void:
    try this.data.pushRight(DestrCall(arg=none,func=func,hasArg=false))
..

DestrRegister.remove(arg ptr, func ptr) !void:
    view := this.data.view()
    for i := 0 to view.count():
        item := view[i]

        if item.arg == arg && item.func == func:
            view[i] = DestrCall(arg=none,func=none,hasArg=false)
        ..
    ..
..

destr DestrRegister.destroyAll() void:
    view := this.data.view()
    i := view.count() - 1
    
    # exits on overflow
    loop i < view.count(): defer i = i - 1
        call := view[i]

        if call.func == none:
            continue
        ..

        if call.hasArg:
            f1 := *cast.reinterpret[(ptr) void](addrof call.func)
            f1(call.arg)
        else:
            f2 := *cast.reinterpret[() void](addrof call.func)
            f2()
        ..
    ..
    this.data.free()
..

destr DestrRegister.releaseAll() void:
    this.data.free()
..