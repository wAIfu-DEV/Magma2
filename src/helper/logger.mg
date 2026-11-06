mod logger

use "std:writer" as wr
use "std:io" as io

pub alias LogLevel = u8

pub const LVL_DEBUG LogLevel = 0
pub const LVL_DEFAULT LogLevel = 1
pub const LVL_WARNING LogLevel = 2
pub const LVL_ERROR LogLevel = 3
pub const LVL_CRITICAL LogLevel = 4

pub Logger(
    level LogLevel
    writer wr.Writer
)

pub new(writer wr.Writer, lvl LogLevel) Logger:
    ret Logger(
        level=lvl,
        writer=writer
    )
..

Logger.log(text str) void:
    this.logLvl(text, LVL_DEFAULT)
..

Logger.logLn(text str) void:
    this.logLnLvl(text, LVL_DEFAULT)
..

Logger.debug(text str) void:
    this.logLvl(text, LVL_DEBUG)
..

Logger.debugLn(text str) void:
    this.logLnLvl(text, LVL_DEBUG)
..

Logger.logLvl(text str, level LogLevel) void:
    if level < this.level:
        ret
    ..
    this.writer.write(text)
..

Logger.logLnLvl(text str, level LogLevel) void:
    if level < this.level:
        ret
    ..
    this.writer.writeLn(text)
..