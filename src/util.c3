module lucy::util;

import lucy::node, lucy::scope, lucy::types, lucy::errors, lucy::sema;
import std::core::string, std::core::mem, std::os, std::io, std::collections::map;
import llvm;

const String LOWERCASE = "abcdefghijklmnopqrstuvwxyz";
const String UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

macro bool in(arr, el)
{
    foreach (a : arr)
    {
        if (a == el) return true;
    }
    return false;
}

macro void array_insert(arr, element)
{
    var $Type = $typeof(element);
    $Type[] tmp = mem::new_array($Type, (*arr).len + 1);
    
    // avoid mem::copy for 0 sized array
    for (int i = 0; i < (*arr).len; i++)
    {
        tmp[i] = (*arr)[i];
    }

    tmp[(*arr).len] = element;

    *arr = tmp;
}

macro void panicf(String fmt, args..., String file, int line, String function) @noreturn => panic(string::tformat(fmt, args), file, line, function);

<*
 @require message.len <= 73 : "message cannot be longer than 73 characters"
*>
fn void panic(String message, String file, int line, String function) @noreturn
{
    io::eprint  (Ansi.YELLOW);
    io::eprintn ("╭──────────────────────────────────────────────────────────────────────────────────╮");
    io::eprintn ("│ ⚠️ Oops! Something went wrong                                                    │");
    io::eprintfn("│ Issue: %-*s │", 73, message);
    io::eprintfn("│ In file: %-*s │", 71, string::tformat("%s (%d)", file, line));
    io::eprintfn("│ function: %-*s │", 70, string::tformat("%s", function));
    io::eprintn ("│                                                                                  │");
    io::eprintn ("│ Please create an issue on github at https://github.com/lucy-language/lucy/issues │");
    io::eprintn ("│ and include your compiler version you can get by running `lucy --version`        │");
    io::eprintn ("╰──────────────────────────────────────────────────────────────────────────────────╯");
    io::eprint (Ansi.RESET);
    os::exit(1);
}

fn String join_to_string(String[] arr, String separator)
{
    DString result;
    result.init(mem);
    defer result.free();

    bool first = true;
    foreach (x : arr)
    {
        if (!first) result.append_chars(separator);
        if (first) first = false;

        result.append_chars(x);
    }

    return result.copy_str(mem);
}

fn String[] all_ends(String[] arr, String el)
{
    String[] ends;
    foreach (a : arr)
    {
        if (a.ends_with(el))
        {
            array_insert(&ends, a);
        }
    }

    return ends;
}

fn ASTNode make_null() => { NULL, { .null_node = { "null" } }, {}, 0, {} };

fn bool String.is_upper(self)
{
    foreach (c : self[:self.len])
    {
        if (!c.is_upper()) return false;
    }

    return true;
}

fn bool is_builtin_type(ASTNode* type) => in((String[]){ "str", "int", "char", "bool", "float", "double" }, type.node.ident_node.name);

fn ASTNode* ScopeResult.get_node(&self)
{
    switch (self.type)
    {
        case VAR:   return self.variable.node;
        case CONST: return self.constant.node;
        case PARAM: return self.parameter.node;
    }
}

fn String ScopeResult.get_type(&self)
{
    switch (self.type)
    {
        case VAR:   return self.variable.type;
        case CONST: return self.constant.type;
        case PARAM: return self.parameter.type;
    }
}

fn LLVMValueRef ScopeResult.get_llvm_value(&self)
{
    switch (self.type)
    {
        case VAR:   return self.variable.llvm_value;
        case CONST: return self.constant.llvm_value;
        case PARAM: return self.parameter.llvm_value;
    }
}

fn LLVMTypeRef ScopeResult.get_llvm_type(&self)
{
    switch (self.type)
    {
        case VAR:   return self.variable.llvm_type;
        case CONST: return self.constant.llvm_type;
        case PARAM: return self.parameter.llvm_type;
    }
}

fn String stringify_path(ASTNode* node)
{
    String[] segments;
    foreach (segment : node.node.path_node.segments)
    {
        array_insert(&segments, segment.node.ident_node.name);
    }
    return join_to_string(segments, ".");
}

fn String stringify_module(ASTNode* node)
{
    String[] segments;
    foreach (segment : node.node.path_node.segments)
    {
        array_insert(&segments, segment.node.ident_node.name);
    }
    return join_to_string(segments, "_");
}

fn String[] get_possible_pkgs(String[] in, String filter)
{
    String[] out;
    foreach (s : in)
    {
        if (s.ends_with(filter)) array_insert(&out, s);
    }

    return out;
}

fn bool is_null(ASTNode* node) => node.node_type == NULL;

fn ASTNode* get_field_by_name(String name, StructNode str)
{
    foreach (field : str.fields)
    {
        if (field.node.field_node.name.node.ident_node.name == name) return field;
    }
    
    return null;
}

fn bool is_variatric(ASTNode*[] parameters)
{
    foreach (parameter : parameters)
    {
        if (parameter.node.parameter_node.is_vararg) return true;
    }

    return false;
}
