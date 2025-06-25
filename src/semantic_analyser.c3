module lucy::semantic_analyser;

import std::collections::list, std::collections::map, std::os, std::io;
import lucy::node, lucy::errors, lucy::scope::sema, lucy::util, lucy::lookup_table;
import llvm;

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

struct Struct
{
    String      name;
    FieldNode[] fields;
    ASTNode     node;
}

struct SemanticAnalyser
{
    String        file_path;
    ASTNode       ast;
    List{Def}     functions;
    List{Struct}  structs;
    SemScope*     scope;
    TypeTable*    type_table;
}

fn SemanticAnalyser new(String file_path, ASTNode ast, TypeTable* type_table)
{
    SemScope* scope    = malloc(SemScope.sizeof);
    (*scope).parent    = null;
    (*scope).variables = {};
    (*scope).constants = {};
    return {
        .file_path  = file_path,
        .ast        = ast,
        .scope      = scope,
        .type_table = type_table
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
            case EXT: self.add_ext(node);
            case STRUCT: self.add_struct(node);
            case GLOBAL:
                switch INNER: ((*node.node.global_node.node).node_type)
                {
                    case CONST: self.add_const(*node.node.global_node.node);
                    case EXT: self.add_ext(*node.node.global_node.node);
                    case STRUCT: self.add_struct(*node.node.global_node.node);
                    default: break INNER;
                }
            default: break;
        }
    }

    foreach (node : self.ast.node.file_node.children)
    {
        switch (node.node_type)
        {
            case DEF:   self.add_def(node);
            case MACRO: self.add_macro(node);
            case GLOBAL:
                switch INNER: ((*node.node.global_node.node).node_type)
                {
                    case DEF:   self.add_def(*node.node.global_node.node);
                    case MACRO: self.add_macro(*node.node.global_node.node);
                    default:  break INNER;
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

fn void SemanticAnalyser.add_macro(&self, ASTNode node_in)
{
    MacroNode node  = node_in.node.macro_node;
    String[]  types = {node.type};
    String    name  = node.name;

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
        String[] types = mem::new_array(String, 1);
        types[0] = type;
        self.functions.push({ node_in, types, alias_name != "" ? alias_name : name });
    }
}

fn void SemanticAnalyser.add_struct(&self, ASTNode node_in)
{
    StructNode node = node_in.node.struct_node;
    String     name = node.name;

    FieldNode[] fields = mem::new_array(FieldNode, node.fields.len);
    foreach (i, field : node.fields)
    {
        fields[i] = field.node.field_node;
    }

    self.structs.push({ name, fields, node_in });
    
    Field* type_fields = malloc(Field.sizeof * (node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT));
    Type* type = malloc(Type.sizeof);
    LLVMTypeRef* llvm_type = malloc(LLVMTypeRef.sizeof);
    *llvm_type = null;
    (*type) = { name.zstr_copy(mem), type_fields, node.fields.len, llvm_type, self.type_table.type_id++ };
    (*self.type_table).insert(type);
}

fn void SemanticAnalyser.analyse_node(&self, ASTNode node)
{
    switch (node.node_type)
    {
        case CONST:     self.analyse_const(node);
        case REASSIGN:  self.analyse_reassign(node);
        case DEF:       self.analyse_def(node);
        case VAR:       self.analyse_var(node);
        case EXT:       self.analyse_ext(node);
        case BIN:       self.analyse_bin(node);
        case IDENT:     self.analyse_ident(node);
        case GLOBAL:    self.analyse_global(node);
        case CALL:      self.analyse_call(node);
        case IF:        self.analyse_if(node);
        case PARAMETER: self.analyse_parameter(node);
        //case INIT:      util::panic("Init analyser not implemented", $$FILE, $$LINE);
        case STRUCT:    self.analyse_struct(node);
        case ACCESS:    self.analyse_access(node);
        case WHILE:     self.analyse_while(node);
        
        case MACRO:
        case STR:
        case INIT:
        case INT:
        case BOOL:
        case FLOAT:
        case DOUBLE:
        case UNARY:
        case SWITCH:
        case RETURN: break;
        default: util::panicf("missing analyse function `%s`", node.node_type, file: $$FILE, line: $$LINE);
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
        case BIN:    return self.get_type(*node.node.bin_node.left);
        case CALL:   return self.get_call_type(node);
        case INIT:   return self.get_struct_type(node);
        case ACCESS: return self.get_access_type(node);

        default: util::panicf("Unable to match type `%s`", node.node_type, file: $$FILE, line: $$LINE);
    }
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
        String name = names[0];
        String type = types[0];
        
        if (node.value)
        {
            ASTNode value = *node.value;
            self.analyse_node(value);
 
            if (self.get_type(value) != type)
            {
                errors::print_node(self.file_path, node_in, string::tformat("Expected type `%s`, got `%s`", type, self.get_type(value)));
                os::exit(1);
            }
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
    
    errors::print_node(self.file_path, node_in, string::tformat("Unable to match type for variable `%s`", name));
    os::exit(1);
}

fn void SemanticAnalyser.analyse_bin(&self, ASTNode node_in)
{
    BinNode node = node_in.node.bin_node;
    ASTNode left = *node.left;
    ASTNode right = *node.right;

    self.analyse_node(left);
    self.analyse_node(right);

    String left_type  = self.get_type(left);
    String right_type = self.get_type(right);

    if (left_type != right_type)
    {
        errors::print_node(self.file_path, node_in, string::tformat("Type mismatch: `%s` and `%s`", left_type, right_type));
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
        util::panic("sema -> Unimplemented", $$FILE, $$LINE);
    } else
    {
        return types[0];
    }
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
    Def def;
    foreach (function : self.functions)
    {
        if (function.name == name)
        {
            def = function;
            found = true;
            break;
        }
    }

    if (!found)
    {
        errors::print_node(self.file_path, node_in, string::tformat("Unable to find function `%s`", name));
        os::exit(1);
    }

    // figure out if function is macro
    if (def.node.node_type == MACRO)
    {
        self.analyse_macro(def.node, node.arguments);
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

fn String SemanticAnalyser.get_struct_type(&self, ASTNode node_in)
{
    InitNode node = node_in.node.init_node;
    InitValueNode[] values = mem::new_array(InitValueNode, node.values.len);
    
    foreach (i, value : node.values)
    {
        values[i] = value.node.init_value_node;
    }
    
    String[] possible_structs = mem::new_array(String, 0);

    foreach STRUCTS: (i, str : self.structs)
    {
        if (str.fields.len != values.len) continue;
        foreach (j, field : str.fields)
        {
            if (field.type != self.get_type(*values[j].value)) continue STRUCTS;
        }
        util::array_insert(&possible_structs, str.name);
    }
    
    if (possible_structs.len > 1)
    {
        errors::print_node(self.file_path, node_in, "Initializer can be of more than one type. Please typecast it");
        os::exit(1);
    }

    if (possible_structs.len == 0)
    {
        errors::print_node(self.file_path, node_in, "Unable find a type with those fields");
        os::exit(1);
    }
    
    return possible_structs[0];
}

// TODO: move to new function
/*fn void SemanticAnalyser.analyse_struct(&self, ASTNode node_in)
{
    StructNode node = node_in.node.struct_node;
    
    HashMap{String, ASTNode} prev;
    prev.init(mem, node.fields.len);
    defer prev.free();
    foreach (field_node : node.fields)
    {
        FieldNode field = field_node.node.field_node;
        if (prev.has_key(field.name))
        {
            errors::print_node(self.file_path, prev.get(field.name)!!, "Previous definition was here");
            errors::print_node(self.file_path, field_node, string::tformat("Field `%s` already defined", field.name));
            os::exit(1);
        }
        prev.set(field.name, field_node);
    }
}*/

fn void SemanticAnalyser.analyse_access(&self, ASTNode node_in)
{
    AccessNode node = node_in.node.access_node;

    if (self.type_table.has((char*)node.id.zstr_copy(mem)))
    {
        Type* base_type = self.type_table.lookup(node.id);
        Type* type = self.resolve_access(base_type, node.id, node.node);
        
        if (!type)
        {
            io::eprintfn("sema -> Unknown type `%s` (%s:%d)", node.id, $$FILE, $$LINE);
            os::exit(1);
        }
        return;
    }

    if (!self.scope.has_var(node.id))
    {
        errors::print_node(self.file_path, node_in, string::tformat("Unable to find variable `%s`", node.id));
        os::exit(1);
    }

    SemVar variable = self.scope.get_var(node.id);
    Type* base_type = self.type_table.lookup(variable.type);

    Type* type = self.resolve_access(base_type, node.id, node.node);
    if (!type)
    {
        io::eprintfn("sema -> Unknown type `%s` (%s:%d)", node.id, $$FILE, $$LINE);
        os::exit(1);
    }
}

// TODO: recursive function for resolving full path
fn Type* SemanticAnalyser.resolve_access(&self, Type* base_type, char* prev, ASTNode* next)
{
    if (!next)
    {
        return base_type;
    }

    switch ((*next).node_type)
    {
        case ACCESS:
            AccessNode access_node = next.node.access_node;
            Field* field           = base_type.get_field(access_node.id);
            if (!field)
            {
                ASTNode struct_node;
                foreach (str : self.structs)
                {
                    if (str.name == ((ZString)base_type.name).str_view())
                    {
                        struct_node = str.node;
                    }
                }
                errors::print_node(self.file_path, struct_node, "Definition was here");
                errors::print_node(self.file_path, *next, string::tformat("Type `%s` has no field `%s`", (ZString)base_type.name, access_node.id));
                os::exit(1);
            }
            return self.resolve_access(field.type, access_node.id.zstr_copy(mem), access_node.node);
        case IDENT:
            char*  field_name = next.node.ident_node.name.zstr_copy(mem);
            Field* field      = base_type.get_field(field_name);
            if (!field)
            {
                ASTNode struct_node;
                foreach (str : self.structs)
                {
                    if (str.name == ((ZString)base_type.name).str_view())
                    {
                        struct_node = str.node;
                    }
                }
                errors::print_node(self.file_path, *next, string::tformat("Type `%s` has no field `%s`", (ZString)base_type.name, (ZString)field_name));
                os::exit(1);
            }
            return (*field).type;
        default:
            util::panic("Unreachable", $$FILE, $$LINE);
    }
}

fn void SemanticAnalyser.analyse_struct(&self, ASTNode node_in)
{
    StructNode node = node_in.node.struct_node;
    String     name = node.name;

    FieldNode[] fields = mem::new_array(FieldNode, node.fields.len);
    foreach (i, field : node.fields)
    {
        fields[i] = field.node.field_node;
    }

    Type* type = self.type_table.lookup(name);

    foreach (i, field : fields)
    {
        ((Field[])type.fields[:node.fields.len])[i].name = field.name;
        ((Field[])type.fields[:node.fields.len])[i].type = self.type_table.lookup(field.type);
        if (!fields[i].type)
        {
            io::eprintfn("Error: unknown type `%s` for field `%s`", field.type, field.name);
            os::exit(1);
        }
    }

    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 0].name = "$typeid";
    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 0].type = self.type_table.lookup("int");

    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 1].name = "$typekind";
    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 1].type = self.type_table.lookup("str");
    
    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 2].name = "$typename";
    ((Field[])type.fields[:node.fields.len + lookup_table::BUILTIN_TYPE_FIELD_COUNT])[node.fields.len + 2].type = self.type_table.lookup("str");
}

