mod main
use "std:errors" as errors
use "std:dialog" as dialog

pub main() !void:
    configuration := dialog.defaultOptions()
    if configuration.filters.count() != 0 || configuration.defaultPath.countBytes() != 0 || configuration.defaultName.countBytes() != 0 || configuration.title.countBytes() != 0 || configuration.parent != none:
        throw errors.failure("default file dialog options changed")
    ..
    imageFilter := dialog.Filter(name="Images", extensions="png,jpg,jpeg")
    filters := [1]dialog.Filter
    filters[0] = imageFilter
    configured := dialog.Options(
        filters=filters,
        defaultPath="assets",
        defaultName="image.png",
        title="Choose an image",
        parent=none,
    )
    if configured.filters.count() != 1:
        throw errors.failure("file dialog filters changed")
    ..
..
