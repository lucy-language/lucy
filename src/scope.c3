module lucy::scope;

import std::collections::map, std::io;
import llvm;
import lucy::node, lucy::util, lucy::types;

struct Scope
{
    Scope*                    parent;
    HashMap{ String, Var    } variables;
    HashMap{ String, Const  } constants;
    HashMap{ String, Param  } parameters;
    HashMap{ String, Def    } functions;
    HashMap{ String, Struct } structs;
}

struct Var    { String type; ASTNode* node; LLVMValueRef llvm_value; LLVMTypeRef llvm_type; }
struct Const  { String type; ASTNode* node; LLVMValueRef llvm_value; LLVMTypeRef llvm_type; }
struct Param  { String type; ASTNode* node; LLVMValueRef llvm_value; LLVMTypeRef llvm_type; }
struct Def    { String type; ASTNode* node; LLVMValueRef llvm_value; LLVMTypeRef llvm_type; }
struct Struct { ASTNode* node; LLVMTypeRef llvm_type; }

fn Scope* new()
{
    Scope* scope    = malloc(Scope.sizeof);
    (*scope).parent = null;

    return scope;
}

fn Scope* Scope.new(&self)
{
    Scope* scope    = malloc(Scope.sizeof);
    (*scope).parent = self;

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
    if (self.has_var(name))   return { .type = VAR,   .variable  = self.get_var(name)   };
    if (self.has_const(name)) return { .type = CONST, .constant  = self.get_const(name) };
    if (self.has_param(name)) return { .type = PARAM, .parameter = self.get_param(name) };

    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn Var Scope.get_var(&self, String name)
{
    if (self.variables.has_key(name)) return self.variables.get(name)!!;
    if (self.parent != null)          return self.parent.get_var(name);

    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn Const Scope.get_const(&self, String name)
{
    if (self.constants.has_key(name)) return self.constants.get(name)!!;
    if (self.parent != null)          return self.parent.get_const(name);

    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn Param Scope.get_param(&self, String name)
{
    if (self.parameters.has_key(name)) return self.parameters.get(name)!!;
    if (self.parent != null)           return self.parent.get_param(name);

    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn Def Scope.get_def(&self, String name)
{
    if (self.functions.has_key(name)) return self.functions.get(name)!!;
    if (self.parent != null)          return self.parent.get_def(name);
    
    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn bool Scope.has_var(&self, String name)
{
    if (self.variables.has_key(name)) return true;
    if (self.parent != null)          return self.parent.has_var(name);
    
    return false;
}

fn bool Scope.has_const(&self, String name)
{
    if (self.constants.has_key(name)) return true;
    if (self.parent != null)          return self.parent.has_const(name);
    
    return false;
}

fn bool Scope.has_param(&self, String name)
{
    if (self.parameters.has_key(name)) return true;
    if (self.parent != null)           return self.parent.has_param(name);
    
    return false;
}

fn bool Scope.has_def(&self, String name)
{
    if (self.functions.has_key(name)) return true;
    if (self.parent != null)          return self.parent.has_def(name);
    
    return false;
}

fn Struct Scope.get_struct(&self, String name)
{
    if (self.structs.has_key(name)) return self.structs.get(name)!!;
    if (self.parent != null)        return self.parent.get_struct(name);
    
    util::panic("Unreachable", $$FILE, $$LINE, $$FUNC);
}

fn StructNode[] Scope.get_all_structs(&self)
{
    StructNode[] out;

    foreach (s : self.structs.values(mem))
    {
        util::array_insert(&out, s.node.node.struct_node);
    }
    if (self.parent)
    {
        foreach (s : self.parent.structs.values(mem))
        {
            util::array_insert(&out, s.node.node.struct_node);
        }
    }

    return out;
}
