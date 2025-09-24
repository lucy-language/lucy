module lucy::generator::llvm_gen;

import lucy::scope, lucy::types, lucy::node, lucy::lexer, lucy::parser, lucy::sema, lucy::util, lucy::errors;
import std::collections::map, std::io::file, std::os, std::math;
import llvm;

struct LLVMGenerator
{
    Scope*                            scope;
    TypeTable*                        types;
    String[]                          linked_files;
    ASTNode*                          ast;
    bool                              emit;
    HashMap{ String, LLVMGenerator* } packages;
    LLVMModuleRef                     mod;
    String                            path;
    String                            pkg_name;
    LLVMBuilderRef                    builder;
    String[]                          links;
}

fn bool           LLVMGenerator.has_pkg(&self, String name) => self.packages.has_key(name);
fn LLVMGenerator* LLVMGenerator.get_pkg(&self, String name) => self.packages.get(name)!!;

fn void LLVMGenerator.get_all_pkg_names(&self, String[]* pkgs)
{
    foreach (pkg : self.packages.keys(mem))
    {
        util::array_insert(pkgs, pkg);
    }
}

fn LLVMGenerator new(TypeTable* types, String[] linked_pkgs, ASTNode* ast, bool emit, String path)
{
    String         pkg     = util::stringify_path(ast.node.file_node.pkg.node.pkg_node.path);
    LLVMModuleRef  mod     = llvm::module_create_with_name((CChar*)pkg);
    Scope*         scope   = scope::new();
    LLVMBuilderRef builder = llvm::create_builder();

    return
    {
        scope,
        types,
        linked_pkgs,
        ast,
        emit,
        {},
        mod,
        path,
        pkg,
        builder,
        {}
    };
}

fn void LLVMGenerator.generate(&self)
{
    foreach (link : self.ast.node.file_node.links)
    {
        self.register_link(link);
    }

    foreach (statement : self.ast.node.file_node.statements)
    {
        self.register_node(statement);
    }

    foreach (link : self.linked_files)
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
            Sema   sema  = sema::new(link, scope, self.types, self.linked_files, ast);
            sema.analyse();
            
            LLVMGenerator gen = llvm_gen::new(self.types, self.linked_files, ast, self.emit, link);
            gen.generate();

            LLVMGenerator* gen_ptr = malloc(LLVMGenerator.sizeof);
            *gen_ptr = gen;

            self.packages.set(pkg, gen_ptr);
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
        self.generate_node(statement, null);
    }

    if (self.emit)
    {
        CChar* error    = null;
        String filename = self.path.replace(mem, ".lc", ".ll");
        llvm::print_module_to_file(self.mod, (CChar*)filename, &error);

        if (error) io::eprintn((ZString)error);
    }

    llvm::dispose_builder(self.builder);
}

fn void LLVMGenerator.register_node(&self, ASTNode* node)
{
    switch (node.node_type)
    {
        case EXT:    self.register_ext(node);
        case DEF:    self.register_def(node);
        // case USE:    self.register_use(node);
        case CONST:  self.register_const(node);
        case MACRO:  self.register_macro(node);
        case STRUCT: self.register_struct(node);

        default: break;
    }
}

fn void LLVMGenerator.register_link(&self, ASTNode* node_in)
{
    LinkNode  node  = node_in.node.link_node;
    IdentNode ident = node.name.node.ident_node;
    String    name  = ident.name;

    util::array_insert(&self.links, name);
}

fn void LLVMGenerator.register_ext(&self, ASTNode* node_in)
{
    ExtNode    node       = node_in.node.ext_node;
    String     name       = node.name.node.ident_node.name;
    String     type_name  = node.type.node.ident_node.name;
    ASTNode*[] parameters = node.parameters;
    int        param_len  = parameters.len;

    LLVMTypeRef   return_type = self.types.lookup(type_name).llvm_type;
    LLVMTypeRef[] param_types = mem::new_array(LLVMTypeRef, param_len);

    LLVMBool is_var_arg = llvm::FALSE;
    foreach (i, parameter : parameters)
    {
        ParameterNode param_node      = parameter.node.parameter_node;
        String        param_type_name = param_node.type.node.ident_node.name;

        if (param_node.is_vararg)
        {
            is_var_arg = llvm::TRUE;
            param_len--;

            if (i == param_types.len - 1) break;
        }

        param_types[i] = self.types.lookup(param_type_name).llvm_type;
    }

    LLVMTypeRef  func_type = llvm::function_type(return_type, param_types, param_len, is_var_arg);
    LLVMValueRef func      = llvm::add_function(self.mod, (CChar*)name, func_type);

    if (!util::is_null(node.aka)) name = node.aka.node.ident_node.name;

    self.scope.functions.set(name, { type_name, node_in, func, func_type });
}

