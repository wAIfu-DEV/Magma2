mod decl_resolver

use "std:hash_map" hm
use "std:stable_list" ls
use "std:allocator" alc
use "shared/node_types" nt
use "shared/origin" org
use "std:atomic" atomic
use "std:read_write_lock" rwlock
use "std:strings" strgs


pub alias ModuleId = u64
pub alias ScopeId = u64
pub alias DeclId = u64

pub DeclArray(
    data Decl**
    length u64
    capacity u64
)

pub ProtoImplementation(
    prototype Decl*
    methods DeclArray
)

pub ProtoImplementationArray(
    data ProtoImplementation*
    length u64
    capacity u64
)

pub ProtoImplementationArray.count() u64:
    ret this.length
..

pub ProtoImplementationArray.get(index u64) !ProtoImplementation:
    if index >= this.length:
        throw "prototype implementation index is out of bounds"
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub ProtoImplementationArray.pushRight(a alc.Allocator, value ProtoImplementation) !void:
    if this.length == this.capacity:
        newCapacity u64 = 2
        if this.capacity != 0:
            newCapacity = this.capacity * 2
        ..
        if this.data == none:
            this.data = try a.allocT[ProtoImplementation](newCapacity)
        else:
            this.data = try a.reallocT[ProtoImplementation](this.data, newCapacity)
        ..
        this.capacity = newCapacity
    ..
    unsafe:
        this.data[this.length] = value
    ..
    this.length = this.length + 1
..

pub emptyDeclArray() DeclArray:
    ret DeclArray(data=none, length=0, capacity=0)
..

pub DeclArray.count() u64:
    ret this.length
..

pub DeclArray.get(index u64) !Decl*:
    if index >= this.length:
        throw "declaration array index is out of bounds"
    ..
    unsafe:
        ret this.data[index]
    ..
..

pub DeclArray.pushRight(a alc.Allocator, value Decl*) !void:
    newLength := this.length + 1
    if this.length == this.capacity:
        newCapacity u64 = 4
        if this.capacity != 0:
            newCapacity = this.capacity * 2
        ..
        if this.data == none:
            this.data = try a.allocT[Decl*](newCapacity)
        else:
            this.data = try a.reallocT[Decl*](this.data, newCapacity)
        ..
        this.capacity = newCapacity
    ..
    unsafe:
        this.data[this.length] = value
    ..
    this.length = newLength
..


Owner(
    module ModuleId
    scope ScopeId
)

pub Module(
    id ModuleId
    path str

    scopes ls.StableList[Scope]
    scopesLock rwlock.ReadWriteLock

    decls ls.StableList[Decl]
    declsLock rwlock.ReadWriteLock

    names hm.HashMap[DeclId]
    namesLock rwlock.ReadWriteLock
)

pub Scope(
    owner Owner
    module Module*
    parentScope Scope*
    kind ScopeKind
    id ScopeId

    names hm.HashMap[DeclId]
    namesLock rwlock.ReadWriteLock
)

pub union ScopeKind(
    Function()
    Method()
    Block()
)

pub Decl(
    kind DeclKind
    module Module*
    # Canonical source type for declarations that denote values or types.
    # Parser-created declarations share this node when their name is used.
    declType nt.Type*
    isPublic bool
    isImplicitContext bool
    semanticState u8
    sourcePos org.FilePos
    sourceHeader nt.Header*
    sourceBody nt.Stmt*
    externalName str
    methodOwnerType nt.Type*
    receiverDecl Decl*
    isModuleVariable bool
    methodNoContext bool
    protoMethodIndex u64
    fieldIndex u64
    implicitContextDecl Decl*
    implicitContextNeedsSlot bool
    protoImplementations ProtoImplementationArray
    unionOwner Decl*
    unionTag u64
    enumIndex u64
    enumInitializer nt.Expr*
    owner Owner,
    id DeclId
)

