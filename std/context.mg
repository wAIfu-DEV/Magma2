mod context

use "std:allocator" as alc
use "std:executor" as exe

pub Ctx(
    alloc alc.Allocator
    exec exe.Executor
)

pub noctx new(allocator alc.Allocator, executor exe.Executor) Ctx:
    ret Ctx(
        alloc=allocator,
        exec=executor,
    )
..
