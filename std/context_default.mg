mod context_default

use "std:context" as context
use "std:allocator" as alc
use "std:heap" as heap
use "std:thread_pool" as tp
use "std:atomic" as atomic
use "std:executor" as executor
use "std:errors" as errors

initFlag atomic.U8
allocator alc.Allocator
thread_pool tp.ThreadPool

pub noctx newDefault() !context.Ctx:
    bootstrapAllocator := heap.allocator()
    ctx = context.new(bootstrapAllocator, executor.null())
    state := initFlag.load()
    if state == 1:
        throw errors.invalidArgument("default context initialization is reentrant")
    ..
    if state == 3:
        throw errors.invalidArgument("default context initialization previously failed")
    ..
    if state != 2:
        initFlag.store(1)
        onerror initFlag.store(3)
        allocator = bootstrapAllocator
        thread_pool = try tp.newDefault(allocator)
        initFlag.store(2)
    ..
    ret context.new(allocator, thread_pool.executor())
..

pub noctx newNull() context.Ctx:
    ret context.new(alc.null(), executor.null())
..