pub union DeclKind(
    Module(name str, moduleRef Module*)
    Variable(name str, type nt.Type*, initializer nt.Expr*, isGlobal bool, isConst bool)
    Argument(name str, type nt.Type*, boundedCount str)
    Function(name str, returnType nt.Type*, args DeclArray, typeParams DeclArray)
    Field(name str, type nt.Type*)
    Struct(name str, fields DeclArray, typeParams DeclArray, implements nt.NodeArray[nt.Type*])
    Alias(name str, target nt.Type*)
    Union(name str, scope Scope*, variants DeclArray, implements nt.NodeArray[nt.Type*])
    Enum(name str, backing nt.Type*, scope Scope*, variants DeclArray)
    Proto(name str, scope Scope*, methods DeclArray)
    UnionVariant(name str, fields DeclArray, unionType nt.Type*)
    EnumVariant(name str, type nt.Type*)
    TypeParameter(name str, index u64)
)

getTypeDecl(t nt.Type*) !Decl*:
    match t as tx:
    case nt.Type.Named:
        ret tx.decl
    else:
        throw "cannot get declaration from type"
    ..
..

typeAccess(t nt.Type*, fieldName str) !Decl*:
    match t as tx:
    case nt.Type.Named:
        ret try tx.decl.access(fieldName)
    case nt.Type.Templated:
        ret try typeAccess(tx.owner, fieldName)
    case nt.Type.Owned:
        ret try typeAccess(tx.ofType, fieldName)
    case nt.Type.Pointer:
        ret try typeAccess(tx.toType, fieldName)
    case nt.Type.Throwing:
        ret try typeAccess(tx.ofType, fieldName)
    case nt.Type.Slice:
        if implicitCoreModule == none:
            throw "core module is missing while resolving slice members"
        ..
        qualified := try strgs.concat("slice.", fieldName)
        defer qualified.free()
        method, methodErr := implicitCoreModule.getDeclFromName(qualified)
        if methodErr.ok():
            ret method
        ..
        sliceDecl := try implicitCoreModule.getDeclFromName("slice")
        ret try sliceDecl.access(fieldName)
    else:
        throw "type cannot be accessed"
    ..
..

Decl.access(name str) !Decl*:
    k := addrof this.kind
    match k as kx:
    case DeclKind.Struct:
        # I guess this is the baseline
        for i := 0 to kx.fields.count():
            field := try kx.fields.get(i)
            match addrof field.kind as kx2:
            case DeclKind.Field:
                if kx2.name == name:
                    ret field
                ..
            else:
                throw "somehow field is not a field"
            ..
        ..
    case DeclKind.Module:
        ret try kx.moduleRef.getDeclFromName(name)
    case DeclKind.Union:
        ret try kx.scope.getDeclFromName(name)
    case DeclKind.Enum:
        ret try kx.scope.getDeclFromName(name)
    case DeclKind.Proto:
        ret try kx.scope.getDeclFromName(name)
    case DeclKind.UnionVariant:
        for i := 0 to kx.fields.count():
            field := try kx.fields.get(i)
            match addrof field.kind as fieldKind:
            case DeclKind.Field:
                if fieldKind.name == name:
                    ret field
                ..
            else:
                throw "union variant contains a non-field declaration"
            ..
        ..
    case DeclKind.Variable:
        ret try typeAccess(kx.type, name)
    case DeclKind.Argument:
        ret try typeAccess(kx.type, name)
    case DeclKind.Alias:
        ret try typeAccess(kx.target, name)
    case DeclKind.Field:
        ret try typeAccess(kx.type, name)
    case DeclKind.EnumVariant:
        ret try typeAccess(kx.type, name)
    #case DeclKind.Union: # TODO: implement (should be used to access UnionVariants)
    #case DeclKind.Enum: # TODO: implement (should be used to access the enum constants)
    #case DeclKind.UnionVariant: # TODO: implement (should be used to access fields)
    else:
        # TODO: comp error
        throw "declaration cannot be accessed"
    ..
    ret none
