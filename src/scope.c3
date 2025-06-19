module lucy::scope;

import lucy::node;

const FMT = "Could not find variable `%s` in current scope (%s:%s)";


module lucy::scope::comp;

import std::io, std::os, std::collections::map;
import llvm;
import lucy::node;

struct Scope
{
    Scope*                 parent;
    HashMap{String, Var}   variables;
    HashMap{String, Const} constants;
    HashMap{String, Param} parameters;
}

struct Var
{
    String       type;
    LLVMValueRef value;
}

struct Const
{
    String       type;
    LLVMValueRef value;
}

struct Param
{
    String       type;
    LLVMValueRef value;
}

fn Scope* Scope.new(&self)
{
    Scope* scope        = malloc(Scope.sizeof);
    (*scope).parent     = self;
    (*scope).variables  = {};
    (*scope).constants  = {};
    (*scope).parameters = {};
    return scope;
}

fn Var Scope.get_var(&self, String name)
{
    if (self.variables.has_key(name))
    {
        return self.variables.get(name)!!;
    }

    if (self.parent != null)
    {
        return (*self.parent).get_var(name);
    }

    io::eprintfn(scope::FMT, name, $$FILE, $$LINE);
    os::exit(1);
}

fn Const Scope.get_const(&self, String name)
{
    if (self.constants.has_key(name))
    {
        return self.constants.get(name)!!;
    }

    if (self.parent != null)
    {
        return (*self.parent).get_const(name);
    }

    io::eprintfn(scope::FMT, name, $$FILE, $$LINE);
    os::exit(1);
}

fn Param Scope.get_param(&self, String name)
{
    if (self.parameters.has_key(name))
    {
        return self.parameters.get(name)!!;
    }

    if (self.parent != null)
    {
        return (*self.parent).get_param(name);
    }

    io::eprintfn(scope::FMT, name, $$FILE, $$LINE);
    os::exit(1);
}

fn bool Scope.has_var(&self, String name)
{
    if (self.variables.has_key(name))
    {
        return true;
    }

    if (self.parent != null)
    {
        return (*self.parent).has_var(name);
    }
    
    return false;
}

fn bool Scope.has_const(&self, String name)
{
    if (self.constants.has_key(name))
    {
        return true;
    }

    if (self.parent != null)
    {
        return (*self.parent).has_const(name);
    }
    
    return false;
}

fn bool Scope.has_param(&self, String name)
{
    if (self.parameters.has_key(name))
    {
        return true;
    }

    if (self.parent != null)
    {
        return (*self.parent).has_param(name);
    }
    
    return false;
}


module lucy::scope::sema;

import std::io, std::os, std::collections::map;
import llvm;
import lucy::node;

struct SemScope
{
    SemScope*                  parent;
    HashMap{String, SemVar}    variables;
    HashMap{String, SemConst}  constants;
}

struct SemVar
{
    ASTNode node;
    String  type;
}

struct SemConst
{
    ASTNode node;
    String  type;
}

fn SemScope* SemScope.new(&self)
{
    SemScope* scope    = malloc(SemScope.sizeof);
    (*scope).parent    = self;
    (*scope).variables = {};
    (*scope).constants = {};
    return scope;
}

fn SemVar SemScope.get_var(&self, String name)
{
    if (self.variables.has_key(name))
    {
        return self.variables.get(name)!!;
    }

    if (self.parent != null)
    {
        return (*self.parent).get_var(name);
    }

    io::eprintfn(scope::FMT, name, $$FILE, $$LINE);
    os::exit(1);
}

fn SemConst SemScope.get_const(&self, String name)
{
    if (self.constants.has_key(name))
    {
        return self.constants.get(name)!!;
    }

    if (self.parent != null)
    {
        return (*self.parent).get_const(name);
    }

    io::eprintfn(scope::FMT, name, $$FILE, $$LINE);
    os::exit(1);
}

fn bool SemScope.has_var(&self, String name)
{
    if (self.variables.has_key(name))
    {
        return true;
    }

    if (self.parent != null)
    {
        return (*self.parent).has_var(name);
    }
    
    return false;
}

fn bool SemScope.has_const(&self, String name)
{
    if (self.constants.has_key(name))
    {
        return true;
    }

    if (self.parent != null)
    {
        return (*self.parent).has_const(name);
    }
    
    return false;
}