fn void LLVMGenerator.register_def(&self, ASTNode* node_in)
{
    DefNode    node       = node_in.node.def_node;
    String     name       = node.name.node.ident_node.name;
    ASTNode*[] parameters = node.parameters;
    int        param_len  = parameters.len;

    String      type_name = self.get_type_node(node_in);
    LLVMTypeRef return_type;
    if (type_name.contains(","))
    {
        String[]      type_arr   = type_name.split(mem, ",");
        LLVMTypeRef[] llvm_types = mem::new_array(LLVMTypeRef, type_arr.len);
        foreach (i, type : type_arr)
        {
            llvm_types[i] = self.types.lookup(type).llvm_type;
        }

        return_type = llvm::struct_type(llvm_types, llvm_types.len, llvm::FALSE);
    } else
    {
        return_type = self.types.lookup(type_name).llvm_type;
    }

    if (name == "main" && type_name != "int")
    {
        return_type = self.types.lookup("int").llvm_type;
    }

    LLVMTypeRef[] param_types = mem::new_array(LLVMTypeRef, param_len);

    LLVMBool is_var_arg = llvm::FALSE;
    foreach (i, parameter : parameters)
    {
        ParameterNode param_node      = parameter.node.parameter_node;
        String        param_type_name = param_node.type.node.ident_node.name;

        if (param_node.is_vararg)
        {
            is_var_arg = llvm::TRUE;
            param_len--;

            if (i == param_types.len - 1) break;
        }

        param_types[i] = self.types.lookup(param_type_name).llvm_type;
    }

    String func_name = string::format(mem, "%s.%s", self.pkg_name, name);

    LLVMTypeRef  func_type = llvm::function_type(return_type, param_types, param_len, is_var_arg);
    LLVMValueRef func      = llvm::add_function(self.mod, (CChar*)func_name, func_type);

    foreach (uint i, param_type : param_types)
    {
        llvm::set_value_name(llvm::get_param(func, i), (CChar*)parameters[i].node.parameter_node.name.node.ident_node.name);
    }

    self.scope.functions.set(name, { type_name, node_in, func, func_type });
}

fn void LLVMGenerator.register_struct(&self, ASTNode* node_in)
{
    StructNode node   = node_in.node.struct_node;
    String     name   = node.name.node.ident_node.name;
    ASTNode*[] fields = node.fields;

    String struct_name = string::format(mem, "%s.%s", self.pkg_name, name);

    LLVMContextRef context     = llvm::get_global_context();
    LLVMTypeRef    struct_type = llvm::struct_create_named(context, (CChar*)struct_name);

    self.types.lookup(name).llvm_type  = struct_type;
    self.types.lookup(name).num_fields = fields.len;
    self.scope.structs.set(name, { node_in, struct_type });
}