..

Resolver(
    modules ls.StableList[Module]
    modulesLock rwlock.ReadWriteLock

    pathToMod hm.HashMap[Module*]
    pathToModLock rwlock.ReadWriteLock
)

global resolverData Resolver
global isInit atomic.U8 = atomic.U8(value=0)
global implicitCoreModule Module* = none

pub setImplicitCoreModule(module Module*) void:
    implicitCoreModule = module
..

pub isImplicitCoreModule(module Module*) bool:
    ret module == implicitCoreModule
..

pub initResolver() !void:
    if isInit.exchange(1) != 0:
        ret
    ..

    resolverData = Resolver(
        modules=try ls.new[Module](ctx.alloc, none)
        pathToMod=try hm.new[Module*](32, none)
        modulesLock=rwlock.new()
        pathToModLock=rwlock.new()
    )
..

pub getModule(id ModuleId) !Module*:
    # The lock protects the StableList page directory during lookup. Module
    # records never move and are immutable after publication, so the pointer
    # remains valid for the resolver's lifetime after the read lock is released.
    resolverData.modulesLock.readLock()
    defer resolverData.modulesLock.readUnlock()

    ret try getModuleLocked(id)
..

pub getModuleFromPath(absPath str) !Module*:
    resolverData.pathToModLock.readLock()
    defer resolverData.pathToModLock.readUnlock()

    ret try resolverData.pathToMod.get(absPath)
..

getModuleLocked(id ModuleId) !Module*:
    if id >= resolverData.modules.count():
        throw "tried to access module outside of bounds"
    ..
    ret try resolverData.modules.get(id) # pointer to stable storage
..

createModule(absPath str) !Module*:
    moduleStruct := Module(
        id=0,
        path=absPath,
        decls=try ls.new[Decl](ctx.alloc, none),
        scopes=try ls.new[Scope](ctx.alloc, none),
        names=try hm.new[DeclId](8, none),
        declsLock=rwlock.new(),
        scopesLock=rwlock.new(),
        namesLock=rwlock.new(),
    )

    moduleRef Module* = none

    if true:
        resolverData.modulesLock.writeLock()
        defer resolverData.modulesLock.writeUnlock()

        id := resolverData.modules.count()
        try resolverData.modules.push(moduleStruct)
        moduleRef = try getModuleLocked(id)
        moduleRef.id = id
    ..

    ret moduleRef
..

pub registerModule(absPath str) !Module*:
    moduleRef := try createModule(absPath)
    resolverData.pathToModLock.writeLock()
    defer resolverData.pathToModLock.writeUnlock()
    try resolverData.pathToMod.setBorrowed(absPath, moduleRef)
    ret moduleRef
..

pub registerTransientModule(absPath str) !Module*:
    ret try createModule(absPath)
..

getScopeLocked(module Module*, id ScopeId) !Scope*:
    if id == 0:
        throw "tried to access scope but its ID is empty"
    ..
    if id > module.scopes.count():
        throw "tried to access scope outside of bounds"
    ..
    ret try module.scopes.get(id - 1)
..

Module.getScope(id ScopeId) !Scope*:
    # Scopes are immutable after insertion and live at stable addresses.
    this.scopesLock.readLock()
    defer this.scopesLock.readUnlock()

    ret try getScopeLocked(this, id)
..

registerScope(module Module*, parentId ScopeId, kind ScopeKind) !Scope*:
    module.scopesLock.writeLock()
    defer module.scopesLock.writeUnlock()

    id := module.scopes.count() + 1
    parent Scope* = none
    if parentId != 0:
        parent = try getScopeLocked(module, parentId)
    ..
    names := try hm.new[DeclId](2, none)
    try module.scopes.push(Scope(
        id=id,
        module=module,
        parentScope=parent,
        owner=Owner(module=module.id, scope=parentId),
        kind=kind,
        names=move names,
        namesLock=rwlock.new(),
    ))
    ret try getScopeLocked(module, id)
