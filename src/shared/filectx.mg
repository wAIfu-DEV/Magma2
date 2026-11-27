mod filectx

use "token_types" tkt

use "std:list" ls
use "std:allocator" alc
use "std:stable_list" stable
use "std:hash_map" hm
use "std:slices" slc
use "std:memory" mem
use "node_types" nt
use "../decl_resolver" dclr

pub FileArray(
    data FileCtx**
    length u64
    capacity u64
)

pub emptyFileArray() FileArray:
    ret FileArray(data=none, length=0, capacity=0)
..
pub FileArray.count() u64:
    ret this.length
..

pub FileArray.get(index u64) !FileCtx*:
    if index >= this.length:
        throw "file array index is out of bounds"
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub FileArray.pushRight(a alc.Allocator, value FileCtx*) !void:
    newLength := this.length + 1
    if this.length == this.capacity:
        newCapacity u64 = 4
        if this.capacity != 0:
            newCapacity = this.capacity * 2
        ..
        if this.data == none:
            this.data = try a.allocT[FileCtx*](newCapacity)
        else:
            this.data = try a.reallocT[FileCtx*](this.data, newCapacity)
        ..
        this.capacity = newCapacity
    ..
    unsafe:
        this.data[this.length] = value
    ..
    this.length = newLength
..

pub FileCtx(
    content str
    path str

    lexingUs u64
    parsingUs u64
    checkingUs u64

    module dclr.Module*

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

    astNodes stable.StableList[nt.Node]
    astRoot nt.Root
    specializations nt.SpecializationPointerArray
)

const UNSET str = "unset"

pub new() !$FileCtx:
    ret FileCtx(
        content=UNSET,
        path=UNSET,

        lexingUs=0,
        parsingUs=0,
        checkingUs=0,

        module=none,

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
        specializations=nt.emptySpecializationArray(),
    )
..
