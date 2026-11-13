mod filectx

use "token_types" tkt

use "std:list" ls
use "std:stable_list" stable
use "std:hash_map" hm
use "std:slices" slc
use "std:memory" mem
use "node_types" nt

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
    publicImportAlias hm.HashMap[bool]
    lineIdx ls.List[u64]
    tokens ls.List[tkt.Token]

    # GET THIS SHIT OUT OF HERE
    astNodes stable.StableList[nt.Node]
    astRoot nt.Root

    # TO IMPLEMENT
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

        importAlias=try hm.new[str](4, none),
        publicImportAlias=try hm.new[bool](4, none),
        lineIdx=try ls.new[u64](ctx.alloc, none),
        tokens=mem.zeroValue[ls.List[tkt.Token]](), # is overwritten by pipeline, no access before
        astNodes=try stable.new[nt.Node](ctx.alloc, none),
        astRoot=nt.Root(statements=nt.emptyNodeArray[nt.GlobalStmt*]()),

        # TODO: to implement
        scopeTree=false,
        interfaceOnly=false,
        interfaceSnapshot=false,
    )
..