fn void LLVMGenerator.register_const(&self, ASTNode* node_in)
{
    ConstNode node      = node_in.node.const_node;
    String    name      = node.name.node.ident_node.name;
    String    type_name = node.type.node.ident_node.name;

    LLVMValueRef const_value;
    switch (type_name)
    {
        case "str":
            String value = node.value.node.str_node.value;
            const_value  = llvm::const_string((CChar*)value, value.len, llvm::FALSE);
        case "int":
            int value   = node.value.node.int_node.value.to_int()!!;
            const_value = llvm::const_int(self.types.lookup(type_name).llvm_type, value, llvm::TRUE);
        case "char":
            char value  = node.value.node.char_node.value.to_ichar()!!;
            const_value = llvm::const_int(self.types.lookup(type_name).llvm_type, value, llvm::TRUE);
        case "bool":
            LLVMBool value = node.value.node.bool_node.value == "true" ? llvm::TRUE : llvm::FALSE;
            const_value    = llvm::const_int(self.types.lookup(type_name).llvm_type, value, llvm::TRUE);
        case "float":
            float value = node.value.node.float_node.value.to_float()!!;
            const_value = llvm::const_real(self.types.lookup(type_name).llvm_type, value);
        case "double":
            double value = node.value.node.double_node.value.to_double()!!;
            const_value  = llvm::const_real(self.types.lookup(type_name).llvm_type, value);
    }

    String const_name = string::format(mem, "%s.%s", self.pkg_name, name);

    LLVMTypeRef  llvm_type  = self.types.lookup(type_name).llvm_type;
    LLVMValueRef llvm_const = llvm::add_global(self.mod, llvm_type, (CChar*)const_name);
    llvm::set_initializer(llvm_const, const_value);

    self.scope.constants.set(name, { type_name, node_in, llvm_const, llvm_type });
}

fn void LLVMGenerator.register_macro(&self, ASTNode* node_in)
{
    MacroNode  node      = node_in.node.macro_node;
    String     name      = node.name.node.ident_node.name;
    String     type_name = self.get_type_node(node_in);

    self.scope.functions.set(name, { type_name, node_in, null, null });
}

// --- Generation ---

fn LLVMValueRef LLVMGenerator.generate_node(&self, ASTNode* node, LLVMBasicBlockRef current_block)
{
    switch (node.node_type)
    {
        case DEF:           self.generate_def(node);
        case INT:    return self.generate_int(node);
        case STR:    return self.generate_str(node);
        case USE:    break; // TODO
        case VAR:           self.generate_var(node, current_block);
        case BOOL:   return self.generate_bool(node);
        case CALL:   return self.generate_call(node, current_block);
        case CHAR:   return self.generate_char(node);
        case INIT:   return self.generate_init(node);
        case FLOAT:  return self.generate_float(node);
        case IDENT:  return self.generate_ident(node);
        case ACCESS: return self.generate_access(node);
        case DOUBLE: return self.generate_double(node);
        case STRUCT:        self.generate_struct(node);
        case RETURN: return self.generate_return(node, current_block);

        case EXT:
        case NULL:
        case CONST:
        case MACRO:
            break;
        default:
            // break;
            util::panicf("Missing llvm-generator function for type `%s`", node.node_type, file: $$FILE, line: $$LINE, function: $$FUNC);
    }

    return null;
}

fn void LLVMGenerator.generate_struct(&self, ASTNode* node_in)
{
    StructNode node       = node_in.node.struct_node;
    String     name       = node.name.node.ident_node.name;
    ASTNode*[] fields     = node.fields;
    int        fields_len = fields.len;

    LLVMTypeRef[] field_types = mem::new_array(LLVMTypeRef, fields_len);
    foreach (i, field : fields)
    {
        FieldNode field_node = field.node.field_node;
        String    type_name  = field_node.type.node.ident_node.name;

        field_types[i] = self.types.lookup(type_name).llvm_type;
    }

    LLVMTypeRef struct_type = self.scope.get_struct(name).llvm_type;
    llvm::struct_set_body(struct_type, field_types, fields_len, llvm::FALSE);
}

