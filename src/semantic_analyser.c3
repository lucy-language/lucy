module lucy::semantic_analyser;

import std;
import lucy::node, lucy::errors, lucy::scope::sema;

struct Def
{
    ASTNode  node;
    String[] types;
    String   name;
}

struct Parameter
{
    String type;
    String name;
}

struct SemanticAnalyser
{
    String      file_path;
    ASTNode     ast;
    List{Def}   functions;
    SemScope*   scope;
}

fn SemanticAnalyser new(String file_path, ASTNode ast)
{
    SemScope* scope    = malloc(SemScope.sizeof);
    (*scope).parent    = null;
    (*scope).variables = {};
    (*scope).constants = {};
    return {
        .file_path = file_path,
        .ast       = ast,
        .scope     = scope
    };
}

// TODO: scopes
fn void SemanticAnalyser.analyse(&self)
{
    foreach (node : self.ast.node.file_node.children)
    {
        switch (node.node_type)
        {
            case CONST: self.add_const(node);
            case DEF: self.add_def(node);
            case EXT: self.add_ext(node);
            case GLOBAL:
                switch (node.node.global_node.node[0].node_type)
                {
                    case CONST: self.add_const(node.node.global_node.node[0]);
                    case DEF: self.add_def(node.node.global_node.node[0]);
                    case EXT: self.add_ext(node.node.global_node.node[0]);
                    default: break;
                }
            default: break;
        }
    }

    foreach (node : self.ast.node.file_node.children)
    {
        self.analyse_node(node);
    }
}

fn void SemanticAnalyser.add_const(&self, ASTNode node_in)
{
    ConstNode node = node_in.node.const_node;
    String type = node.type;
    String name = node.name;

    if (self.scope.has_const(name))
    {
        SemConst constant = (*self.scope).get_const(name);
        errors::print_node(self.file_path, constant.node, "Previous definition was here");
        errors::print_node(self.file_path, node_in, string::tformat("A constant with the name `%s` is already defined", name));
        os::exit(1);
    } else
    {
        (*self.scope).constants.set(name, { node_in, type });
    }
}

fn void SemanticAnalyser.add_def(&self, ASTNode node_in)
{
    DefNode node = node_in.node.def_node;
    String[] types = node.types;
    String name = node.name;

    Def def;
    bool found;
    foreach (function : self.functions)
    {
        if (function.name == name)
        {
            found = true;
            def = function;
        }
    }

    if (found)
    {
        errors::print_node(self.file_path, def.node, "Previous definition was here");
        errors::print_node(self.file_path, node_in, string::tformat("A function with the name `%s` is already defined", name));
        os::exit(1);
    } else
    {
        self.functions.push({ node_in, types, name });
    }
}

fn void SemanticAnalyser.add_ext(&self, ASTNode node_in)
{
    ExtNode node = node_in.node.ext_node;
    String type = node.type;
    String name = node.name;
    String alias_name = node.alias_name;

    Def def;
    bool found;
    foreach (function : self.functions)
    {
        if (alias_name != "" && function.name == alias_name)
        {
            found = true;
            def = function;
        } else if (function.name == name)
        {
            found = true;
            def = function;
        }
    }

    if (found)
    {
        if (alias_name != "")
        {
            if (def.name == alias_name)
            {
                errors::print_node(self.file_path, def.node, "Previous definition was here");
                errors::print_node(self.file_path, node_in, string::tformat("A function with the name `%s` is already defined", alias_name));
                os::exit(1);
            }
        } else if (def.name == name)
        {
            errors::print_node(self.file_path, def.node, "Previous definition was here");
            errors::print_node(self.file_path, node_in, string::tformat("A function with the name `%s` is already defined", name));
            os::exit(1);
        }
    } else
    {
        self.functions.push({ node_in, (String[]){ type }, alias_name != "" ? alias_name : name });
    }
}