..

Module.registerScope(kind ScopeKind) !Scope*:
    ret try registerScope(this, 0, kind)
..

getDeclLocked(module Module*, id DeclId) !Decl*:
    if id == 0:
        throw "tried to access decl but its ID is empty"
    ..
    if id > module.decls.count():
        throw "tried to access decl outside of bounds"
    ..
    ret try module.decls.get(id - 1)
..

Module.getDecl(id DeclId) !Decl*:
    # Declarations are fully initialized before publication and never mutated.
    this.declsLock.readLock()
    defer this.declsLock.readUnlock()

    ret try getDeclLocked(this, id)
..

registerDeclLocked(module Module*, name str, scope ScopeId, kind DeclKind) !Decl*:
    id := module.decls.count() + 1
    try module.decls.push(Decl(
        id=id,
        module=module,
        declType=none,
        isPublic=false,
        isImplicitContext=false,
        semanticState=0,
        sourcePos=org.FilePos(line=0, column=0),
        sourceHeader=none,
        sourceBody=none,
        externalName="",
        methodOwnerType=none,
        receiverDecl=none,
        isModuleVariable=false,
        methodNoContext=false,
        protoMethodIndex=0,
        fieldIndex=0,
        implicitContextDecl=none,
        implicitContextNeedsSlot=false,
        protoImplementations=ProtoImplementationArray(data=none, length=0, capacity=0),
        unionOwner=none,
        unionTag=0,
        enumIndex=0,
        enumInitializer=none,
        owner=Owner(module=module.id, scope=scope),
        kind=kind,
    ))

    if scope == 0:
        module.namesLock.writeLock()
        defer module.namesLock.writeUnlock()
        try module.names.set(name, id)
    else:
        module.scopesLock.readLock()
        scopeNode := try getScopeLocked(module, scope)
        module.scopesLock.readUnlock()
        scopeNode.namesLock.writeLock()
        defer scopeNode.namesLock.writeUnlock()
        try scopeNode.names.set(name, id)
    ..

    ret try module.decls.get(id - 1)
..

Module.registerDecl(name str, kind DeclKind) !Decl*:
    this.declsLock.writeLock()
    defer this.declsLock.writeUnlock()

    ret try registerDeclLocked(this, name, 0, kind)
..

Module.registerScopeDecl(name str, scope ScopeId, kind DeclKind) !Decl*:
    this.scopesLock.readLock()
    validScope := scope != 0 && scope <= this.scopes.count()
    this.scopesLock.readUnlock()
    if not validScope:
        throw "tried to register a declaration in an unknown scope"
    ..

    this.declsLock.writeLock()
    defer this.declsLock.writeUnlock()
    ret try registerDeclLocked(this, name, scope, kind)
..

Module.getDeclFromName(name str) !Decl*:
    id DeclId

    if true:
        this.namesLock.readLock()
        defer this.namesLock.readUnlock()
        id = try this.names.get(name)
    ..
    ret try this.getDecl(id)
..

Scope.getDecl(id DeclId) !Decl*:
    ret try this.module.getDecl(id)
..

Scope.registerDecl(name str, kind DeclKind) !Decl*:
    ret try this.module.registerScopeDecl(name, this.id, kind)
..

Scope.registerScope(kind ScopeKind) !Scope*:
    ret try registerScope(this.module, this.id, kind)
..

Scope.getDeclFromName(name str) !Decl*:
    scope := this
    id DeclId
    loop scope != none:
        scope.namesLock.readLock()
        if scope.names.contains(name):
            id = try scope.names.get(name)
            scope.namesLock.readUnlock()
            ret try this.module.getDecl(id)
        ..
        scope.namesLock.readUnlock()
        scope = scope.parentScope
    ..
    ret try this.module.getDeclFromName(name)
..