fn void SemanticAnalyser.analyse_while(&self, ASTNode node_in)
{
    WhileNode node = node_in.node.while_node;
    self.analyse_node(*node.condition);

    foreach (child : node.children)
    {
        self.analyse_node(child);
    }
}

fn String SemanticAnalyser.get_access_type(&self, ASTNode node_in)
{
    AccessNode node = node_in.node.access_node;
    
    if (self.type_table.has((char*)node.id.zstr_copy(mem)))
    {
        Type* base_type = self.type_table.lookup(node.id);
        Type* type = self.resolve_access(base_type, node.id, node.node);
        
        if (!type)
        {
            io::eprintfn("sema -> Unknown type `%s` (%s:%d)", node.id, $$FILE, $$LINE);
            os::exit(1);
        }
        return ((ZString)type.name).str_view();
    }

    if (!self.scope.has_var(node.id))
    {
        errors::print_node(self.file_path, node_in, string::tformat("Unable to find variable `%s`", node.id));
        os::exit(1);
    }

    SemVar variable = self.scope.get_var(node.id);
    Type* base_type = self.type_table.lookup(variable.type);

    Type* type = self.resolve_access(base_type, node.id, node.node);
    if (!type)
    {
        io::eprintfn("sema -> Unknown type `%s` (%s:%d)", node.id, $$FILE, $$LINE);
        os::exit(1);
    }

    return ((ZString)type.name).str_view();
}

// TODO: somehow pass param type from call 
fn void SemanticAnalyser.analyse_macro(&self, ASTNode node_in, ASTNode[] arguments)
{
    MacroNode node = node_in.node.macro_node;
    
    self.scope = (*self.scope).new();
    foreach (i, param : node.parameters)
    {
        Type* type = self.type_table.lookup(self.get_type(arguments[i]));
        param.node.parameter_node.type = ((ZString)type.name).str_view();
        self.analyse_parameter(param);
    }

    foreach (child : node.children)
    {
        self.analyse_node(child);
    }
    self.scope = self.scope.parent;
}