fn void LLVMGenerator.generate_def(&self, ASTNode* node_in)
{
    DefNode node = node_in.node.def_node;
    String  name = node.name.node.ident_node.name;
    
    Def          def       = self.scope.get_def(name);
    LLVMValueRef llvm_func = def.llvm_value;

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(llvm_func, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    self.scope = self.scope.new();
    foreach (uint i, param : node.parameters)
    {
        ParameterNode param_node = param.node.parameter_node;
        String        param_name = param_node.name.node.ident_node.name;
        String        param_type = param_node.type.node.ident_node.name;
        self.scope.parameters.set(param_name, { param_type, param, llvm::get_param(llvm_func, i), self.types.lookup(param_type).llvm_type });
    }

    foreach (child : node.children)
    {
        self.generate_node(child, entry_block);
    }
    self.scope = self.scope.parent;

    // TODO: check if return already present
    if (name == "main" && def.type == "void") llvm::build_ret(self.builder, llvm::const_int(self.types.lookup("int").llvm_type, 0, llvm::TRUE));
    if (name != "main" && def.type == "void") llvm::build_ret_void(self.builder);
}

fn void LLVMGenerator.generate_var(&self, ASTNode* node_in, LLVMBasicBlockRef current_block)
{
    VarNode node = node_in.node.var_node;

    if (node.type.node_type == IDENT)
    {
        String      name      = node.names[0].node.ident_node.name;
        String      type_name = node.type.node.ident_node.name;
        LLVMTypeRef llvm_type = self.types.lookup(type_name).llvm_type;

        LLVMValueRef llvm_value = llvm::build_alloca(self.builder, llvm_type, (CChar*)name);

        if (node.value.node_type != NULL)
        {
            LLVMValueRef value = self.generate_node(node.value, current_block);
            llvm::build_store(self.builder, value, llvm_value);
        }

        self.scope.variables.set(name, { type_name, node_in, llvm_value, llvm_type });
    } else
    {
        LLVMValueRef value       = self.generate_node(node.value, current_block);
        String[] type_names = self.get_type_node(node.type).split(mem, ",");
        foreach (uint i, name_node : node.names)
        {
            String       name        = name_node.node.ident_node.name;
            String       type_name   = type_names[i];
            LLVMTypeRef  llvm_type   = self.types.lookup(type_name).llvm_type;
            LLVMValueRef llvm_value  = llvm::build_alloca(self.builder, llvm_type, (CChar*)name);
            LLVMTypeRef  value_type  = llvm::type_of(value);
            int          field_count = llvm::count_struct_element_types(value_type);

            // TODO: deal with some values maybe being null due to named initialization
            LLVMValueRef field      = llvm::build_extract_value(self.builder, value, i, "");
            LLVMTypeRef  field_type = llvm::struct_get_type_at_index(value_type, i);

            llvm::build_store(self.builder, field, llvm_value);

            self.scope.variables.set(name, { type_name, node_in, llvm_value, llvm_type });
        }
    }
}

fn LLVMValueRef LLVMGenerator.generate_init(&self, ASTNode* node_in)
{
    InitNode node = node_in.node.init_node;
    
    // TODO: if named fields - get field index from struct
    return null;
}

// TODO: add `generate_call`

fn LLVMValueRef LLVMGenerator.generate_double(&self, ASTNode* node_in)
{
    DoubleNode node  = node_in.node.double_node;
    double     value = node.value.to_double()!!;
    return llvm::const_real(self.types.lookup("double").llvm_type, value);
}

fn LLVMValueRef LLVMGenerator.generate_float(&self, ASTNode* node_in)
{
    FloatNode node  = node_in.node.float_node;
    float     value = node.value.to_float()!!;
    return llvm::const_real(self.types.lookup("float").llvm_type, value);
}

fn LLVMValueRef LLVMGenerator.generate_bool(&self, ASTNode* node_in)
{
    BoolNode node  = node_in.node.bool_node;
    LLVMBool value = node.value == "true" ? llvm::TRUE : llvm::FALSE;
    return llvm::const_int(self.types.lookup("bool").llvm_type, value, llvm::FALSE);
}

fn LLVMValueRef LLVMGenerator.generate_str(&self, ASTNode* node_in)
{
    StrNode node  = node_in.node.str_node;
    String  value = node.value;
    return self.create_string(value);
}

fn LLVMValueRef LLVMGenerator.generate_int(&self, ASTNode* node_in)
{
    IntNode node  = node_in.node.int_node;
    int     value = node.value.to_int()!!;
    return llvm::const_int(self.types.lookup("int").llvm_type, value, llvm::TRUE);
}

fn LLVMValueRef LLVMGenerator.generate_char(&self, ASTNode* node_in)
{
    // TODO: figure out base
    CharNode node  = node_in.node.char_node;
    char     value = node.value.to_ichar(base: 8)!!;
    return llvm::const_int(self.types.lookup("char").llvm_type, value, llvm::TRUE);
}

fn LLVMValueRef LLVMGenerator.generate_call(&self, ASTNode* node_in, LLVMBasicBlockRef current_block)
{
    CallNode   node     = node_in.node.call_node;
    String     name     = node.name.node.ident_node.name;
    ASTNode*[] args     = node.arguments;
    int        args_len = args.len;

    Def          def        = self.scope.get_def(name);
    LLVMTypeRef  llvm_type  = def.llvm_type;
    LLVMValueRef llvm_value = def.llvm_value;

    if (def.node.node_type == MACRO)
    {
        LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, args_len);
        foreach (i, arg : args)
        {
            llvm_args[i] = self.generate_node(arg, current_block);
        }

        return self.generate_macro(def.node, node, current_block);
    } else
    {
        LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, args_len);
        foreach (i, arg : args)
        {
            llvm_args[i] = self.generate_node(arg, current_block);
        }

        return llvm::build_call_2(self.builder, llvm_type, llvm_value, llvm_args, args_len, "");
    }
}

