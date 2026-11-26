mod global_state

use "std:hash_map" hm
use "std:future" future
use "std:locker" lck
use "std:atomic" atomic
use "std:adaptive_spinlock" adsl
use "std:stable_list" sl
use "std:writer" wr
use "std:list" ls
use "std:buffered" buf

use "../helper/logger" lg
use "node_types" nt
use "filectx" fctx
use "../decl_resolver" dclr

pub ProtoPayloadSize(
    prototype dclr.Decl*
    size u64
    alignment u64
)

pub AggregateLayout(
    declaration dclr.Decl*
    size u64
    alignment u64
)

pub alias ModuleID = str

pub const UNSET str = "unset"

pub global logger lg.Logger
pub global stdout buf.Writer
pub global stdin buf.Reader

pub global cwd str = UNSET
pub global stdLibRoot str = UNSET
pub global mainUniqueName str = UNSET

pub global errTraceSlots u64 = 1024
pub global naked bool

pub global pipelines hm.HashMap[future.Future[error]]
pub global lockPipelines lck.Locker
pub global runningPipelines atomic.U64

pub global files hm.HashMap[fctx.FileCtx*]
pub global lockFiles lck.Locker
pub global importedFiles sl.StableList[fctx.FileCtx]
pub global lockImportedFiles lck.Locker
pub global protoPayloadSizes ls.List[ProtoPayloadSize]
pub global lockProtoPayloadSizes lck.Locker
pub global aggregateLayouts ls.List[AggregateLayout]
pub global lockAggregateLayouts lck.Locker
pub global lockStdout lck.Locker
pub global timingLex ls.List[u64]
pub global timingParse ls.List[u64]
pub global lockTimings lck.Locker

pub global pipelineRunner fn(str) !$future.Future[error]

pub global moduleNames hm.HashMap[ModuleID]
pub global lockModuleNames lck.Locker

global pipelineLockStorage adsl.AdaptiveSpinLock
global filesLockStorage adsl.AdaptiveSpinLock
global importedFilesLockStorage adsl.AdaptiveSpinLock
global protoPayloadSizesLockStorage adsl.AdaptiveSpinLock
global aggregateLayoutsLockStorage adsl.AdaptiveSpinLock
global stdoutLockStorage adsl.AdaptiveSpinLock
global timingsLockStorage adsl.AdaptiveSpinLock
global moduleNamesLockStorage adsl.AdaptiveSpinLock

pub initGlobal() !void:
    pipelines = try hm.new[future.Future[error]](16, none)
    pipelineLockStorage = adsl.new()
    lockPipelines = pipelineLockStorage.protoBorrow()

    runningPipelines = atomic.newU64(0)

    files = try hm.new[fctx.FileCtx*](16, none)
    filesLockStorage = adsl.new()
    lockFiles = filesLockStorage.protoBorrow()
    importedFiles = try sl.new[fctx.FileCtx](ctx.alloc, none)
    importedFilesLockStorage = adsl.new()
    lockImportedFiles = importedFilesLockStorage.protoBorrow()
    protoPayloadSizes = try ls.new[ProtoPayloadSize](ctx.alloc, none)
    protoPayloadSizesLockStorage = adsl.new()
    lockProtoPayloadSizes = protoPayloadSizesLockStorage.protoBorrow()
    aggregateLayouts = try ls.new[AggregateLayout](ctx.alloc, none)
    aggregateLayoutsLockStorage = adsl.new()
    lockAggregateLayouts = aggregateLayoutsLockStorage.protoBorrow()
    stdoutLockStorage = adsl.new()
    lockStdout = stdoutLockStorage.protoBorrow()
    timingLex = try ls.new[u64](ctx.alloc, none)
    timingParse = try ls.new[u64](ctx.alloc, none)
    timingsLockStorage = adsl.new()
    lockTimings = timingsLockStorage.protoBorrow()

    moduleNames = try hm.new[ModuleID](16, none)
    moduleNamesLockStorage = adsl.new()
    lockModuleNames = moduleNamesLockStorage.protoBorrow()
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
    try stdout.flush()
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
