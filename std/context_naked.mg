mod context_default

use "std:allocator" as alc
use "std:context" as context
use "std:executor" as executor

# Minimal program context for --naked: allocations fail unless a subsystem is
# given an allocator explicitly, and submitted work runs on the calling thread.
pub noctx newDefault() !context.Ctx:
    ret context.new(alc.null(), executor.singleThread())
..
