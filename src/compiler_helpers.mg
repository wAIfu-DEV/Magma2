mod compiler_helpers

use "std:future" fut
use "shared/global" gl

pub discardErrorFuture(value $fut.Future[error]) void:
    output error, awaitError error = value.await()
    output = output
    awaitError = awaitError
..

pub registerRootPipeline(path str, future fut.Future[error]) !bool:
    try gl.pipelines.setBorrowed(path, future)
    ret true
..

