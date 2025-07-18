module lucy::util;

import lucy::node, lucy::scope, lucy::types, lucy::errors;
import std::core::string, std::core::mem, std::os, std::io, std::collections::map;
import llvm;

const String LOWERCASE   = "abcdefghijklmnopqrstuvwxyz";
const String UPPERCASE   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

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

fn String get_type_node(ASTNode* node, Scope* scope, String path)
{
    switch (node.node_type)
    {
        case INT:       return "int";
        case DEF:       return get_type_node_def(node);
        case STR:       return "str";
        case BIN:       return get_type_node_bin(node, scope, path);
        case CALL:      return get_type_node_call(node, scope);
        case BOOL:      return "bool";
        case CHAR:      return "char";
        case INIT:      return get_type_node_init(node, scope, path);
        case TUPLE:     return get_type_node_tuple(node);
        case FLOAT:     return "float";
        case UNARY:     return get_type_node(node.node.unary_node.expr, scope, path);
        case IDENT:     return get_type_node_ident(node, scope);
        case DOUBLE:    return "double";
        case RETURN:    return get_type_node_return(node, scope, path);
        case PARAMETER: return get_type_node_parameter(node, scope);
        
        default: panicf("Missing case for type `%s`", node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
    }
}

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

fn String get_type_node_tuple(ASTNode* node)
{
    String[] types;
    foreach (type : node.node.tuple_node.values)
    {
        array_insert(&types, type.node.ident_node.name);
    }

    DString out;

    out.append_char('(');
    out.append_chars(join_to_string(types, ", "));
    out.append_char(')');

    return out.copy_str(mem);
}

fn String get_type_node_call(ASTNode* node, Scope* scope)
{
    CallNode call_node = node.node.call_node;
    String   name      = call_node.name.node.ident_node.name;
    return scope.get_def(name).type;
}

fn String get_type_node_def(ASTNode* node)
{
    DefNode def_node = node.node.def_node;
    if (def_node.type.node_type == IDENT)
    {
        return def_node.type.node.ident_node.name;
    } else
    {
        return get_type_node_tuple(def_node.type);
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

fn String[] get_possible_pkgs(String[] in, String filter)
{
    String[] out;
    foreach (s : in)
    {
        if (s.ends_with(filter)) array_insert(&out, s);
    }

    return out;
}

fn String get_type_node_parameter(ASTNode* node, Scope* scope)
{
    ParameterNode parameter_node = node.node.parameter_node;

    if (parameter_node.type.node_type == NULL) return "void";

    return parameter_node.type.node.ident_node.name;
}

fn String get_type_node_ident(ASTNode* node, Scope* scope)
{
    String name = node.node.ident_node.name;
    return scope.get(name).get_type();
}

fn String get_type_node_bin(ASTNode* node, Scope* scope, String path)
{
    BinNode bin_node = node.node.bin_node;
    String  operator = bin_node.operator;

    switch (operator)
    {
        case "!=":
        case "==":
        case ">=":
        case "<=":
        case ">=":
        case ">":
        case "<":
            return "bool";
        case "+":
        case "-":
        case "*":
        case "/":
            return get_type_node(bin_node.left, scope, path);
    }
    
    panicf("Missing case for operator `%s`", operator, file: $$FILE, line: $$LINE, function: $$FUNC);
}

fn String get_type_node_return(ASTNode* node, Scope* scope, String path)
{
    ReturnNode return_node = node.node.return_node;
    ASTNode*[] values      = return_node.values;

    if (values.len == 0) return "void";

    if (values.len > 1)
    {
        String[] types;
        foreach (value : values)
        {
            array_insert(&types, get_type_node(value, scope, path));
        }

        DString out;

        out.append_char('(');
        out.append_chars(join_to_string(types, ", "));
        out.append_char(')');

        return out.copy_str(mem);
    } else
    {
        return get_type_node(values[0], scope, path);
    }
}

fn String get_type_node_init(ASTNode* node, Scope* scope, String path)
{
    InitNode init_node      = node.node.init_node;
    String[] possible_types = get_possible_types(init_node, scope, path);

    if (possible_types.len > 1)
    {
        errors::print_node(path, *node, string::format(mem, "Multiple matching types found: `%s`", join_to_string(possible_types, ", ")));
        os::exit(1);
    }

    if (possible_types.len == 0)
    {
        errors::print_node(path, *node, "Could not find type with those properties.");
        os::exit(1);
    }

    return possible_types[0];
}

fn String[] get_possible_types(InitNode init_node, Scope* scope, String path)
{
    String[] possible_types;

    bool named;
    foreach (i, value : init_node.values)
    {
        InitValueNode value_node = value.node.init_value_node;
        if (i == 0) named = !is_null(value_node.name);
        
        if (named && is_null(value_node.name) || !named && !is_null(value_node.name))
        {
            errors::print_node(path, *value, "Cannot mix named and unnamed initialization.");
            os::exit(1);
        }
    }

    if (named)
    {
        foreach (type : scope.get_all_structs())
        {
            bool all_names_match = true;

            HashMap{ String, ASTNode* } previous_names;
            foreach (value : init_node.values)
            {
                InitValueNode init_value = value.node.init_value_node;
                String        name       = init_value.name.node.ident_node.name;

                if (previous_names.has_key(name))
                {
                    errors::print_node(path, *previous_names.get(name)!!, errors::ERROR_PREVIOUS);
                    errors::print_node(path, *value, "A field with this name has already been initialized.");
                    os::exit(1);
                }

                previous_names.set(name, value);

                bool name_found;
                foreach FIELDS: (field : type.fields)
                {
                    String field_name = field.node.field_node.name.node.ident_node.name;

                    if (name == field_name)
                    {
                        name_found = true;
                        break FIELDS;
                    }
                }

                if (!name_found)
                {
                    all_names_match = false;
                }
            }

            if (all_names_match)
            {
                foreach (value : init_node.values)
                {
                    String type_name  = get_type_node(value.node.init_value_node.value, scope, path);
                    String field_type = get_field_by_name(value.node.init_value_node.name.node.ident_node.name, type).node.field_node.type.node.ident_node.name;

                    if (type_name != field_type)
                    {
                        errors::print_node(path, *value, string::format(mem, "Expected type `%s`, got `%s`", field_type, type_name));
                        os::exit(1);
                    }
                }

                array_insert(&possible_types, type.name.node.ident_node.name);
            }
        }
    } else
    {
        foreach (type : scope.get_all_structs())
        {
            if (type.fields.len != init_node.values.len) continue;
            
            bool types_match = true;
            foreach FIELDS: (i, field : type.fields)
            {
                String field_type = field.node.field_node.type.node.ident_node.name;
                String value_type = get_type_node(init_node.values[i].node.init_value_node.value, scope, path);

                if (field_type != value_type)
                {
                    types_match = false;
                    break FIELDS;
                }
            }

            if (types_match)
            {
                array_insert(&possible_types, type.name.node.ident_node.name);
            }
        }
    }

    return possible_types;
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


module libc;

extern fn isz readlink(ZString pathname, char* buf, int bufsize);
