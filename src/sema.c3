module lucy::sema;

import lucy::scope, lucy::node, lucy::types, lucy::util, lucy::errors, lucy::lexer, lucy::parser;
import std::os, std::collections::map, std::io;

struct Sema
{
    String                   path;
    Scope*                   scope;
    ASTNode*                 ast;
    TypeTable*               types;
    String[]                 links;
    HashMap{ String, Sema* } packages;
}

fn bool  Sema.has_pkg(&self, String name) => self.packages.has_key(name);
fn Sema* Sema.get_pkg(&self, String name) => self.packages.get(name)!!;

fn void Sema.get_all_pkg_names(&self, String[]* pkgs)
{
    foreach (pkg : self.packages.keys(mem))
    {
        util::array_insert(pkgs, pkg);
    }
}

fn Sema new(String path, Scope* scope, TypeTable* types, String[] links, ASTNode* ast)
{
    return
    {
        path,
        scope,
        ast,
        types,
        links,
        {}
    };
}

fn void Sema.analyse(&self)
{
    foreach (statement : self.ast.node.file_node.statements)
    {
        self.register_node(statement);
    }

    foreach (link : self.links)
    {
        String content = (String)file::load(mem, link)!!;
        Lexer  lexer   = lexer::new(content);

        Parser   parser = parser::new(lexer, link);
        ASTNode* ast    = parser.parse();

        String pkg = util::stringify_path(ast.node.file_node.pkg.node.pkg_node.path);
        bool   found;

        foreach INNER: (use : self.packages.keys(mem))
        {
            if (pkg == use)
            {
                found = true;
                break INNER;
            }
        }

        if (found)
        {
            Scope* scope = scope::new();
            Sema   sema  = sema::new(link, scope, self.types, self.links, ast);
            sema.analyse();

            Sema* sema_ptr = malloc(Sema.sizeof);
            *sema_ptr = sema;

            self.packages.set(pkg, sema_ptr);
        }
    }

    foreach (pkg : self.packages.keys(mem))
    {
        if (!self.get_pkg(pkg))
        {
            self.packages.remove(pkg);
        }
    }

    foreach (statement : self.ast.node.file_node.statements)
    {
        self.analyse_node(statement);
    }
}

fn void Sema.register_node(&self, ASTNode* node)
{
    switch (node.node_type)
    {
        case EXT:    self.register_ext(node);
        case DEF:    self.register_def(node);
        case USE:    self.register_use(node);
        case CONST:  self.register_const(node);
        case MACRO:  self.register_macro(node);
        case STRUCT: self.register_struct(node);

        default: break;
    }
}

fn void Sema.register_ext(&self, ASTNode* node_in)
{
    ExtNode node = node_in.node.ext_node;

    String name = node.name.node.ident_node.name;
    if (!util::is_null(node.aka)) name = node.aka.node.ident_node.name;
    
    if (self.scope.has_def(name))
    {
        errors::print_node(self.path, *self.scope.get_def(name).node, errors::ERROR_PREVIOUS);
        errors::print_node(self.path, *node_in, "A function with this name is already defined.");
        os::exit(1);
    }

    String type_name = node.type.node.ident_node.name;
    self.scope.functions.set(name, { type_name, node_in, null });
}

fn void Sema.register_def(&self, ASTNode* node_in)
{
    DefNode node = node_in.node.def_node;

    String name = node.name.node.ident_node.name;
    if (self.scope.has_def(name))
    {
        errors::print_node(self.path, *self.scope.get_def(name).node, errors::ERROR_PREVIOUS);
        errors::print_node(self.path, *node.name, "A Function with this name already exists.");
        os::exit(1);
    }

    self.scope.functions.set(name, { util::get_type_node(node_in, self.scope, self.path), node_in, null });
}

fn void Sema.register_const(&self, ASTNode* node_in)
{
    ConstNode node = node_in.node.const_node;
    String    name = node.name.node.ident_node.name;

    if (self.scope.has_const(name))
    {
        errors::print_node(self.path, *self.scope.get_const(name).node, errors::ERROR_PREVIOUS);
        errors::print_node(self.path, *node.name, "A constant with this name already exists.");
        os::exit(1);
    }

    String type_name = node.type.node.ident_node.name;
    self.scope.constants.set(name, { type_name, node_in, null });
}

