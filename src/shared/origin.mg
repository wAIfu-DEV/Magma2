mod origin

# Used for token or node position in source
# @author devan

pub FilePos(
    line u32
    column u32
)

pub Origin(
    filePath str
    position FilePos
)