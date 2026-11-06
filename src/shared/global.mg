mod global_state

use "std:hash_map" hm
use "std:future" future
use "std:locker" lck
use "std:adaptive_spinlock" adsl

use "../helper/logger" lg
use "filectx" fctx

pub alias ModuleID = str

const UNSET str = "unset"

pub global logger lg.Logger

pub global cwd str = UNSET
pub global stdLibRoot str = UNSET
pub global mainUniqueName str = UNSET

pub global errTraceSlots u64 = 1024

pub global pipelines hm.HashMap[future.Future[error]]
pub global lockPipelines lck.Locker

pub global files hm.HashMap[fctx.FileCtx]
pub global lockFiles lck.Locker

pub global moduleNames hm.HashMap[ModuleID]
pub global lockModuleNames lck.Locker

pub initGlobal() !void:
    pipelines = try hm.new[future.Future[error]](32, none)
    lockPipelines = adsl.new().proto()

    files = try hm.new[fctx.FileCtx](32, none)
    lockFiles = adsl.new().proto()

    moduleNames = try hm.new[ModuleID](32, none)
    lockModuleNames = adsl.new().proto()
..

pub registerId(moduleName str, id ModuleID) !void:
    try lockModuleNames.lock()
    defer lockModuleNames.unlock()
    
    i, e := moduleNames.indexOf(moduleName)
    if e.nok():
        
    ..
..