fn void Sema.register_struct(&self, ASTNode* node_in)
{
    StructNode node = node_in.node.struct_node;
    String name = node.name.node.ident_node.name;
    
    if (self.types.lookup(name))
    {
        errors::print_node(self.path, *node.name, "A Type with this name already exists.");
        os::exit(1);
    }

    Field* fields = malloc(Field.sizeof * node.fields.len);
    foreach (i, field : node.fields)
    {
        FieldNode field_node = field.node.field_node;
        String    type_name  = field_node.type.node.ident_node.name;

        ((Field[])fields[:node.fields.len])[i] = { name.zstr_copy(mem), self.types.lookup(type_name) };
    }

    self.types.insert_type(name, fields, null);
    self.scope.structs.set(name, node);
}

fn void Sema.register_use(&self, ASTNode* node_in)
{
    UseNode node = node_in.node.use_node;
    String  pkg  = util::stringify_path(node.path);

    self.packages.set(pkg, null);
}

fn void Sema.register_macro(&self, ASTNode* node_in)
{
    MacroNode node = node_in.node.macro_node;

    String name = node.name.node.ident_node.name;
    if (self.scope.has_def(name))
    {
        errors::print_node(self.path, *self.scope.get_def(name).node, errors::ERROR_PREVIOUS);
        errors::print_node(self.path, *node.name, "A Function with this name already exists.");
        os::exit(1);
    }

    self.scope.functions.set(name, { node.type.node.ident_node.name, node_in, null });
}