fn void SemanticAnalyser.analyse_node(&self, ASTNode node)
{
    switch (node.node_type)
    {
        case CONST    : self.analyse_const(node);
        case REASSIGN : self.analyse_reassign(node);
        case DEF      : self.analyse_def(node);
        case VAR      : self.analyse_var(node);
        case EXT      : self.analyse_ext(node);
        case BIN      : self.analyse_bin(node);
        case IDENT    : self.analyse_ident(node);
        case GLOBAL   : self.analyse_global(node);
        case CALL     : self.analyse_call(node);
        case IF       : self.analyse_if(node);
        case PARAMETER: self.analyse_parameter(node);
        default       : break;
    }
}

fn void SemanticAnalyser.analyse_const(&self, ASTNode node_in)
{
    ConstNode node = node_in.node.const_node;
    String type = node.type;
    String name = node.name;
    ASTNode value = node.value[0];

    for (int i = 0; i < name.len; i++)
    {
        if (name[i].is_lower())
        {
            errors::print_node(self.file_path, node_in, "Constant names must be all uppercase");
            os::exit(1);
        }
    }

    if (type != self.get_type(value))
    {
        errors::print_node(self.file_path, node.value[0], string::tformat("Expected type `%s`, got `%s`", type, self.get_type(value)));
        os::exit(1);
    }
}

fn void SemanticAnalyser.analyse_reassign(&self, ASTNode node_in)
{
    ReassignNode node = node_in.node.reassign_node;
    String name = node.name;
    ASTNode value = node.value[0];

    self.analyse_node(value);
    
    if ((*self.scope).has_const(name))
    {
        errors::print_node(self.file_path, node_in, "Cannot reassign a constant");
        os::exit(1);
    }

    if ((*self.scope).has_var(name))
    {
        SemVar variable = (*self.scope).get_var(name);
        if (variable.type != self.get_type(value))
        {
            errors::print_node(self.file_path, node_in, string::tformat("Expected type `%s`, got `%s`", variable.type, self.get_type(value)));
            os::exit(1);
        }
        return;
    }

    errors::print_node(self.file_path, node_in, string::tformat("Unable to find variable `%s`", name));
    os::exit(1);
}

fn void SemanticAnalyser.analyse_def(&self, ASTNode node_in)
{
    DefNode node = node_in.node.def_node;
    String[] types = node.types;
    String name = node.name;
    
    self.scope = (*self.scope).new();
    foreach (parameter : node.parameters)
    {
        self.analyse_node(parameter);
    }

    foreach (child : node.children)
    {
        self.analyse_node(child);
    }
    self.scope = (*self.scope).parent;
}

fn String SemanticAnalyser.get_type(&self, ASTNode node)
{
    switch (node.node_type)
    {
        case BOOL:   return "bool";
        case INT:    return "int";
        case STR:    return "str";
        case DOUBLE: return "double";
        case CHAR:   return "char";
        case FLOAT:  return "float";
        case IDENT:  return self.get_ident_type(node);
        case BIN:    return self.get_type(node.node.bin_node.left[0]);
        case CALL:   return self.get_call_type(node);

        default: io::eprintfn("Unable to match type `%s`", node.node_type);
    }

    return "";
}

fn void SemanticAnalyser.analyse_var(&self, ASTNode node_in)
{
    VarNode node = node_in.node.var_node;
    String[] types = node.types;
    String[] names = node.names;

    foreach (name : names)
    {
        if (name[0].is_upper())
        {
            errors::print_node(self.file_path, node_in, "Variable names must start with a lowercase letter");
            os::exit(1);
        }
    }

    if (types.len != names.len)
    {
        errors::print_node(self.file_path, node_in, string::tformat("Tuple requires %d fields, got %d", types.len, names.len));
        os::exit(1);
    }

    if (types.len > 1)
    {
        // tuple
        for (int i = 0; i < types.len; i++)
        {
            self.add_variable(node_in, types[i], names[i]);
        }
    } else
    {
        ASTNode value = node.value[0];
        self.analyse_node(value);
 
        String name = names[0];
        String type = types[0];
        if (self.get_type(value) != type)
        {
            errors::print_node(self.file_path, node_in, string::tformat("Expected type `%s`, got `%s`", type, self.get_type(value)));
            os::exit(1);
        }
        self.add_variable(node_in, type, name);
    }
}

