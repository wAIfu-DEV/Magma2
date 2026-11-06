mod filectx

use "token_types" tkt

use "std:list" ls
use "std:hash_map" hm
use "std:slices" slc
use "std:memory" mem

pub FileCtx(
    content str
    path str

    modID str
    modName str
    uniqueName str
    
    imports ls.List[str]
    nativeLibs ls.List[str]
    bundles ls.List[str]
    importAlias hm.HashMap[str]
    lineIdx ls.List[u64]
    tokens ls.List[tkt.Token]

    # TO IMPLEMENT
    glNode bool
    scopeTree bool
    interfaceOnly bool
    interfaceSnapshot bool
)

const UNSET str = "unset"

pub new() !$FileCtx:
    ret FileCtx(
        content=UNSET,
        path=UNSET,

        modID=UNSET,
        modName=UNSET,
        uniqueName=UNSET,

        # TODO: remove allocator taking from List
        imports=try ls.new[str](ctx.alloc, none),
        nativeLibs=try ls.new[str](ctx.alloc, none),
        bundles=try ls.new[str](ctx.alloc, none),

        importAlias=try hm.new[str](8, none),
        lineIdx=try ls.new[u64](ctx.alloc, none),
        tokens=mem.zeroValue[ls.List[tkt.Token]](), # is overwritten by pipeline, no access before

        # TODO: to implement
        glNode=false,
        scopeTree=false,
        interfaceOnly=false,
        interfaceSnapshot=false,
    )
..