fn LLVMValueRef LLVMGenerator.generate_ident(&self, ASTNode* node_in)
{
    IdentNode    node       = node_in.node.ident_node;
    String       name       = node.name;
    ScopeResult  scope_res  = self.scope.get(name);
    LLVMValueRef llvm_value = scope_res.get_llvm_value();
    LLVMTypeRef  llvm_type  = scope_res.get_llvm_type();

    switch (scope_res.type)
    {
        case VAR:   return llvm::build_load_2(self.builder, llvm_type, llvm_value, ".tmp");
        case PARAM: return llvm_value;
        case CONST:
            if (scope_res.get_type() == "str") return llvm_value;
            return llvm::build_load_2(self.builder, llvm_type, llvm_value, ".tmp");
    }
}

fn LLVMValueRef LLVMGenerator.generate_access(&self, ASTNode* node_in)
{
    AccessNode node  = node_in.node.access_node;
    IdentNode  ident = node.expr.node.ident_node; // assume it's ident for now since call on expression is still unsupported e.g. "Test".$length

    String       type_name;
    LLVMValueRef llvm_value;
    LLVMTypeRef  llvm_type;
    Type*        type = null;
    
    if (self.types.lookup(ident.name))
    {
        type = self.types.lookup(ident.name);
    }

    if (self.scope.has(ident.name))
    {
        ScopeResult scope_result = self.scope.get(ident.name);
        
        type_name  = scope_result.get_type();
        type       = self.types.lookup(type_name);
        llvm_value = scope_result.get_llvm_value();
        llvm_type  = scope_result.get_llvm_type();
    }

    return self.resolve_access(type, llvm_value, llvm_type, ident.name, node.next);
}

fn LLVMValueRef LLVMGenerator.resolve_access(&self, Type* prev_type, LLVMValueRef llvm_value, LLVMTypeRef llvm_type, String prev_name, ASTNode* next_node)
{
    if (!prev_type) {} // TODO: handle imports
    else
    {
        switch (next_node.node_type)
        {
            case IDENT:
                IdentNode ident_node = next_node.node.ident_node;
                String    ident_name = ident_node.name;
                Field*    field      = prev_type.get_field(ident_name);

                if (!llvm_value) return self.resolve_type_access(prev_type, ident_name); // NOTE: handles calls on types e.g. `str.$size`
                
                // if (ident_name.starts_with("$")) return self.resolve_builtin_field(prev_type, name); // NOTE: handle builtin fields e.g. `foo.$size`
                // NOTE: something with `llvm::struct_gep(ty, i)`
                // TODO: handle builtins e.g. `$size`
                // NOTE: use field index to get from struct
            default: util::panic("FUCK", $$FILE, $$LINE, $$FUNC);
        }
    }

    return null;
}

fn LLVMValueRef LLVMGenerator.resolve_type_access(&self, Type* type, String field_name)
{
    switch (field_name)
    {
        case "$size":      return self.create_int("int", self.resolve_type_size(type));
        case "$typeid":    return self.create_int("int", type.type_id);
        case "$typename":  return self.create_string(type.name.str_view().copy(mem));
        case "$typekind":  return self.create_string(llvm::get_type_kind(type.llvm_type) == llvm::STRUCTTYPEKIND ? "STRUCT" : "BUILTIN");
        case "$numfields": return self.create_int("int", type.num_fields);
    }

    return null;
}

fn LLVMValueRef LLVMGenerator.resolve_builtin_field(&self, Type* type, String name)
{
    
    return null;
}

