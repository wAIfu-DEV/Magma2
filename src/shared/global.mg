mod global_state

use "std:hash_map" hm
use "std:future" future
use "std:locker" lck
use "std:atomic" atomic
use "std:adaptive_spinlock" adsl
use "std:stable_list" sl
use "std:writer" wr

use "../helper/logger" lg
use "node_types" nt
use "filectx" fctx

pub alias ModuleID = str

pub const UNSET str = "unset"

pub global logger lg.Logger

pub global cwd str = UNSET
pub global stdLibRoot str = UNSET
pub global mainUniqueName str = UNSET

pub global errTraceSlots u64 = 1024

pub global pipelines hm.HashMap[future.Future[error]]
pub global lockPipelines lck.Locker
pub global runningPipelines atomic.U64

pub global files hm.HashMap[fctx.FileCtx*]
pub global lockFiles lck.Locker
pub global importedFiles sl.StableList[fctx.FileCtx]
pub global lockImportedFiles lck.Locker
pub global lockStdout lck.Locker

pub global pipelineRunner fn(str) !$future.Future[error]

pub global moduleNames hm.HashMap[ModuleID]
pub global lockModuleNames lck.Locker

pub initGlobal() !void:
    pipelines = try hm.new[future.Future[error]](16, none)
    lockPipelines = adsl.new().proto()

    runningPipelines = atomic.newU64(0)

    files = try hm.new[fctx.FileCtx*](16, none)
    lockFiles = adsl.new().proto()
    importedFiles = try sl.new[fctx.FileCtx](ctx.alloc, none)
    lockImportedFiles = adsl.new().proto()
    lockStdout = adsl.new().proto()

    moduleNames = try hm.new[ModuleID](16, none)
    lockModuleNames = adsl.new().proto()
..

pub TempLogger(
    x u8
)

pub startLog(lvl lg.LogLevel) !$TempLogger:
    if lvl < logger.level:
        ret TempLogger(
            x=0
        )
    ..

    try lockStdout.lock()
    ret TempLogger(
        x=1
    )
..

destr TempLogger.end() !void:
    if this.x == 0:
        ret
    ..
    lockStdout.unlock()
..

TempLogger.write(bytes str) !TempLogger*:
    if this.x == 0:
        ret this
    ..
    try logger.writer.write(bytes)
    ret this
..

TempLogger.writeLn(bytes str) !TempLogger*:
    if this.x == 0:
        ret this
    ..
    try logger.writer.writeLn(bytes)
    ret this
..

TempLogger.writeInt64(num i64) !TempLogger*:
    if this.x == 0:
        ret this
    ..
    try logger.writer.writeInt64(num)
    ret this
..

TempLogger.writeUint64(num u64) !TempLogger*:
    if this.x == 0:
        ret this
    ..
    try logger.writer.writeUint64(num)
    ret this
..