fn void Sema.analyse_node(&self, ASTNode* node, ASTNode* def = null)
{
    switch (node.node_type)
    {
        case IF:         self.analyse_if(node, def);
        case USE:        self.analyse_use(node);
        case EXT:        self.analyse_ext(node);
        case DEF:        self.analyse_def(node);
        case VAR:        self.analyse_var(node);
        case BIN:        self.analyse_bin(node);
        case INC:        self.analyse_inc(node);
        case FOR:        self.analyse_for(node, def);
        case INIT:       self.analyse_init(node);
        case CALL:       self.analyse_call(node);
        case CONST:      self.analyse_const(node);
        case UNARY:      self.analyse_unary(node);
        case WHILE:      self.analyse_while(node, def);
        case IDENT:      self.analyse_ident(node);
        // case MACRO:      self.analyse_macro(node);
        case STRUCT:     self.analyse_struct(node);
        case ACCESS:     self.analyse_access(node);
        case SWITCH:     self.analyse_switch(node, def);
        case RETURN:     self.analyse_return(node, def);
        case REASSIGN:   self.analyse_reassign(node);
        case PARAMETER:  self.analyse_parameter(node);
        case INIT_VALUE: self.analyse_init_value(node);

        case INT:
        case STR:
        case BOOL:
        case CHAR:
        case FLOAT:
        case MACRO:
        case DOUBLE:
            break;

        default: util::panicf("missing sema function for type `%s`", node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
    }
}

fn void Sema.analyse_use(&self, ASTNode* node_in)
{
    UseNode node = node_in.node.use_node;
    String  name = util::stringify_path(node.path);

    if (!self.has_pkg(name))
    {
        errors::print_node(self.path, *node_in, string::format(mem, "Unable to find module `%s`", name));
        os::exit(1);
    }
}

fn void Sema.analyse_ext(&self, ASTNode* node_in)
{
    ExtNode node = node_in.node.ext_node;
    
    HashMap{ String, ASTNode* } previous_parameters;
    foreach (parameter : node.parameters)
    {
        ParameterNode parameter_node = parameter.node.parameter_node;

        self.analyse_node(parameter);

        String name = parameter_node.name.node.ident_node.name;
        if (previous_parameters.has_key(name))
        {
            errors::print_node(self.path, *previous_parameters.get(name)!!, errors::ERROR_PREVIOUS);
            errors::print_node(self.path, *parameter, "A parameter with this name is already defined.");
            os::exit(1);
        }

        previous_parameters.set(name, parameter);
    }
}

fn void Sema.analyse_struct(&self, ASTNode* node_in)
{
    StructNode node = node_in.node.struct_node;

    if (node.fields.len == 0)
    {
        errors::print_node(self.path, *node.name, "Empty structs are not allowed.");
        os::exit(1);
    }

    HashMap{ String, ASTNode* } previous_fields;
    foreach (field : node.fields)
    {
        FieldNode field_node = field.node.field_node;

        String name = field_node.name.node.ident_node.name;
        if (previous_fields.has_key(name))
        {
            errors::print_node(self.path, *previous_fields.get(name)!!, errors::ERROR_PREVIOUS);
            errors::print_node(self.path, *field, "A field with this name is already defined.");
            os::exit(1);
        }

        previous_fields.set(name, field);
    }

    String name = node.name.node.ident_node.name;

    if (name[0].is_lower())
    {
        errors::print_node(self.path, *node.name, "Type names must start with an uppercase letter.");
        os::exit(1);
    }

    if (name.is_upper())
    {
        errors::print_node(self.path, *node.name, "Type names cannot be all uppercase.");
        os::exit(1);
    }
}

fn void Sema.analyse_const(&self, ASTNode* node_in)
{
    ConstNode node = node_in.node.const_node;

    if (!util::is_builtin_type(node.type))
    {
        errors::print_node(self.path, *node.type, "Constants can only have a base type.");
        os::exit(1);
    }

    String name = node.name.node.ident_node.name;
    if (!name.is_upper())
    {
        errors::print_node(self.path, *node.name, "Constant names must be all uppercase.");
        os::exit(1);
    }

    String type = node.type.node.ident_node.name;
    if (type != util::get_type_node(node.value, self.scope, self.path))
    {
        errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", type, util::get_type_node(node.value, self.scope, self.path)));
        os::exit(1);
    }

    self.analyse_node(node.value);
}

fn void Sema.analyse_def(&self, ASTNode* node_in)
{
    DefNode node = node_in.node.def_node;
    
    if (node.type.node_type == IDENT)
    {
        String type = node.type.node.ident_node.name;
        if (!self.types.lookup(type))
        {
            errors::print_node(self.path, *node.type, string::format(mem, "Could not find type `%s`.", type));
            os::exit(1);
        }
    } else
    {
        foreach (type_node : node.type.node.tuple_node.values)
        {
            String type = type_node.node.ident_node.name;
            if (!self.types.lookup(type))
            {
                errors::print_node(self.path, *type_node, string::format(mem, "Could not find type `%s`.", type));
                os::exit(1);
            }
        }
    }

    HashMap{ String, ASTNode* } previous_parameters;
    foreach (parameter : node.parameters)
    {
        ParameterNode parameter_node = parameter.node.parameter_node;

        if (util::is_null(parameter_node.type))
        {
            errors::print_node(self.path, *parameter, "Untyped parameters are only allowed for macros.");
            os::exit(1);
        }

        if (parameter_node.is_vararg)
        {
            errors::print_node(self.path, *parameter, "Variatric parameters are not allowed for functions.");
            os::exit(1);
        }

        String name = parameter_node.name.node.ident_node.name;
        if (previous_parameters.has_key(name))
        {
            errors::print_node(self.path, *previous_parameters.get(name)!!, errors::ERROR_PREVIOUS);
            errors::print_node(self.path, *parameter, "A parameter with this name is already defined.");
            os::exit(1);
        }

        previous_parameters.set(name, parameter);
    }

    self.scope = self.scope.new();
    foreach (parameter : node.parameters)
    {
        self.analyse_node(parameter);
    }

    foreach (child : node.children)
    {
        self.analyse_node(child, node_in);
    }

    self.scope = self.scope.parent;
}

fn void Sema.analyse_parameter(&self, ASTNode* node_in)
{
    ParameterNode node = node_in.node.parameter_node;

    String name      = node.name.node.ident_node.name;
    String type_name = "void";
    if (!util::is_null(node.type)) type_name = node.type.node.ident_node.name;

    if (!self.types.lookup(type_name))
    {
        errors::print_node(self.path, *node.type, string::format(mem, "Could not find type `%s`.", type_name));
        os::exit(1);
    }

    self.scope.parameters.set(name, { type_name, node_in, null });
}

fn void Sema.analyse_var(&self, ASTNode* node_in)
{
    VarNode node = node_in.node.var_node;

    if (node.type.node_type == IDENT)
    {
        IdentNode type_node = node.type.node.ident_node;
        String    type_name = node.type.node.ident_node.name;
        if (!self.types.lookup(type_name))
        {
            errors::print_node(self.path, *node.type, string::format(mem, "Could not find type `%s`.", type_name));
            os::exit(1);
        }

        String name = node.names[0].node.ident_node.name;
        if (self.scope.has(name))
        {
            errors::print_node(self.path, *self.scope.get(name).get_node(), errors::ERROR_PREVIOUS);
            errors::print_node(self.path, *node.names[0], "A Variable with this name already exists.");
            os::exit(1);
        }

        if (node.value.node_type == INIT)
        {
            self.analyse_node(node.value);
            String[] possible_types = util::get_possible_types(node.value.node.init_node, self.scope, self.path);

            if (!util::in(possible_types, type_name))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`.", type_name));
                os::exit(1);
            }
        } else if (node.value.node_type != NULL)
        {
            self.analyse_node(node.value);
            
            if (type_name != util::get_type_node(node.value, self.scope, self.path))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", type_name, util::get_type_node(node.value, self.scope, self.path)));
                os::exit(1);
            }
        }

        self.scope.variables.set(name, { type_name, node_in, null });
    } else
    {
        TupleNode type_node = node.type.node.tuple_node;

        foreach (type : type_node.values)
        {
            String type_name = type.node.ident_node.name;
            if (!self.types.lookup(type_name))
            {
                errors::print_node(self.path, *node.type, string::format(mem, "Could not find type `%s`.", type_name));
                os::exit(1);
            }
        }

        if (type_node.values.len > node.names.len)
        {
            errors::print_node(self.path, *node.type, string::format(mem, "Missing variable name, expected %d but only got %d.", type_node.values.len, node.names.len));
            os::exit(1);
        }
        if (type_node.values.len < node.names.len)
        {
            errors::print_node(self.path, *node.type, string::format(mem, "Too many variable names, expected %d but got %d.", type_node.values.len, node.names.len));
            os::exit(1);
        }

        foreach (name : node.names)
        {
            IdentNode name_node  = name.node.ident_node;
            String    name_value = name_node.name;
            if (self.scope.has(name_node.name))
            {
                
                errors::print_node(self.path, *self.scope.get(name_value).get_node(), errors::ERROR_PREVIOUS);
                errors::print_node(self.path, *name, "A Variable with this name already exists.");
                os::exit(1);
            }
        }

        if (node.value.node_type != NULL)
        {
            self.analyse_node(node.value);
            
            if (util::get_type_node(node.type, self.scope, self.path) != util::get_type_node(node.value, self.scope, self.path))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", util::get_type_node(node.type, self.scope, self.path), util::get_type_node(node.value, self.scope, self.path)));
                os::exit(1);
            }
        }

        foreach (i, name : node.names)
        {
            String name_value = name.node.ident_node.name;
            String type       = type_node.values[i].node.ident_node.name;
            self.scope.variables.set(name_value, { type, node_in, null });
        }
    }

    if (node.value.node_type != NULL)
    {
        self.analyse_node(node.value);
    }
}

fn void Sema.analyse_init(&self, ASTNode* node_in)
{
    InitNode node = node_in.node.init_node;

    foreach (value : node.values)
    {
        self.analyse_node(value);
    }
}

fn void Sema.analyse_init_value(&self, ASTNode* node_in)
{
    InitValueNode node = node_in.node.init_value_node;
    
    self.analyse_node(node.value);
}

fn void Sema.analyse_call(&self, ASTNode* node_in)
{
    CallNode node = node_in.node.call_node;

    String name = node.name.node.ident_node.name;
    if (!self.scope.has_def(name))
    {
        errors::print_node(self.path, *node.name, string::format(mem, "Could not find function `%s`.", name));
        os::exit(1);
    }

    Def def = self.scope.get_def(name);
    if (def.node.node_type == DEF)
    {
        DefNode def_node = def.node.node.def_node;
        if (node.arguments.len > def_node.parameters.len)
        {
            errors::print_node(self.path, *def_node.name, "Definition was here.");
            errors::print_node(self.path, *node.arguments[node.arguments.len - 1], "This argument would exceed the argument size.");
            os::exit(1);
        }
        if (node.arguments.len < def_node.parameters.len)
        {
            errors::print_node(self.path, *def_node.name, "Definition was here.");
        
            if (node.arguments.len != 0)
            {
                errors::print_node(self.path, *node.arguments[node.arguments.len - 1], "Expected more arguments after this one.");
            } else
            {
                errors::print_node(self.path, *node.name, "Expected arguments.");
            }
        
            os::exit(1);
        }

        foreach (i, arg : node.arguments)
        {
            ASTNode* param      = def_node.parameters[i];
            String   arg_type   = util::get_type_node(arg, self.scope, self.path);
            String   param_type = util::get_type_node(param, self.scope, self.path);

            if (arg_type != param_type)
            {
                errors::print_node(self.path, *param, "Definition was here.");
                errors::print_node(self.path, *arg, string::format(mem, "Expected type `%s`, got `%s`.", param_type, arg_type));
                os::exit(1);
            }
        }
    } else
    {
        MacroNode macro_node = def.node.node.macro_node;

        self.analyse_macro(def.node, node.arguments);
        
        /*
        if (node.arguments.len < macro_node.parameters.len)
        {
            
        }

        */
    }

    foreach (arg : node.arguments)
    {
        self.analyse_node(arg);
    }
}

fn void Sema.analyse_unary(&self, ASTNode* node_in)
{
    UnaryNode node         = node_in.node.unary_node;
    String    value_type   = util::get_type_node(node.expr, self.scope, self.path);

    if (!self.types.lookup(value_type))
    {
        errors::print_node(self.path, *node.expr, string::format(mem, "Could not find type `%s`", value_type));
        os::exit(1);
    }

    String[]  number_types = { "int", "float", "double" };

    switch (node.operator)
    {
        case "+":
        case "-":
            if (!util::in(number_types, value_type))
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Invalid unary operator for type %s", value_type));
                os::exit(1);
            }
        case "!":
            if (value_type != "bool")
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Invalid unary operator for type %s", value_type));
                os::exit(1);
            }
    }
}

fn void Sema.analyse_access(&self, ASTNode* node_in)
{
    AccessNode node  = node_in.node.access_node;
    IdentNode  ident = node.expr.node.ident_node; // assume it's ident for now since call on expression is still unsupported e.g. "Test".$length

    ZString id_name   = ident.name.zstr_copy(mem);
    String  type_name;
    Type*   type      = null;
    
    if (self.scope.has(ident.name))
    {
        type_name = self.scope.get(ident.name).get_type();
        type      = self.types.lookup(type_name);
    }

    self.resolve_access(type, ident.name, node.expr, node.next);
}

fn void Sema.resolve_access(&self, Type* prev_type, String prev_name, ASTNode* prev_node, ASTNode* next_node)
{
    if (!prev_type)
    {
        String[] pkg_names;
        self.get_all_pkg_names(&pkg_names);
        String[] possible_pkgs = util::get_possible_pkgs(pkg_names, prev_name);

        if (possible_pkgs.len > 1)
        {
            errors::print_node(self.path, *prev_node, "Multiple imports with this name found. Please specify.");
            os::exit(1);
        }

        if (possible_pkgs.len == 0)
        {
            errors::print_node(self.path, *prev_node, string::format(mem, "Unable to find `%s`.", prev_name));
            os::exit(1);
        }

        String pkg_name  = possible_pkgs[0];
        Sema*  pkg       = self.get_pkg(pkg_name);
        switch (next_node.node_type)
        {
            case IDENT:
                IdentNode ident_node = next_node.node.ident_node;
                String    ident_name = ident_node.name;
                if (!pkg.scope.has_const(ident_name))
                {
                    errors::print_node(self.path, *next_node, string::format(mem, "Could not find constant `%s` in package `%s`.", ident_name, pkg_name));
                    os::exit(1);
                }
            case CALL:
                CallNode call_node = next_node.node.call_node;
                String   call_name = call_node.name.node.ident_node.name;
                if (!pkg.scope.has_def(call_name))
                {
                    errors::print_node(self.path, *next_node.node.call_node.name, string::format(mem, "Could not find function `%s` in package `%s`.", call_name, pkg_name));
                    os::exit(1);
                }

                // TODO: check if macro and invoke argument type to analyse parmeters

                Def     def      = pkg.scope.get_def(call_name);
                DefNode def_node = def.node.node.def_node;
                if (call_node.arguments.len > def_node.parameters.len)
                {
                    errors::print_node(pkg.path, *def_node.name, "Definition was here.");
                    errors::print_node(self.path, *call_node.arguments[call_node.arguments.len - 1], "This argument would exceed the argument size.");
                    os::exit(1);
                }
                if (call_node.arguments.len < def_node.parameters.len)
                {
                    errors::print_node(pkg.path, *def_node.name, "Definition was here.");

                    if (call_node.arguments.len != 0)
                    {
                        errors::print_node(self.path, *call_node.arguments[call_node.arguments.len - 1], "Expected more arguments after this one.");
                    } else
                    {
                        errors::print_node(self.path, *call_node.name, "Expected arguments.");
                    }

                    os::exit(1);
                }

                foreach (i, arg : call_node.arguments)
                {
                    ASTNode* param      = def_node.parameters[i];
                    String   arg_type   = util::get_type_node(arg, self.scope, self.path);
                    String   param_type = util::get_type_node(param, self.scope, self.path);

                    if (param_type == "void") continue;

                    if (arg_type != param_type)
                    {
                        errors::print_node(pkg.path,  *param, "Definition was here.");
                        errors::print_node(self.path, *arg, string::format(mem, "Expected type `%s`, got `%s`.", param_type, arg_type));
                        os::exit(1);
                    }
                }

                foreach (arg : call_node.arguments)
                {
                    self.analyse_node(arg);
                }
            default:
                util::panicf("Unsupported node type in access chain: `%s`", next_node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
        }
    } else
    {
        switch (next_node.node_type)
        {
            case IDENT:
                IdentNode ident_node = next_node.node.ident_node;
                String    ident_name = ident_node.name;

                if (prev_type.name == "void") return;

                if (prev_type.get_field(ident_name))
                {
                    io::printn("asasas");
                }
            default:
                util::panicf("Unsupported node type in access chain: `%s`", next_node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
        }

        // handle get from var; handle nested builtin fields e.g. $length.$typeid
        util::panic("Unfinished method", $$FILE, $$LINE, $$FUNC);
    }
}

fn void Sema.analyse_while(&self, ASTNode* node_in, ASTNode* def)
{
    WhileNode node = node_in.node.while_node;

    self.analyse_node(node.condition);

    if (util::get_type_node(node.condition, self.scope, self.path) != "bool")
    {
        errors::print_node(self.path, *node.condition, string::format(mem, "Condition cannot be of type `%s`.", util::get_type_node(node.condition, self.scope, self.path)));
        os::exit(1);
    }

    self.scope = self.scope.new();

    foreach (child : node.children)
    {
        self.analyse_node(child, def);
    }

    self.scope = self.scope.parent;
}

fn void Sema.analyse_bin(&self, ASTNode* node_in)
{
    BinNode node     = node_in.node.bin_node;
    String  operator = node.operator;

    self.analyse_node(node.left);
    self.analyse_node(node.right);

    String left_type  = util::get_type_node(node.left, self.scope, self.path);
    String right_type = util::get_type_node(node.right, self.scope, self.path);

    String[] number_types = { "int", "float", "double" };

    switch (operator)
    {
        case "==":
        case "!=":
            if (left_type != right_type)
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Type mismatch `%s` and `%s`", left_type, right_type));
                os::exit(1);
            }
        case "+":
            if (left_type != right_type)
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Type mismatch `%s` and `%s`", left_type, right_type));
                os::exit(1);
            }

            bool is_number_type = util::in(number_types, left_type) && util::in(number_types, right_type);
            bool is_string_type = left_type == "str" && right_type == "str";

            if (!is_number_type && !is_string_type)
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Unsupported binary operation for type `%s`", left_type));
                os::exit(1);
            }
        case "-":
        case "*":
        case "/":
        case ">":
        case "<":
        case ">=":
        case "<=":
            if (left_type != right_type)
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Type mismatch `%s` and `%s`", left_type, right_type));
                os::exit(1);
            }

            bool is_number_type = util::in(number_types, left_type) && util::in(number_types, right_type);

            if (!is_number_type)
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Unsupported binary operation for type `%s`", left_type));
                os::exit(1);
            }
    }
}

fn void Sema.analyse_ident(&self, ASTNode* node_in)
{
    IdentNode node = node_in.node.ident_node;
    String    name = node.name;

    if (!self.scope.has(name))
    {
        errors::print_node(self.path, *node_in, string::format(mem, "Unable to find variable `%s`", name));
        os::exit(1);
    }
}

fn void Sema.analyse_inc(&self, ASTNode* node_in)
{
    IncNode node       = node_in.node.inc_node;
    String  operator   = node.operator;
    String  identifier = node.identifier.node.ident_node.name;

    if (!self.scope.has_var(identifier))
    {
        errors::print_node(self.path, *node.identifier, string::format(mem, "Unable to find variable `%s`", identifier));
        os::exit(1);
    }

    String type = util::get_type_node(node.identifier, self.scope, self.path);

    switch (operator)
    {
        case "+":
        case "-":
            if (type != "int")
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Unsupported incremental operation for type `%s`", type));
                os::exit(1);
            }
        case "!":
            if (type != "bool")
            {
                errors::print_node(self.path, *node_in, string::format(mem, "Unsupported incremental operation for type `%s`", type));
                os::exit(1);
            }
    }
}

fn void Sema.analyse_for(&self, ASTNode* node_in, ASTNode* def)
{
    ForNode node = node_in.node.for_node;

    self.scope = self.scope.new();

    self.analyse_node(node.statement);
    self.analyse_node(node.condition);

    foreach (child : node.children)
    {
        self.analyse_node(child, def);
    }

    self.analyse_node(node.expression);

    self.scope = self.scope.parent;
}

fn void Sema.analyse_if(&self, ASTNode* node_in, ASTNode* def)
{
    IfNode node = node_in.node.if_node;

    self.analyse_node(node.condition);

    self.scope = self.scope.new();

    foreach (child : node.children)
    {
        self.analyse_node(child, def);
    }

    self.scope = self.scope.parent;

    if (node.else_if.node_type == IF)
    {
        self.analyse_node(node.else_if, def);
    }

    foreach (child : node.else_children)
    {
        self.analyse_node(child, def);
    }
}

fn void Sema.analyse_switch(&self, ASTNode* node_in, ASTNode* def)
{
    SwitchNode node = node_in.node.switch_node;

    ASTNode* left = node.expression;
    self.analyse_node(left);

    String left_type = util::get_type_node(left, self.scope, self.path);

    foreach (_case : node.cases)
    {
        CaseNode case_node = _case.node.case_node;
        ASTNode* right     = case_node.condition;
        self.analyse_node(right);

        String right_type = util::get_type_node(right, self.scope, self.path);

        if (left_type != right_type)
        {
            errors::print_node(self.path, *right, string::format(mem, "Expected type `%s`, got `%s`", left_type, right_type));
            os::exit(1);
        }

        foreach (child : case_node.children)
        {
            self.analyse_node(child, def);
        }
    }
}

fn void Sema.analyse_return(&self, ASTNode* node_in, ASTNode* def)
{
    ReturnNode node   = node_in.node.return_node;
    ASTNode*[] values = node.values;

    String def_type    = util::get_type_node(def, self.scope, self.path);
    String return_type = util::get_type_node(node_in, self.scope, self.path);

    if (def_type != return_type)
    {
        errors::print_node(self.path, *def.node.def_node.type, "Definition was here.");
        errors::print_node(self.path, *node_in, string::format(mem, "Expected type `%s`, got `%s`", def_type, return_type));
        os::exit(1);
    }
}

fn void Sema.analyse_macro(&self, ASTNode* node_in, ASTNode*[] arguments)
{
    MacroNode node = node_in.node.macro_node;

    bool is_vararg;
    int  min_param_len = node.parameters.len;
    foreach (i, parameter: node.parameters)
    {
        ParameterNode param = parameter.node.parameter_node;
        if (param.is_vararg)
        {
            if (i != node.parameters.len - 1)
            {
                errors::print_node(self.path, *parameter, "Variatric parameter must be last.");
                os::exit(1);
            }

            is_vararg = true;
            min_param_len = (int)i;
        }
    }

    HashMap{ String, ASTNode* } previous_parameters;
    foreach (parameter : node.parameters)
    {
        ParameterNode parameter_node = parameter.node.parameter_node;

        String name = parameter_node.name.node.ident_node.name;
        if (previous_parameters.has_key(name))
        {
            errors::print_node(self.path, *previous_parameters.get(name)!!, errors::ERROR_PREVIOUS);
            errors::print_node(self.path, *parameter, "A parameter with this name is already defined.");
            os::exit(1);
        }

        previous_parameters.set(name, parameter);
    }

    if (is_vararg)
    {
        if (arguments.len < min_param_len)
        {
            errors::print_node(self.path, *node.name, "Definition was here.");
            if (arguments.len != 0)
            {
                errors::print_node(self.path, *arguments[arguments.len - 1], "Expected more arguments after this one.");
            } else
            {
                errors::print_node(self.path, *node.name, "Expected arguments.");
            }
        
            os::exit(1);
        }

        String param_type;
        ASTNode* param;
        foreach (i, arg : arguments)
        {
            String arg_type = util::get_type_node(arg, self.scope, self.path);

            if (i < node.parameters.len)
            {
                param = node.parameters[i];
                param_type = util::get_type_node(param, self.scope, self.path);
            }

            if (!self.types.lookup(param_type))
            {
                io::printn(param_type);
                errors::print_node(self.path, *param, string::format(mem, "Could not find type `%s`", param_type));
                os::exit(1);
            }

            if (param_type == "void") continue;

            if (arg_type != param_type)
            {
                errors::print_node(self.path, *param, "Definition was here.");
                errors::print_node(self.path, *arg, string::format(mem, "Expected type `%s`, got `%s`", param_type, arg_type));
                os::exit(1);
            }
        }
    } else
    {
        if (arguments.len < min_param_len)
        {
            errors::print_node(self.path, *node.name, "Definition was here.");
            if (arguments.len != 0)
            {
                errors::print_node(self.path, *arguments[arguments.len - 1], "Expected more arguments after this one.");
            } else
            {
                errors::print_node(self.path, *node.name, "Expected arguments.");
            }
        
            os::exit(1);
        }

        if (arguments.len > min_param_len)
        {
            errors::print_node(self.path, *node.name, "Definition was here.");
            errors::print_node(self.path, *arguments[arguments.len - 1], "This argument would exceed the argument size.");
            os::exit(1);
        }

        foreach (i, param : node.parameters)
        {
            ASTNode* arg        = arguments[i];
            String   arg_type   = util::get_type_node(arg, self.scope, self.path);
            String   param_type = util::get_type_node(param, self.scope, self.path);

            if (!self.types.lookup(param_type))
            {
                io::printn(param_type);
                errors::print_node(self.path, *param, string::format(mem, "Could not find type `%s`", param_type));
                os::exit(1);
            }

            if (param_type == "void") continue;

            if (arg_type != param_type)
            {
                errors::print_node(self.path, *param, "Definition was here.");
                errors::print_node(self.path, *arg, string::format(mem, "Expected type `%s`, got `%s`", param_type, arg_type));
                os::exit(1);
            }
        }
    }

    self.scope = self.scope.new();
    foreach (i, parameter : node.parameters)
    {
        // TODO: varargs as array
        parameter.node.parameter_node.type.node.ident_node.name = util::get_type_node(arguments[i], self.scope, self.path);
        parameter.node.parameter_node.type.node_type = IDENT;
        self.analyse_node(parameter);
    }

    foreach (child : node.children)
    {
        self.analyse_node(child, node_in);
    }

    self.scope = self.scope.parent;
}

// TODO: analyse expression, check types
fn void Sema.analyse_reassign(&self, ASTNode* node_in)
{
    ReassignNode node = node_in.node.reassign_node;
    String       name = node.name.node.ident_node.name;

    if (!self.scope.has_var(name))
    {
        errors::print_node(self.path, *node.name, string::format(mem, "Unable to find variable `%s`", name));
        os::exit(1);
    }

    self.analyse_node(node.value);

    String var_type = self.scope.get_var(name).type;
    String val_type = util::get_type_node(node.value, self.scope, self.path);

    if (var_type != val_type)
    {
        errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`", var_type, val_type));
        os::exit(1);
    }
}
