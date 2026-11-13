mod decl_resolver

use "std:hash_map" hm
use "std:stable_list" ls
use "shared/node_types" nt
use "std:atomic" atomic
use "std:read_write_lock" rwlock

pub alias ModuleId = u64
pub alias ScopeId = u64
pub alias DeclId = u64


Owner(
    module ModuleId
    scope ScopeId
)

pub Module(
    id ModuleId

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
    owner Owner, 
    id DeclId
)

pub union DeclKind(
    Variable(name str, type nt.Type*)
    Argument(name str, type nt.Type*, boundedCount str)
    Function(name str, returnType nt.Type*)
    Struct(name str)
    Alias(name str, target nt.Type*)
    Union(name str)
    Enum(name str, backing nt.Type*)
    Proto(name str)
    Field(name str, type nt.Type*)
    UnionVariant(name str)
    EnumVariant(name str, type nt.Type*)
)

Resolver(
    modules ls.StableList[Module]
    modulesLock rwlock.ReadWriteLock

    pathToMod hm.HashMap[ModuleId]
    pathToModLock rwlock.ReadWriteLock
)

global resolverData Resolver
global isInit atomic.U8 = atomic.U8(value=0)

pub initResolver() !void:
    if isInit.exchange(1) != 0:
        ret
    ..
    # risk of deadlock if errors here, but if it does
    # you likely have bigger issues at hand

    resolverData = Resolver(
        modules=try ls.new[Module](ctx.alloc, none)
        pathToMod=try hm.new[ModuleId](32, none)
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

getModuleLocked(id ModuleId) !Module*:
    if id >= resolverData.modules.count():
        throw "tried to access module outside of bounds"
    ..
    ret try resolverData.modules.get(id) # pointer to stable storage
..

pub registerModule(absPath str) !Module*:
    scopes := try ls.new[Scope](ctx.alloc, none)
    decls := try ls.new[Decl](ctx.alloc, none)
    # Module-wide declarations can be numerous; keep this registry sized for
    # its larger working set. Individual scopes use the small-map default.
    names := try hm.new[DeclId](8, none)

    resolverData.modulesLock.writeLock()
    defer resolverData.modulesLock.writeUnlock()

    id := resolverData.modules.count()
    try resolverData.modules.push(Module(
        id=id,
        decls=move decls,
        scopes=move scopes,
        names=move names,
        declsLock=rwlock.new(),
        scopesLock=rwlock.new(),
        namesLock=rwlock.new(),
    ))
    ret try getModuleLocked(id)
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
    names := try hm.new[DeclId](2, none)

    module.scopesLock.writeLock()
    defer module.scopesLock.writeUnlock()

    id := module.scopes.count() + 1
    parent Scope* = none
    if parentId != 0:
        parent = try getScopeLocked(module, parentId)
    ..
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
    loop scope != none:
        scope.namesLock.readLock()
        id, err := scope.names.indexOf(name)
        if err.ok():
            id = try scope.names.get(name)
            scope.namesLock.readUnlock()
            ret try this.module.getDecl(id)
        ..
        scope.namesLock.readUnlock()
        scope = scope.parentScope
    ..
    ret try this.module.getDeclFromName(name)
..