fn void SemanticAnalyser.add_variable(&self, ASTNode node, String type, String name)
{
    if ((*self.scope).has_var(name))
    {
        SemVar variable = (*self.scope).get_var(name);
        errors::print_node(self.file_path, variable.node, "Previous definition was here");
        errors::print_node(self.file_path, node, string::tformat("Variable `%s` already defined", name));
        os::exit(1);
    }
    
    (*self.scope).variables.set(name, { node, type });
}

fn void SemanticAnalyser.analyse_ext(&self, ASTNode node_in)
{
    ExtNode node = node_in.node.ext_node;
    String type = node.type;
    String name = node.name;

    // TODO
}

fn String SemanticAnalyser.get_ident_type(&self, ASTNode node_in)
{
    IdentNode node = node_in.node.ident_node;
    String name = node.name;
    
    if ((*self.scope).has_var(name))
    {
        SemVar variable = (*self.scope).get_var(name);
        return variable.type;
    }
    
    if ((*self.scope).has_const(name))
    {
        SemConst constant = (*self.scope).get_const(name);
        return constant.type;
    }

    io::eprintfn("Unable to match type `%s`", node_in.node_type);
    os::exit(1);
}

fn void SemanticAnalyser.analyse_bin(&self, ASTNode node_in)
{
    BinNode node = node_in.node.bin_node;
    ASTNode left = *node.left;
    ASTNode right = *node.right;

    self.analyse_node(left);
    self.analyse_node(right);

    if (self.get_type(left) != self.get_type(right))
    {
        errors::print_node(self.file_path, node_in, "Type mismatch");
        os::exit(1);
    }
}

fn bool SemanticAnalyser.has_variable(&self, String name)
{
    return (*self.scope).has_var(name) || (*self.scope).has_const(name);
}

fn void SemanticAnalyser.analyse_ident(&self, ASTNode node_in)
{
    IdentNode node = node_in.node.ident_node;

    String name = node.name;
    if (!self.has_variable(name))
    {
        errors::print_node(self.file_path, node_in, string::tformat("Unable to find variable `%s`", name));
        os::exit(1);
    }
}

fn void SemanticAnalyser.analyse_global(&self, ASTNode node_in)
{
    GlobalNode node = node_in.node.global_node;
    self.analyse_node(node.node[0]);
}

fn String SemanticAnalyser.get_call_type(&self, ASTNode node_in)
{
    CallNode node = node_in.node.call_node;
    String name = node.name;

    Def def;
    foreach (function : self.functions)
    {
        if (function.name == name)
        {
            def = function;
            break;
        }
    }

    String[] types = def.types;
    if (types.len > 1)
    {
        // tuple

    } else
    {
        return types[0];
    }

    return "";
}

// TODO: analyse_call, check arg/param count and param types
fn void SemanticAnalyser.analyse_call(&self, ASTNode node_in)
{
    CallNode node = node_in.node.call_node;
    String name = node.name;

    foreach (arg : node.arguments)
    {
        self.analyse_node(arg);
    }

    bool found;
    foreach (function : self.functions)
    {
        if (function.name == name)
        {
            found = true;
            break;
        }
    }

    if (!found)
    {
        errors::print_node(self.file_path, node_in, string::tformat("Unable to find function `%s`", name));
        os::exit(1);
    }
}

fn void SemanticAnalyser.analyse_if(&self, ASTNode node_in)
{
    IfNode node = node_in.node.if_node;
    ASTNode condition = *node.condition;

    self.analyse_node(condition);

    self.scope = (*self.scope).new();
    foreach (child : node.children)
    {
        self.analyse_node(child);
    }
    self.scope = (*self.scope).parent;

    if (node.else_if != null)
    {
        self.analyse_node(*node.else_if);
    }
    
    self.scope = (*self.scope).new();
    foreach(child : node.else_children)
    {
        self.analyse_node(child);
    }
    self.scope = (*self.scope).parent;
}

fn void SemanticAnalyser.analyse_parameter(&self, ASTNode node_in)
{
    ParameterNode node = node_in.node.parameter_node;

    (*self.scope).variables.set(node.name, { node_in, node.type });
}
