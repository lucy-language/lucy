module lucy::scope;

const FMT = "Could not find variable `%s` in current scope (%s:%s)";


module lucy::scope::comp;

import std::io, std::os, std::collections::map;
import llvm;
import lucy::node, lucy::util;

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
    ConstNode    node;
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

enum ResultType
{
    VAR,
    CONST,
    PARAM
}

struct ScopeResult
{
    ResultType type;
    Var        variable;
    Const      constant;
    Param      parameter;
}

fn bool Scope.has(&self, String name)
{
    return self.has_var(name) || self.has_const(name) || self.has_param(name);
}

fn ScopeResult Scope.get(&self, String name)
{
    if (self.has_var(name))
    {
        return { .type = VAR, .variable = self.get_var(name) };
    }
    if (self.has_const(name))
    {
        return { .type = CONST, .constant = self.get_const(name) };
    }
    if (self.has_param(name))
    {
        return { .type = PARAM, .parameter = self.get_param(name) };
    }

    util::panic("Unreachable", $$FILE, $$LINE);
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
    
    return {};
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

    return {};
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
