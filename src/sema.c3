module lucy::sema;


import lucy::scope, lucy::node, lucy::types, lucy::util, lucy::errors, lucy::lexer, lucy::parser, lucy::attributes;
import std::os, std::collections::map, std::io;
import llvm;

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
    self.scope.functions.set(name, { type_name, node_in, null, null });
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

    self.scope.functions.set(name, { self.get_type_node(node_in), node_in, null, null });
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
    
    self.scope.constants.set(name, { type_name, node_in, null, null });
}

fn void Sema.register_struct(&self, ASTNode* node_in)
{
    StructNode node = node_in.node.struct_node;
    String     name = node.name.node.ident_node.name;
    
    if (self.types.lookup(name))
    {
        errors::print_node(self.path, *node.name, "A Type with this name already exists.");
        os::exit(1);
    }

    self.types.insert_type(name, null, null);
    
    self.scope.structs.set(name, { node_in, null });
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

    foreach (attribute : node.attributes)
    {
        AttributeNode attribute_node = attribute.node.attribute_node;
        if (attribute_node.name == "@variatric" && !util::is_variatric(node.parameters))
        {
            errors::print_node(self.path, *attribute, "Can only use attribute @variatric in combination with a vararg.");
            os::exit(1);
        }
    }

    self.scope.functions.set(name, { node.type.node.ident_node.name, node_in, null, null });
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

    foreach (attribute : node.attributes)
    {
        AttributeNode attribute_node = attribute.node.attribute_node;
        if (attribute_node.name == "@variatric" && !util::is_variatric(node.parameters))
        {
            errors::print_node(self.path, *attribute, "Can only use attribute @variatric in combination with a vararg.");
            os::exit(1);
        }
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

    Field* fields = malloc(Field.sizeof * (node.fields.len + types::BUILTIN_TYPE_FIELD_COUNT));
    foreach (i, field : node.fields)
    {
        FieldNode field_node = field.node.field_node;
        String    type_name  = field_node.type.node.ident_node.name;
        String    field_name = field_node.name.node.ident_node.name;

        ((Field[])fields[:node.fields.len])[i] = { field_name.zstr_copy(mem), self.types.lookup(type_name) };
    }

    self.types.append_builtin_type_fields(fields, node.fields.len);
    self.types.lookup(name).fields = fields;
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
    if (type != self.get_type_node(node.value))
    {
        errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", type, self.get_type_node(node.value)));
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

    self.scope.parameters.set(name, { type_name, node_in, null, null });
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
            String[] possible_types = self.get_possible_types(node.value.node.init_node);

            if (!util::in(possible_types, type_name))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`.", type_name));
                os::exit(1);
            }
        } else if (node.value.node_type != NULL)
        {
            self.analyse_node(node.value);
            
            if (type_name != self.get_type_node(node.value))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", type_name, self.get_type_node(node.value)));
                os::exit(1);
            }
        }

        self.scope.variables.set(name, { type_name, node_in, null, null });
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
            
            if (self.get_type_node(node.type) != self.get_type_node(node.value))
            {
                errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`.", self.get_type_node(node.type), self.get_type_node(node.value)));
                os::exit(1);
            }
        }

        foreach (i, name : node.names)
        {
            String name_value = name.node.ident_node.name;
            String type       = type_node.values[i].node.ident_node.name;
            self.scope.variables.set(name_value, { type, node_in, null, null });
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
    if (def.node.node_type == DEF ||
        def.node.node_type == EXT)
    {
        ASTNode*[] parameters;
        ASTNode*   name_node;
        ASTNode*[] attributes;
        if (def.node.node_type == DEF)
        {
            parameters = def.node.node.def_node.parameters;
            name_node  = def.node.node.def_node.name;
            attributes = def.node.node.def_node.attributes;
        } else
        {
            parameters = def.node.node.ext_node.parameters;
            name_node  = def.node.node.ext_node.name;
            attributes = def.node.node.ext_node.attributes;
        }

        foreach (arg : node.arguments)
        {
            self.analyse_node(arg);
        }

        foreach (attribute : attributes)
        {
            AttributeNode attribute_node = attribute.node.attribute_node;
            if (attribute_node.name == "@variatric" && !util::is_variatric(parameters))
            {
                errors::print_node(self.path, *attribute, "Can only use attribute @variatric in combination with a vararg.");
                os::exit(1);
            }

            attributes::inspect_call(attribute_node.name, node, self.path);
        }

        bool is_vararg;
        int  min_param_len = parameters.len;
        foreach (int i, parameter : parameters)
        {
            ParameterNode param = parameter.node.parameter_node;
            if (param.is_vararg)
            {
                if (i != parameters.len - 1)
                {
                    errors::print_node(self.path, *parameter, "Variatric parameter must be last.");
                    os::exit(1);
                }

                is_vararg = true;
                min_param_len = i;
            }
        }
        
        if (is_vararg)
        {
            if (node.arguments.len < min_param_len)
            {
                errors::print_node(self.path, *node.name, "Definition was here.");
                if (node.arguments.len != 0)
                {
                    errors::print_node(self.path, *node.arguments[node.arguments.len - 1], "Expected more arguments after this one.");
                } else
                {
                    errors::print_node(self.path, *node.name, "Expected arguments.");
                }
        
                os::exit(1);
            }

            String param_type;
            ASTNode* param;
            foreach (i, arg : node.arguments)
            {
                String arg_type = self.get_type_node(arg);

                if (i < parameters.len)
                {
                    param = parameters[i];
                    param_type = self.get_type_node(param);
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
            if (node.arguments.len < min_param_len)
            {
                errors::print_node(self.path, *node.name, "Definition was here.");
                if (node.arguments.len != 0)
                {
                    errors::print_node(self.path, *node.arguments[node.arguments.len - 1], "Expected more arguments after this one.");
                } else
                {
                    errors::print_node(self.path, *node.name, "Expected arguments.");
                }
        
                os::exit(1);
            }

            if (node.arguments.len > min_param_len)
            {
                errors::print_node(self.path, *def.node, "Definition was here.");
                errors::print_node(self.path, *node.arguments[node.arguments.len - 1], "This argument would exceed the argument size.");
                os::exit(1);
            }

            foreach (i, param : parameters)
            {
                ASTNode* arg        = node.arguments[i];
                String   arg_type   = self.get_type_node(arg);
                String   param_type = self.get_type_node(param);

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
    } else
    {
        self.analyse_macro(def.node, node.arguments);
    }

    foreach (arg : node.arguments)
    {
        self.analyse_node(arg);
    }
}

fn void Sema.analyse_unary(&self, ASTNode* node_in)
{
    UnaryNode node       = node_in.node.unary_node;
    String    value_type = self.get_type_node(node.expr);

    if (!self.types.lookup(value_type))
    {
        errors::print_node(self.path, *node.expr, string::format(mem, "Could not find type `%s`", value_type));
        os::exit(1);
    }

    String[] number_types = { "int", "float", "double" };

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
    
    if (self.types.lookup(ident.name))
    {
        type = self.types.lookup(ident.name);
    }

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

                Def def = pkg.scope.get_def(call_name);
                if (def.node.node_type == DEF)
                {
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
                        String   arg_type   = self.get_type_node(arg);
                        String   param_type = self.get_type_node(param);

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
                } else
                {
                    // TODO: macro call
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
                if (!prev_type.get_field(ident_name))
                {
                    errors::print_node(self.path, *next_node, string::format(mem, "Could not find property `%s` on type `%s`.", ident_name, prev_type.name));
                    os::exit(1);
                }
            case ACCESS:
                AccessNode access_node = next_node.node.access_node;
                IdentNode  ident_node  = access_node.expr.node.ident_node;
                String     field_name  = ident_node.name;
                Field*     field       = prev_type.get_field(field_name);
                if (!field)
                {
                    // TODO: error
                    errors::print_node(self.path, *access_node.expr, string::format(mem, "Could not find field `%s` on type `%s`.", field_name, prev_name));
                    os::exit(1);
                }

                self.resolve_access(field.type, field_name, access_node.expr, access_node.next);
            case INC:
                IncNode   inc_node     = next_node.node.inc_node;
                IdentNode ident_node   = inc_node.identifier.node.ident_node;
                String    ident_name   = ident_node.name;
                String    operator     = inc_node.operator;
                String    type         = prev_type.get_field(ident_name).type.name.str_view();

                switch (operator)
                {
                    case "+":
                    case "-":
                        if (type != "int")
                        {
                            errors::print_node(self.path, *next_node, string::format(mem, "Unsupported incremental operation for type `%s`", type));
                            os::exit(1);
                        }
                    case "!":
                        if (type != "bool")
                        {
                            errors::print_node(self.path, *next_node, string::format(mem, "Unsupported incremental operation for type `%s`", type));
                            os::exit(1);
                        }
                }
            default:
                util::panicf("Unsupported node type in access chain: `%s`", next_node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
        }
    }
}

fn void Sema.analyse_while(&self, ASTNode* node_in, ASTNode* def)
{
    WhileNode node = node_in.node.while_node;

    self.analyse_node(node.condition);

    if (self.get_type_node(node.condition) != "bool")
    {
        errors::print_node(self.path, *node.condition, string::format(mem, "Condition cannot be of type `%s`.", self.get_type_node(node.condition)));
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

    String left_type  = self.get_type_node(node.left);
    String right_type = self.get_type_node(node.right);

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

    String type = self.get_type_node(node.identifier);

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

    String left_type = self.get_type_node(left);

    foreach (_case : node.cases)
    {
        CaseNode case_node = _case.node.case_node;
        ASTNode* right     = case_node.condition;
        self.analyse_node(right);

        String right_type = self.get_type_node(right);

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

    String def_type    = self.get_type_node(def);
    String return_type = self.get_type_node(node_in);

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

    foreach (arg : arguments)
    {
        self.analyse_node(arg);
    }

    bool is_vararg;
    int  min_param_len = node.parameters.len;
    foreach (int i, parameter: node.parameters)
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
            min_param_len = i;
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
            String arg_type = self.get_type_node(arg);

            if (i < node.parameters.len)
            {
                param = node.parameters[i];
                param_type = self.get_type_node(param);
            }

            if (!self.types.lookup(param_type))
            {
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
            String   arg_type   = self.get_type_node(arg);
            String   param_type = self.get_type_node(param);

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
        parameter.node.parameter_node.type.node.ident_node.name = self.get_type_node(arguments[i]);
        parameter.node.parameter_node.type.node_type = IDENT;
        self.analyse_node(parameter);
    }

    foreach (child : node.children)
    {
        self.analyse_node(child, node_in);
    }

    self.scope = self.scope.parent;
}

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
    String val_type = self.get_type_node(node.value);

    if (var_type != val_type)
    {
        errors::print_node(self.path, *node.value, string::format(mem, "Expected type `%s`, got `%s`", var_type, val_type));
        os::exit(1);
    }
}

// --- TYPES ---

fn String Sema.get_type_node(&self, ASTNode* node)
{
    switch (node.node_type)
    {
        case INT:       return "int";
        case DEF:       return self.get_type_node_def(node);
        case STR:       return "str";
        case BIN:       return self.get_type_node_bin(node);
        case CALL:      return self.get_type_node_call(node);
        case BOOL:      return "bool";
        case CHAR:      return "char";
        case INIT:      return self.get_type_node_init(node);
        case TUPLE:     return self.get_type_node_tuple(node);
        case FLOAT:     return "float";
        case UNARY:     return self.get_type_node(node.node.unary_node.expr);
        case IDENT:     return self.get_type_node_ident(node);
        case MACRO:     return self.get_type_node_macro(node);
        case DOUBLE:    return "double";
        case RETURN:    return self.get_type_node_return(node);
        case ACCESS:    return self.get_type_node_access(node);
        case PARAMETER: return self.get_type_node_parameter(node);
        
        default: util::panicf("Missing case for type `%s`", node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
    }
}

fn String Sema.get_type_node_tuple(&self, ASTNode* node)
{
    String[] types;
    foreach (type : node.node.tuple_node.values)
    {
        util::array_insert(&types, type.node.ident_node.name);
    }

    DString out;

    out.append_char('(');
    out.append_chars(util::join_to_string(types, ", "));
    out.append_char(')');

    return out.copy_str(mem);
}

fn String Sema.get_type_node_call(&self, ASTNode* node)
{
    CallNode call_node = node.node.call_node;
    String   name      = call_node.name.node.ident_node.name;
    return self.scope.get_def(name).type;
}

fn String Sema.get_type_node_def(&self, ASTNode* node)
{
    DefNode def_node = node.node.def_node;
    if (def_node.type.node_type == IDENT)
    {
        return def_node.type.node.ident_node.name;
    } else
    {
        return self.get_type_node_tuple(def_node.type);
    }
}

fn String Sema.get_type_node_parameter(&self, ASTNode* node)
{
    ParameterNode parameter_node = node.node.parameter_node;

    if (parameter_node.type.node_type == NULL) return "void";

    return parameter_node.type.node.ident_node.name;
}

fn String Sema.get_type_node_ident(&self, ASTNode* node)
{
    String name = node.node.ident_node.name;
    return self.scope.get(name).get_type();
}

fn String Sema.get_type_node_bin(&self, ASTNode* node)
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
            return self.get_type_node(bin_node.left);
    }
    
    util::panicf("Missing case for operator `%s`", operator, file: $$FILE, line: $$LINE, function: $$FUNC);
}

fn String Sema.get_type_node_return(&self, ASTNode* node)
{
    ReturnNode return_node = node.node.return_node;
    ASTNode*[] values      = return_node.values;

    if (values.len == 0) return "void";

    if (values.len > 1)
    {
        String[] types;
        foreach (value : values)
        {
            util::array_insert(&types, self.get_type_node(value));
        }

        DString out;

        out.append_char('(');
        out.append_chars(util::join_to_string(types, ", "));
        out.append_char(')');

        return out.copy_str(mem);
    } else
    {
        return self.get_type_node(values[0]);
    }
}

fn String Sema.get_type_node_init(&self, ASTNode* node)
{
    InitNode init_node      = node.node.init_node;
    String[] possible_types = self.get_possible_types(init_node);

    if (possible_types.len > 1)
    {
        errors::print_node(self.path, *node, string::format(mem, "Multiple matching types found: `%s`", util::join_to_string(possible_types, ", ")));
        os::exit(1);
    }

    if (possible_types.len == 0)
    {
        errors::print_node(self.path, *node, "Could not find type with those properties.");
        os::exit(1);
    }

    return possible_types[0];
}

fn String[] Sema.get_possible_types(&self, InitNode init_node)
{
    String[] possible_types;

    bool named;
    foreach (i, value : init_node.values)
    {
        InitValueNode value_node = value.node.init_value_node;
        if (i == 0) named = !util::is_null(value_node.name);
        
        if (named && util::is_null(value_node.name) || !named && !util::is_null(value_node.name))
        {
            errors::print_node(self.path, *value, "Cannot mix named and unnamed initialization.");
            os::exit(1);
        }
    }

    if (named)
    {
        foreach (type : self.scope.get_all_structs())
        {
            bool all_names_match = true;

            HashMap{ String, ASTNode* } previous_names;
            foreach (value : init_node.values)
            {
                InitValueNode init_value = value.node.init_value_node;
                String        name       = init_value.name.node.ident_node.name;

                if (previous_names.has_key(name))
                {
                    errors::print_node(self.path, *previous_names.get(name)!!, errors::ERROR_PREVIOUS);
                    errors::print_node(self.path, *value, "A field with this name has already been initialized.");
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
                    String type_name  = self.get_type_node(value.node.init_value_node.value);
                    String field_type = util::get_field_by_name(value.node.init_value_node.name.node.ident_node.name, type).node.field_node.type.node.ident_node.name;

                    if (type_name != field_type)
                    {
                        errors::print_node(self.path, *value, string::format(mem, "Expected type `%s`, got `%s`", field_type, type_name));
                        os::exit(1);
                    }
                }

                util::array_insert(&possible_types, type.name.node.ident_node.name);
            }
        }
    } else
    {
        foreach (type : self.scope.get_all_structs())
        {
            if (type.fields.len != init_node.values.len) continue;
            
            bool types_match = true;
            foreach FIELDS: (i, field : type.fields)
            {
                String field_type = field.node.field_node.type.node.ident_node.name;
                String value_type = self.get_type_node(init_node.values[i].node.init_value_node.value);

                if (field_type != value_type)
                {
                    types_match = false;
                    break FIELDS;
                }
            }

            if (types_match)
            {
                util::array_insert(&possible_types, type.name.node.ident_node.name);
            }
        }
    }

    return possible_types;
}

fn String Sema.get_type_node_access(&self, ASTNode* node)
{
    AccessNode access_node = node.node.access_node;
    IdentNode  ident       = access_node.expr.node.ident_node;

    String  type_name;
    Type*   type      = null;

    if (self.types.lookup(ident.name))
    {
        type = self.types.lookup(ident.name);
    } else if (self.scope.has(ident.name))
    {
        type_name = self.scope.get(ident.name).get_type();
        type      = self.types.lookup(type_name);
    }

    return self.resolve_type_node_access(type, ident.name, access_node.expr, access_node.next);
}

fn String Sema.resolve_type_node_access(&self, Type* prev_type, String prev_name, ASTNode* prev_node, ASTNode* next_node)
{
    if (!prev_type)
    {
        String[] pkg_names;
        self.get_all_pkg_names(&pkg_names);
        String[] possible_pkgs = util::get_possible_pkgs(pkg_names, prev_name);

        String pkg_name  = possible_pkgs[0];
        Sema*  pkg       = self.get_pkg(pkg_name);
        switch (next_node.node_type)
        {
            case IDENT:
                IdentNode ident_node = next_node.node.ident_node;
                String    ident_name = ident_node.name;

                return pkg.scope.get_const(ident_name).type;
            case CALL:
                CallNode call_node = next_node.node.call_node;
                String   call_name = call_node.name.node.ident_node.name;
                Def      def       = pkg.scope.get_def(call_name);

                return def.type;
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

                return prev_type.get_field(ident_name).type.name.str_view();
            case ACCESS:
                AccessNode access_node = next_node.node.access_node;
                IdentNode  ident_node  = access_node.expr.node.ident_node;
                String     field_name  = ident_node.name;
                Field*     field       = prev_type.get_field(field_name);

                return self.resolve_type_node_access(field.type, field_name, access_node.expr, access_node.next);
            case INC:
                IncNode   inc_node   = next_node.node.inc_node;
                IdentNode ident_node = inc_node.identifier.node.ident_node;
                String    field_name = ident_node.name;
                Field*    field      = prev_type.get_field(field_name);

                return field.type.name.str_view();
            default:
                util::panicf("Unsupported node type in access chain: `%s`", next_node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
        }
    }
}

fn String Sema.get_type_node_macro(&self, ASTNode* node)
{
    MacroNode macro_node = node.node.macro_node;
    if (macro_node.type.node_type == IDENT)
    {
        return macro_node.type.node.ident_node.name;
    } else
    {
        return self.get_type_node_tuple(macro_node.type);
    }
}
