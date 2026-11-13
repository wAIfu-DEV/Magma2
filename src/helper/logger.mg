mod logger

use "std:writer" as wr
use "std:io" as io

pub enum LogLevel u8(
    VERBOSE=0
    DEBUG
    DEFAULT
    WARNING
    ERROR
    CRITICAL
)

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
    this.logLvl(text, LogLevel.DEFAULT)
..

Logger.logLn(text str) void:
    this.logLnLvl(text, LogLevel.DEFAULT)
..

Logger.debug(text str) void:
    this.logLvl(text, LogLevel.DEBUG)
..

Logger.debugLn(text str) void:
    this.logLnLvl(text, LogLevel.DEBUG)
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