fn LLVMValueRef LLVMGenerator.generate_macro(&self, ASTNode* node_in, CallNode call_node, LLVMBasicBlockRef current_block)
{
    MacroNode  node       = node_in.node.macro_node;
    String     name       = node.name.node.ident_node.name;
    ASTNode*[] parameters = node.parameters;
    int        param_len  = parameters.len;

    String      type_name = self.get_type_node(node_in);
    LLVMTypeRef return_type;
    if (type_name.contains(","))
    {
        String[]      type_arr   = type_name.split(mem, ",");
        LLVMTypeRef[] llvm_types = mem::new_array(LLVMTypeRef, type_arr.len);
        foreach (i, type : type_arr)
        {
            llvm_types[i] = self.types.lookup(type).llvm_type;
        }

        return_type = llvm::struct_type(llvm_types, llvm_types.len, llvm::FALSE);
    } else
    {
        return_type = self.types.lookup(type_name).llvm_type;
    }

    LLVMTypeRef[] param_types = mem::new_array(LLVMTypeRef, param_len);

    LLVMBool is_var_arg = llvm::FALSE;
    foreach (i, parameter : parameters)
    {
        ParameterNode param_node      = parameter.node.parameter_node;
        String        param_type_name = self.get_type_node(call_node.arguments[i]);

        if (param_node.is_vararg)
        {
            is_var_arg = llvm::TRUE;
            param_len--;

            if (i == param_types.len - 1) break;
        }

        param_types[i] = self.types.lookup(param_type_name).llvm_type;
    }

    String func_name = string::format(mem, "%s.%s", self.pkg_name, name);

    LLVMTypeRef  func_type = llvm::function_type(return_type, param_types, param_len, is_var_arg);
    LLVMValueRef func      = llvm::add_function(self.mod, (CChar*)func_name, func_type);

    foreach (uint i, param_type : param_types)
    {
        llvm::set_value_name(llvm::get_param(func, i), (CChar*)parameters[i].node.parameter_node.name.node.ident_node.name);
    }

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(func, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    self.scope = self.scope.new();
    foreach (uint i, param : node.parameters)
    {
        ParameterNode param_node = param.node.parameter_node;
        String        param_name = param_node.name.node.ident_node.name;
        String        param_type = param_node.type.node.ident_node.name;
        self.scope.parameters.set(param_name, { param_type, param, llvm::get_param(func, i), self.types.lookup(param_type).llvm_type });
    }

    foreach (child : node.children)
    {
        self.generate_node(child, entry_block);
    }
    self.scope = self.scope.parent;

    int args_len = call_node.arguments.len;

    LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, args_len);
    foreach (i, arg : call_node.arguments)
    {
        llvm_args[i] = self.generate_node(arg, entry_block);
    }

    if (type_name == "void") llvm::build_ret_void(self.builder);

    llvm::position_builder_at_end(self.builder, current_block);
    return llvm::build_call_2(self.builder, func_type, func, llvm_args, args_len, "");
}

fn LLVMValueRef LLVMGenerator.generate_return(&self, ASTNode* node_in, LLVMBasicBlockRef current_block)
{
    ReturnNode node       = node_in.node.return_node;
    ASTNode*[] values     = node.values;
    int        values_len = values.len;

    if (values_len > 1)
    {
        LLVMValueRef[] llvm_values = mem::new_array(LLVMValueRef, values_len);
        foreach(i, value : values)
        {
            llvm_values[i] = self.generate_node(value, current_block);
        }

        LLVMValueRef llvm_value = llvm::const_struct((LLVMValueRef*)llvm_values, values_len, llvm::FALSE);
        
        return llvm::build_ret(self.builder, llvm_value);
    }

    return llvm::build_ret(self.builder, self.generate_node(values[0], current_block));
}

// --- UTIL ---

fn LLVMValueRef LLVMGenerator.create_string(&self, String value)
{
    LLVMValueRef llvm_value  = llvm::const_string((CChar*)value, value.len, llvm::FALSE);
    LLVMTypeRef  llvm_type   = llvm::array_type(self.types.lookup("char").llvm_type, value.len + 1);
    LLVMValueRef llvm_global = llvm::add_global(self.mod, llvm_type, ".str");
    llvm::set_initializer(llvm_global, llvm_value);

    return llvm_global;
}

macro LLVMValueRef LLVMGenerator.create_int(&self, type, int value)
{
    LLVMTypeRef int_type = self.types.lookup(type).llvm_type;

    return llvm::const_int(int_type, value, llvm::TRUE);
}

fn int LLVMGenerator.resolve_type_size(&self, Type* type)
{
    String type_name = type.name.str_view().copy(mem);

    switch (type_name)
    {
        case "str":    return 8;
        case "int":    return 4;
        case "char":   return 1;
        case "bool":   return 1;
        case "float":  return 4;
        case "double": return 8;
    }

    int max_alignment  = 1;
    int current_offset = 0;

    for (int i = 0; i < type.num_fields; i++)
    {
        Field* field           = &type.fields[i];
        int    field_alignment = self.resolve_type_alignment(field.type);

        max_alignment = math::max(max_alignment, field_alignment);
    }

    for (int i = 0; i < type.num_fields; i++)
    {
        Field* field           = &type.fields[i];
        int    field_alignment = self.resolve_type_alignment(field.type);
        int    padding         = (field_alignment - (current_offset % field_alignment)) % field_alignment;

        current_offset += padding;

        int field_size = self.resolve_type_size(field.type);

        current_offset += field_size;
    }

    int final_padding = (max_alignment - (current_offset % max_alignment)) % max_alignment;

    return current_offset + final_padding;
}

fn int LLVMGenerator.resolve_type_alignment(&self, Type* type)
{
    String type_name = type.name.str_view().copy(mem);

    switch (type_name)
    {
        case "str":    return 8;
        case "int":    return 4;
        case "char":   return 1;
        case "bool":   return 1;
        case "float":  return 4;
        case "double": return 8;
    }

    int max_alignment = 1;
    for (int i = 0; i < type.num_fields; i++)
    {
        Field* field  = &type.fields[i];
        max_alignment = math::max(max_alignment, self.resolve_type_alignment(field.type));
    }

    return max_alignment;
}

// --- TYPES ---

fn String LLVMGenerator.get_type_node(&self, ASTNode* node)
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

fn String LLVMGenerator.get_type_node_tuple(&self, ASTNode* node)
{
    String[] types;
    foreach (type : node.node.tuple_node.values)
    {
        util::array_insert(&types, type.node.ident_node.name);
    }

    return util::join_to_string(types, ",");
}

fn String LLVMGenerator.get_type_node_call(&self, ASTNode* node)
{
    CallNode call_node = node.node.call_node;
    String   name      = call_node.name.node.ident_node.name;
    return self.scope.get_def(name).type;
}

fn String LLVMGenerator.get_type_node_def(&self, ASTNode* node)
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

fn String LLVMGenerator.get_type_node_parameter(&self, ASTNode* node)
{
    ParameterNode parameter_node = node.node.parameter_node;

    if (parameter_node.type.node_type == NULL) return "void";

    return parameter_node.type.node.ident_node.name;
}

fn String LLVMGenerator.get_type_node_ident(&self, ASTNode* node)
{
    String name = node.node.ident_node.name;
    return self.scope.get(name).get_type();
}

fn String LLVMGenerator.get_type_node_bin(&self, ASTNode* node)
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

fn String LLVMGenerator.get_type_node_return(&self, ASTNode* node)
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

fn String LLVMGenerator.get_type_node_init(&self, ASTNode* node)
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

fn String[] LLVMGenerator.get_possible_types(&self, InitNode init_node)
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

fn String LLVMGenerator.get_type_node_access(&self, ASTNode* node)
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

fn String LLVMGenerator.resolve_type_node_access(&self, Type* prev_type, String prev_name, ASTNode* prev_node, ASTNode* next_node)
{
    if (!prev_type)
    {
        String[] pkg_names;
        self.get_all_pkg_names(&pkg_names);
        String[] possible_pkgs = util::get_possible_pkgs(pkg_names, prev_name);

        String         pkg_name = possible_pkgs[0];
        LLVMGenerator* pkg      = self.get_pkg(pkg_name);
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

fn String LLVMGenerator.get_type_node_macro(&self, ASTNode* node)
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
