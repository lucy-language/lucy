module lucy::compiler;

import std::collections::map, std::collections::list, std::os, std::io;
import lucy::node, lucy::errors, lucy::scope::comp, lucy::util, lucy::lookup_table, lucy::linker, lucy::semantic_analyser, lucy::parser, lucy::lexer;
import llvm;

extern fn int strcmp(char* s1, char* s2);

faultdef INVALID_TYPE;

struct Compiler
{
    FileNode                      file_node;
    String                        module_name;
    String                        file_path;
    LLVMModuleRef                 mod;
    LLVMBuilderRef                builder;
    LLVMContextRef                context;
    HashMap{String, Def}          functions;
    HashMap{String, Struct}       structs;
    Scope*                        scope;
    int                           index;
    LLVMValueRef                  true_ptr;
    LLVMValueRef                  false_ptr;
    LLVMValueRef                  strcmp;
    LLVMTypeRef                   strcmp_type;
    LLVMValueRef                  strlen;
    LLVMTypeRef                   strlen_type;
    LLVMValueRef                  strcon;
    LLVMTypeRef                   strcon_type;
    TypeTable*                    type_table;
    HashMap{String, LLVMValueRef} strings;
    String[]                      imports;
    String[]                      linker_options;
    HashMap{String, Compiler}     linked_modules;
}

struct Def
{
    ExtNode*     ext_node;
    MacroNode*   node;
    LLVMValueRef function;
    LLVMTypeRef  type;
    String       ret_type;
}

struct Struct
{
    String      name;
    LLVMTypeRef type;
    FieldNode[] fields;
}

fn Compiler new(String file_path, ASTNode file, TypeTable* type_table)
{
    String mod_name        = file.node.file_node.module_name;
    LLVMModuleRef mod      = llvm::module_create_with_name(mod_name);
    LLVMBuilderRef builder = llvm::create_builder();
    LLVMContextRef context = llvm::context_create();
    Scope* scope           = malloc(Scope.sizeof);
    (*scope).parent        = null;
    (*scope).variables     = {};
    (*scope).constants     = {};

    return
    {
        .file_node   = file.node.file_node,
        .module_name = mod_name,
        .file_path   = file_path,
        .mod         = mod,
        .builder     = builder,
        .context     = context,
        .scope       = scope,
        .type_table  = type_table,
        .strcmp      = null,
        .strcmp_type = null,
        .strlen      = null,
        .strlen_type = null
    };
}

fn void Compiler.compile(&self, String[] links = {})
{
    // compile linked lc files
    foreach (link_path : links)
    {
        String   content  = (String)file::load(mem, link_path)!!;
        Lexer    lexer    = lexer::new(content);
        Parser   parser   = parser::new(lexer, link_path);

        ASTNode ast = parser.parse();
        TypeTable* type_table = malloc(TypeTable.sizeof);
        (*type_table).init();
        SemanticAnalyser semantic_analyser = semantic_analyser::new(link_path, ast, type_table);
        semantic_analyser.analyse();

        parser = parser::new(lexer, link_path);
        Compiler compiler = compiler::new(link_path, parser.parse(), type_table);
        compiler.compile();

        
        foreach (name : compiler.functions.keys(mem))
        {
            Def def = compiler.functions.get(name)!!;
            if (def.ext_node)
            {
                self.compile_ext(*def.ext_node);
            }
        }
        

        self.linked_modules.set(compiler.module_name, compiler);
        self.linker_options = array::concat(mem, self.linker_options, compiler.linker_options);
    }

    // register functions first so they can be found even if declared later than call
    foreach (child : self.file_node.children)
    {
        switch (child.node_type)
        {
            case EXT:    self.compile_ext(child.node.ext_node);
            case DEF:    self.add_def(child.node.def_node);
            case MACRO:  self.add_macro(child.node.macro_node);
            case STRUCT: self.add_struct(child.node.struct_node);
            default: break;
        }
    }
    
    defer llvm::dispose_builder(self.builder);
    foreach (ast : self.file_node.children)
    {
        self.compile_node(ast);
    }

    foreach (mod : self.linked_modules.values(mem))
    {
        llvm::link_modules_2(self.mod, mod.mod);
    }

    foreach (child : self.file_node.linker_options)
    {
        util::array_insert(&self.linker_options, string::format(mem, "-l%s", child.node.linker_option_node.value));
    }
}

fn void Compiler.add_def(&self, DefNode node)
{
    LLVMTypeRef type = self.get_type(node.types);
    if (node.name == "main" && node.types[0] == "void")
    {
        type = self.get_type((String[]){"int"});
    }

    List{LLVMTypeRef} param_list;
    bool vararg;

    foreach (parameter : node.parameters)
    {
        ParameterNode param = parameter.node.parameter_node;

        if (param.vararg)
        {
            vararg = true;
            break;
        }
        param_list.push(self.get_type((String[]){param.type}));
    }

    LLVMTypeRef[] parameters = mem::new_array(LLVMTypeRef, param_list.len());

    for (int i = 0; i < param_list.len(); i++)
    {
        parameters[i] = param_list.get(i);
    }

    String new_name = string::format(mem, "%s.%s", self.module_name, node.name);

    LLVMTypeRef fn_type = llvm::function_type(type, parameters, parameters.len, vararg ? llvm::TRUE : llvm::FALSE);
    LLVMValueRef fN = llvm::add_function(self.mod, new_name, fn_type);

    for (int i = 0; i < parameters.len; i++) {
        llvm::set_value_name(llvm::get_param(fN, i), (node.parameters)[i].node.parameter_node.name);
    }

    self.functions.set(node.name, { null, null, fN, fn_type, node.types[0] });
}

fn void Compiler.add_macro(&self, MacroNode node)
{
    MacroNode* node_ptr = malloc(MacroNode.sizeof);
    *node_ptr = node;
    self.functions.set(node.name, { null, node_ptr, null, null, node.type });
}

fn void Compiler.add_struct(&self, StructNode node)
{
    LLVMTypeRef struct_type = llvm::struct_create_named(self.context, node.name);
    FieldNode[] fields = mem::new_array(FieldNode, node.fields.len);
    foreach (i, field : node.fields)
    {
        fields[i] = field.node.field_node;
    }

    self.structs.set(node.name, { node.name, struct_type, fields });
}

fn LLVMValueRef Compiler.compile_node(&self, ASTNode ast, LLVMValueRef fN = null, LLVMTypeRef type = null, LLVMBasicBlockRef parent_block = null)
{
    switch (ast.node_type)
    {
        case DEF:               self.compile_def(ast.node.def_node);
        case RETURN:            self.compile_return(ast.node.return_node);
        //case EXT:               self.compile_ext(ast.node.ext_node);
        case CONST:             self.compile_const(ast.node.const_node);
        case GLOBAL:            self.compile_global(ast.node.global_node);
        case VAR:               self.compile_var(ast.node.var_node);
        case REASSIGN:          self.compile_reassign(ast.node.reassign_node);
        case STR:        return self.compile_str(ast.node.str_node);
        case INT:        return self.compile_int(ast.node.int_node);
        case CHAR:       return self.compile_char(ast.node.char_node);
        case BOOL:       return self.compile_bool(ast.node.bool_node);
        case FLOAT:      return self.compile_float(ast.node.float_node);
        case DOUBLE:     return self.compile_double(ast.node.double_node);
        case CALL:       return self.compile_call(ast.node.call_node, parent_block);
        case IDENT:      return self.compile_ident(ast);
        case IF:                self.compile_if(ast.node.if_node, fN);
        case BIN:        return self.compile_bin(ast.node.bin_node);
        case INIT:       return self.compile_init(ast.node.init_node, type);
        case INIT_VALUE: return self.compile_node(*ast.node.init_value_node.value);
        case ACCESS:     return self.compile_access(ast.node.access_node, parent_block);
        case STRUCT:            self.compile_struct(ast.node.struct_node);
        case WHILE:             self.compile_while(ast.node.while_node, fN);
        case UNARY:      return self.compile_unary(ast.node.unary_node);
        case SWITCH:            self.compile_switch(ast.node.switch_node, fN, parent_block);
        case INC:        return self.compile_inc(ast.node.inc_node);
        case FOR:               self.compile_for(ast.node.for_node, fN);
        case USE:               self.compile_use(ast.node.use_node);

        case EXT:
        case MACRO: break;

        default: util::panic(string::tformat("Missing compile function `%s`", ast.node_type), $$FILE, $$LINE);
    }
    return null;
}

fn void Compiler.compile_def(&self, DefNode node)
{
    Def def = self.functions.get(node.name)!!;
    LLVMValueRef function = def.function;

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(function, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    self.scope = (*self.scope).new();
    foreach (index, parameter : node.parameters)
    {
        ParameterNode param = parameter.node.parameter_node;
        LLVMValueRef llvm_param = llvm::get_param(function, index);
        (*self.scope).parameters.set(param.name, { param.type, llvm_param });
    }

    foreach (child : node.children)
    {
        self.compile_node(child, function, parent_block: entry_block);
    }

    if (node.children.len == 0 || (node.children[node.children.len - 1].node_type != RETURN && def.ret_type == "void"))
    {
        if (node.name == "main")
        {
            llvm::build_ret(self.builder, create_int(0));
        } else
        {
            llvm::build_ret_void(self.builder);
        }
    }

    self.scope = (*self.scope).parent;
}

fn void Compiler.compile_return(&self, ReturnNode node)
{
    ASTNode[] values = node.values;
    if (values.len == 0)
    {
        llvm::build_ret_void(self.builder);
    } else if (values.len == 1)
    {
        llvm::build_ret(self.builder, self.compile_node(values[0]));
    } else
    {
        LLVMValueRef[] llvm_values = mem::new_array(LLVMValueRef, values.len);
        for (int i = 0; i < llvm_values.len; i++)
        {
            llvm_values[i] = self.compile_node(values[i]);
        }

        llvm::build_ret(self.builder, llvm::const_struct(llvm_values, values.len, llvm::FALSE));
    }
}

fn void Compiler.compile_ext(&self, ExtNode node)
{
    LLVMTypeRef type = self.get_type((String[]){ node.type });

    bool vararg;
    foreach (param : node.parameters)
    {
        if (param.node.parameter_node.vararg)
        {
            vararg = true;
            break;
        }
    }

    usz size = vararg ? node.parameters.len - 1 : node.parameters.len;
    LLVMTypeRef[] llvm_param_types = mem::new_array(LLVMTypeRef, size);
    for (int i = 0; i < size; i++)
    {
        ParameterNode param = node.parameters[i].node.parameter_node;
        llvm_param_types[i] = self.get_type((String[]){ param.type });
    }

    LLVMTypeRef fn_type = llvm::function_type(type, llvm_param_types, llvm_param_types.len, vararg ? llvm::TRUE : llvm::FALSE);
    LLVMValueRef fN = llvm::add_function(self.mod, node.name, fn_type);

    String name = node.alias_name != "" ? node.alias_name : node.name;
    ExtNode* ext_node = malloc(ExtNode.sizeof);
    *ext_node = node;

    self.functions.set(name, { ext_node, null, fN, fn_type, node.type });
}

fn void Compiler.compile_const(&self, ConstNode node, bool global = false)
{
    
    LLVMValueRef value;

    switch (node.type)
    {
        case "bool": value = llvm::const_int(llvm::int1_type(), node.value.node.bool_node.value == "true" ? llvm::TRUE : llvm::FALSE, llvm::FALSE);
        case "char": value = llvm::const_int(llvm::int8_type(), node.value.node.char_node.value.to_uchar(), llvm::TRUE)!!;
        case "int": value = llvm::const_int(llvm::int32_type(), node.value.node.int_node.value.to_int(), llvm::TRUE)!!; // TODO: return llvm::int64_type() if on 64 bit system
        case "float": value = llvm::const_real(llvm::float_type(), node.value.node.float_node.value.to_float())!!;
        case "double": value = llvm::const_real(llvm::double_type(), node.value.node.double_node.value.to_double())!!;
        case "str": value = llvm::const_string(node.value.node.str_node.value, node.value.node.str_node.value.len, llvm::FALSE);
        default: util::panic("A constant can only be a builtin type", $$FILE, $$LINE);
    }
    LLVMValueRef constant = llvm::add_global(self.mod, llvm::type_of(value), node.name);

    llvm::set_initializer(constant, value);
    llvm::set_linkage(constant, global ? EXTERNAL_LINKAGE : PRIVATE_LINKAGE);
    llvm::set_global_constant(constant, llvm::TRUE);
    llvm::set_unnamed_addr(constant, llvm::TRUE);

    (*self.scope).constants.set(node.name, { node.type, constant });
}

fn LLVMTypeRef Compiler.get_type(&self, String[] types)
{
    if (types.len == 1)
    {
        String type = types[0];
        if (type != "" && type[type.len - 1] == '*')
        {
            return llvm::pointer_type(self.get_type((String[]){type[..type.len - 2]}), 0);
        }
        // TODO: return array_type/ptr
//        String type = types[0];
//        char   last = type[type.len - 1];
//        while (util::in((char[]){'*', ']'}, last))
//        {
//            while (last == '*')
//            {
//                type = type[..type.len - 2];
//                last    = type[type.len - 1];
//            }
//
//            while (last == ']')
//            {
//                type = type[..type.len - 2];
//                last    = type[type.len - 1];
//                while (last != '[')
//                {
//                    type = type[..type.len - 2];
//                    last    = type[type.len - 1];
//                }
//                type = type[..type.len - 2];
//            }
//        }

        switch (type)
        {
            case "bool": return llvm::int1_type();
            case "char": return llvm::int8_type();
            case "int": return llvm::int32_type(); // TODO: return llvm::int64_type() if on 64 bit system
            case "float": return llvm::float_type();
            case "double": return llvm::double_type();
            case "void": return llvm::void_type();
            case "str": return llvm::pointer_type(llvm::int8_type(), 0);
            // struct
            default:
                if (!self.structs.has_key(type)) util::panic(string::tformat("Type `%s` could not be matched", type), $$FILE, $$LINE);
                return self.structs.get(type)!!.type;
        }
    } else
    {
        LLVMTypeRef[] llvm_types = mem::new_array(LLVMTypeRef, types.len);
        for (int i = 0; i < llvm_types.len; i++)
        {
            llvm_types[i] = self.get_type((String[]){ types[i] });
        }

        return llvm::struct_type(llvm_types, llvm_types.len, llvm::FALSE);
    }
}

fn void Compiler.compile_global(&self, GlobalNode node)
{
    switch (node.node.node_type)
    {
        case DEF: break; // TODO
        case EXT: break; // TODO
        case CONST: self.compile_const(node.node[0].node.const_node, true);
        default: break; // TODO: show error
    }
}

fn void Compiler.compile_var(&self, VarNode node)
{
    if (node.names.len == 1)
    {
        LLVMTypeRef type = self.get_type(node.types);
        if (llvm::get_type_kind(self.get_type(node.types)) == STRUCT_TYPE_KIND)
        {
            type = self.structs.get(node.types[0])!!.type;
        }
        
        LLVMValueRef variable = llvm::build_alloca(self.builder, type, node.names[0]);
        if (node.value != null)
        {
            LLVMValueRef value = self.compile_node(*node.value, type: type);
            llvm::build_store(self.builder, value, variable);
        }

        self.scope.variables.set(node.names[0], { node.types[0], variable });
        return;
    }

    LLVMValueRef value = self.compile_node(*node.value);
    LLVMTypeRef valueType = llvm::type_of(value);

    if (llvm::get_type_kind(valueType) == STRUCT_TYPE_KIND)
    {
        usz num_fields = llvm::count_struct_element_types(valueType);
        for (int i = 0; i < num_fields; ++i)
        {
            LLVMValueRef field = llvm::build_extract_value(self.builder, value, i, "");
            LLVMTypeRef fieldType = llvm::struct_get_type_at_index(valueType, i);
            String name = node.names[i];

            LLVMValueRef variable = llvm::build_alloca(self.builder, fieldType, name);
            llvm::build_store(self.builder, field, variable);

            self.scope.variables.set(node.names[i], { node.types[i], variable });
        }
    }
}

fn void Compiler.compile_reassign(&self, ReassignNode node)
{
    String name = node.name;
    Var variable = (*self.scope).get_var(name);
    
    LLVMValueRef value = self.compile_node(*node.value);

    llvm::build_store(self.builder, value, variable.value);
}

fn LLVMValueRef Compiler.compile_str(&self, StrNode node)
{
    String value = node.value;
    
    return self.create_string(value);
}

fn LLVMValueRef Compiler.compile_int(&self, IntNode node)
{
    int value = (int)node.value.to_uint()!!;
    LLVMTypeRef type = llvm::int32_type(); // TODO: return llvm::int64_type() if on 64 bit system

    return llvm::const_int(type, value, llvm::FALSE);
}

fn LLVMValueRef Compiler.compile_bool(&self, BoolNode node)
{
    /*
    String value = node.value;
    if (value == "true")
    {
        if (self.true_ptr != null)
        {
            return self.true_ptr;
        }
    } else
    {
        if (self.false_ptr != null)
        {
            return self.false_ptr;
        }
    }

    LLVMValueRef str = llvm::const_string(value, value.len, llvm::FALSE);
    LLVMTypeRef arr_type = llvm::array_type(llvm::int8_type(), value.len + 1);
    LLVMValueRef global = llvm::add_global(self.mod, arr_type, value);
    llvm::set_initializer(global, str);
    llvm::set_linkage(global, PRIVATE_LINKAGE);
    llvm::set_unnamed_addr(global, llvm::TRUE);
    llvm::set_global_constant(global, llvm::TRUE);

    if (value == "true")
    {
        self.true_ptr = global;
    } else
    {
        self.false_ptr = global;
    }

    return global;
    */
    return llvm::const_int(llvm::int1_type(), node.value == "true" ? 1 : 0, 0);
}

fn LLVMValueRef Compiler.compile_char(&self, CharNode node)
{
    char value = node.value[0];
    if (value == '\\')
    {
        value = node.value[1];
    }

    return llvm::const_int(llvm::int8_type(), value, llvm::FALSE);
}

fn LLVMValueRef Compiler.compile_call(&self, CallNode node, LLVMBasicBlockRef parent_block)
{
    Def def = self.functions.get(node.name)!!;

    LLVMValueRef function      = def.function;
    LLVMTypeRef  function_type = def.type;
    String[]     arg_types     = mem::new_array(String, node.arguments.len);

    LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, node.arguments.len);
    for (int i = 0; i < node.arguments.len; ++i) {
        ASTNode arg_node = node.arguments[i];
    
        LLVMValueRef arg_value = self.compile_node(arg_node);

        arg_types[i] = self.get_type_from_llvm(arg_value);
        llvm_args[i] = arg_value;
    }

    if (def.node != null)
    {
        if (parent_block == null)
        {
            util::panic("Missing parent block for call", $$FILE, $$LINE);
        }

        self.compile_macro(def.node, llvm_args, arg_types, parent_block);
    }
    else
    {
        LLVMValueRef call = llvm::build_call_2(
            self.builder,
            function_type,
            function,
            llvm_args,
            llvm_args.len,
            ""
        );
        return call;
    }
    return null;
}

fn LLVMValueRef Compiler.compile_ident(&self, ASTNode node_in)
{
    IdentNode node = node_in.node.ident_node;
    String    name = node.name;

    switch (name)
    {
        case "$FILE": return self.create_string(self.file_path);
        case "$PATH": return self.create_string(self.file_path.to_absolute_path(mem)!!.str_view());
        case "$LINE": return llvm::const_int(self.get_type((String[]){"int"}), node_in.line, llvm::FALSE);
    }

    LLVMValueRef loaded;
    // TODO: replace with Scope.has and switch
    if ((self.scope).has_var(name))
    {
        Var variable = (*self.scope).get_var(name);
        LLVMTypeRef type = self.get_type((String[]){ variable.type });
        loaded = llvm::build_load_2(self.builder, type, variable.value, "");
    } else if ((*self.scope).has_const(name))
    {
        Const constant = (*self.scope).get_const(name);
        //LLVMTypeRef type = self.get_type((String[]){ constant.type });
        //loaded = llvm::build_load_2(self.builder, type, constant.value, "");
        return constant.value;
    } else if ((*self.scope).has_param(name))
    {
        loaded = (*self.scope).get_param(name).value;
    }

    return loaded;
}

fn String Compiler.process_escape_sequences(&self, String input)
{
    DString output;
    defer output.free();
    int i = 0;

    while (i < input.len) {
        if (input[i] == '\\' && i + 1 < input.len) {
            switch (input[i+1]) {
                case 'n':  output.append_char('\n'); break;
                case 't':  output.append_char('\t'); break;
                case 'r':  output.append_char('\r'); break;
                case '\\': output.append_char('\\'); break;
                case '"':  output.append_char('"'); break;
                case 'u':
                    if (i + 5 < input.len && input[i+2] == '0' && input[i+3] == '0' && input[i+4] == '1' && input[i+5] == 'B')
                    {
                        output.append_char('\x1B');
                        i += 6;
                        continue;
                    }
                default:   output.append_char(input[i+1]); break;
            }
            i += 2;
        } else {
            output.append_char(input[i]);
            i += 1;
        }
    }

    return output.copy_str(mem);
}

fn void Compiler.compile_if(&self, IfNode node, LLVMValueRef fN)
{
    LLVMValueRef condition = self.compile_node(*node.condition);

    int index = (*self).index++;

    // create first for reference to jump
    LLVMBasicBlockRef then_block = llvm::append_basic_block(fN, string::format(mem, "then.%d", index));
    LLVMBasicBlockRef else_block = llvm::append_basic_block(fN, string::format(mem, "else.%d", index));
    LLVMBasicBlockRef end_block  = llvm::append_basic_block(fN, string::format(mem, "end.%d", index));

    // evaluate condition
    llvm::build_cond_br(self.builder, condition, then_block, else_block);

    // evaluate then
    self.scope = (*self.scope).new();
    llvm::position_builder_at_end(self.builder, then_block);
    foreach (child : node.children)
    {
        self.compile_node(child);
    }
    llvm::build_br(self.builder, end_block);
    self.scope = (*self.scope).parent;

    llvm::position_builder_at_end(self.builder, else_block);
    if (node.else_if != null)
    {
        self.compile_node(*node.else_if, fN);
        llvm::build_br(self.builder, end_block);
    } else
    {
        // evaluate else
        self.scope = (*self.scope).new();
        foreach (child : node.else_children)
        {
            self.compile_node(child, fN);
        }
        llvm::build_br(self.builder, end_block);
        self.scope = (*self.scope).parent;
    }
    // continue code
    llvm::position_builder_at_end(self.builder, end_block);
}

fn LLVMValueRef Compiler.compile_bin(&self, BinNode node)
{
    if (node.op == "+" && node.left.node_type == STR && node.right.node_type == STR)
    {
        String  left_value  = node.left.node.str_node.value;
        String  right_value = node.right.node.str_node.value;
        DString result;
        result.init(mem);
        defer result.free();
        result.append_chars(left_value);
        result.append_chars(right_value);

        return self.create_string(result.copy_str(mem));
    }

    LLVMValueRef left  = self.compile_node(*node.left);
    LLVMValueRef right = self.compile_node(*node.right);
    
    LLVMTypeRef[] int_types =
    {
        llvm::int1_type(),
        llvm::int8_type(),
        llvm::int32_type(),
        llvm::int64_type()
    };

    LLVMTypeRef[] real_types =
    {
        llvm::double_type(),
        llvm::float_type()
    };

    // TODO: extend type checking
    // only need to check one side since sema rules out mismatch
    if (util::in(int_types, llvm::type_of(left)))
    {
        switch (node.op)
        {
            case "==": return llvm::build_i_cmp(self.builder, llvm::INT_EQ, left, right, "");
            case "!=": return llvm::build_i_cmp(self.builder, llvm::INT_NE, left, right, "");
            case ">=": return llvm::build_i_cmp(self.builder, llvm::INT_SGE, left, right, "");
            case "<=": return llvm::build_i_cmp(self.builder, llvm::INT_SLE, left, right, "");
            case ">":  return llvm::build_i_cmp(self.builder, llvm::INT_SGT, left, right, "");
            case "<":  return llvm::build_i_cmp(self.builder, llvm::INT_SLT, left, right, "");

            case "+": return llvm::build_add(self.builder, left, right, "");
            case "-": return llvm::build_sub(self.builder, left, right, "");
            case "*": return llvm::build_mul(self.builder, left, right, "");
            case "/": return llvm::build_s_div(self.builder, left, right, "");
        }
    } else if (util::in(real_types, llvm::type_of(left)))
    {
        switch (node.op)
        {
            case "==": return llvm::build_f_cmp(self.builder, llvm::REAL_OEQ, left, right, "");
            case "!=": return llvm::build_f_cmp(self.builder, llvm::REAL_ONE, left, right, "");
            case ">=": return llvm::build_f_cmp(self.builder, llvm::REAL_OGE, left, right, "");
            case "<=": return llvm::build_f_cmp(self.builder, llvm::REAL_OLE, left, right, "");
            case ">":  return llvm::build_f_cmp(self.builder, llvm::REAL_OGT, left, right, "");
            case "<":  return llvm::build_f_cmp(self.builder, llvm::REAL_OLT, left, right, "");
            
            case "+": return llvm::build_f_add(self.builder, left, right, "");
            case "-": return llvm::build_f_sub(self.builder, left, right, "");
            case "*": return llvm::build_f_mul(self.builder, left, right, "");
            case "/": return llvm::build_f_div(self.builder, left, right, "");
        }
    } else if (llvm::type_of(left) == llvm::pointer_type(llvm::int8_type(), 0))
    { // strings
        switch (node.op)
        {
            case "==":
                if (!self.strcmp) self.build_strcmp();
                LLVMValueRef[] args = { left, right, llvm::const_int(llvm::int1_type(), llvm::TRUE, llvm::FALSE) };
                return llvm::build_call_2(self.builder, self.strcmp_type, self.strcmp, args, 3, "");
            case "!=":
                if (!self.strcmp) self.build_strcmp();
                LLVMValueRef[] args = { left, right, llvm::const_int(llvm::int1_type(), llvm::FALSE, llvm::FALSE) };
                return llvm::build_call_2(self.builder, self.strcmp_type, self.strcmp, args, 3, "");
            case "+":
                if (!self.strcon) self.build_strcon();
                LLVMValueRef[] args = { left, right };
                return llvm::build_call_2(self.builder, self.strcon_type, self.strcon, args, 2, "");
        }
    }

    return null;
}

fn LLVMValueRef Compiler.compile_float(&self, FloatNode node)
{
    return llvm::const_real(llvm::double_type(), node.value.to_float())!!;
}

fn LLVMValueRef Compiler.compile_double(&self, DoubleNode node)
{
    return llvm::const_real(llvm::double_type(), node.value.to_double())!!;
}

fn LLVMValueRef Compiler.compile_init(&self, InitNode node, LLVMTypeRef type)
{
    LLVMValueRef[] values = mem::new_array(LLVMValueRef, node.values.len);
    bool all_const = true;

    foreach (i, value : node.values)
    {
        values[i] = self.compile_node(value);
        if (!llvm::is_constant(values[i]))
        {
            all_const = false;
        }
    }
    
    LLVMTypeRef struct_type = self.get_struct_type(node);

    if (all_const)
    {
        if (struct_type != null)
        {
            return llvm::const_named_struct(struct_type, values, values.len, 0);
        } else
        {
            return llvm::const_struct(values, values.len, 0);
        }
    } else
    {
        LLVMValueRef instance = llvm::build_alloca(self.builder, struct_type, "");
        foreach (i, value : values)
        {
            LLVMValueRef field_ptr = llvm::build_struct_gep_2(self.builder, struct_type, instance, (int)i, "");
            llvm::build_store(self.builder, value, field_ptr);
        }

        return instance;
    }
}

fn LLVMValueRef Compiler.compile_access(&self, AccessNode node, LLVMValueRef parent_block)
{
    String name = node.id;

    if (self.type_table.has((char*)name.zstr_copy(mem)))
    {
        Type* base_type = self.type_table.lookup(node.id);
        return self.resolve_access(null, base_type.llvm_type, name, node.node, parent_block);
    }

    LLVMValueRef struct_value;
    String       type_name = name;
    if ((self.scope).has_var(name))
    {
        Var variable = self.scope.get_var(name);
        struct_value = variable.value;
        type_name    = variable.type;
    } else if ((*self.scope).has_const(name))
    {
        Const constant = self.scope.get_const(name);
        struct_value   = constant.value;
        type_name      = constant.type;
    } else if ((*self.scope).has_param(name))
    {
        Param param  = self.scope.get_param(name);
        struct_value = param.value;
        type_name    = param.type;
    }
    
    LLVMTypeRef struct_type = null;
    if (self.scope.has(name)) struct_type = self.type_table.lookup(type_name).llvm_type;
    
    return self.resolve_access(struct_value, struct_type, type_name, node.node, parent_block);
}

// TODO: see sema
fn LLVMValueRef Compiler.resolve_access(&self, LLVMValueRef base_value, LLVMTypeRef base_type, char* prev_id, ASTNode* next_node, LLVMValueRef parent_block)
{
    if (!next_node) return base_value;

    switch (next_node.node_type)
    {
        case ACCESS:
            AccessNode access = next_node.node.access_node;
            char* field_name  = access.id.zstr_copy(mem);
            int num_fields    = llvm::count_struct_element_types(base_type);
            Type* type        = self.type_table.lookup(prev_id); // lookup type name
            for (int i = 0; i < num_fields; i++)
            {
                Field field = ((Field[])(*type).fields[:num_fields])[i];
                if (strcmp(field.name, field_name) == 0)
                {
                    LLVMValueRef field_ptr = llvm::build_struct_gep_2(self.builder, base_type, base_value, i, "");
                    LLVMValueRef loaded_value = llvm::build_load_2(self.builder, field.type.llvm_type, field_ptr, "");
                    
                    return self.resolve_access(field_ptr, field.type.llvm_type, field.type.name, access.node, parent_block);
                }
            }
        case IDENT:
            IdentNode ident  = next_node.node.ident_node;
            char* field_name = ident.name.zstr_copy(mem);
            int num_fields   = llvm::count_struct_element_types(base_type);
            Type* type       = self.type_table.lookup(prev_id); // lookup type name
            if (ident.name[0] == '$')
            {//detect early
                return self.resolve_builtin_field(base_value, base_type, prev_id, field_name);
            }

            for (int i = 0; i < num_fields; i++)
            {
                Field field = ((Field[])(*type).fields[:num_fields])[i];
                if (strcmp(field.name, field_name) == 0)
                {
                    if (((ZString)field_name)[0] == '$')
                    {
                        LLVMValueRef type_struct = llvm::build_load_2(self.builder, base_type, base_value, "");
                        return llvm::build_extract_value(self.builder, type_struct, i + 1, "");
                    }
                    LLVMValueRef field_ptr = llvm::build_struct_gep_2(self.builder, base_type, base_value, i, "");
                    LLVMValueRef loaded_value = llvm::build_load_2(self.builder, field.type.llvm_type, field_ptr, "");

                    return loaded_value;
                }
            }
            util::panic("Unreachable", $$FILE, $$LINE);
        case INC:
            IncNode inc      = next_node.node.inc_node;
            char* field_name = inc.name.zstr_copy(mem);
            int num_fields   = llvm::count_struct_element_types(base_type);
            Type* type       = self.type_table.lookup(prev_id); // lookup type name

            for (int i = 0; i < num_fields; i++)
            {
                Field field = ((Field[])(*type).fields[:num_fields])[i];
                if (strcmp(field.name, field_name) == 0)
                {
                    LLVMValueRef field_ptr = llvm::build_struct_gep_2(self.builder, base_type, base_value, i, "");
                    LLVMValueRef loaded_value = llvm::build_load_2(self.builder, field.type.llvm_type, field_ptr, "");
                    
                    switch (inc.operator)
                    {
                        case "+":
                            LLVMValueRef value = llvm::build_add(self.builder, loaded_value, create_int(1), "");
                            llvm::build_store(self.builder, value, field_ptr);
                            return loaded_value;
                        case "-":
                            LLVMValueRef value = llvm::build_sub(self.builder, loaded_value, create_int(1), "");
                            llvm::build_store(self.builder, value, field_ptr);
                            return loaded_value;
                        case "!":
                            LLVMValueRef value = llvm::build_not(self.builder, loaded_value, "");
                            llvm::build_store(self.builder, value, field_ptr);
                            return loaded_value;
                    }

                    return loaded_value;
                }
            }
            util::panic("Unreachable", $$FILE, $$LINE);
        case CALL:
            // TODO: filter if it's from a module or called on a type --- second one isn't possible yet
            CallNode call_node = next_node.node.call_node;
            String   mod_name  = util::all_ends(self.linked_modules.keys(mem), ((ZString)prev_id).str_view())[0];
            String   name      = string::format(mem, "%s.%s", mod_name, call_node.name);

            Compiler     linked_compiler = self.linked_modules.get(mod_name)!!;
            Def          def             = linked_compiler.functions.get(call_node.name)!!;
            LLVMValueRef function        = llvm::get_named_function(self.mod, name);
            String[]     arg_types       = mem::new_array(String, call_node.arguments.len);

            LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, call_node.arguments.len);
            for (int i = 0; i < call_node.arguments.len; ++i) {
                ASTNode arg_node = call_node.arguments[i];
    
                LLVMValueRef arg_value = self.compile_node(arg_node);

                arg_types[i] = self.get_type_from_llvm(arg_value);
                llvm_args[i] = arg_value;
            }

            if (def.node != null)
            {
                if (parent_block == null)
                {
                    util::panic("Missing parent block for call", $$FILE, $$LINE);
                }

                self.compile_macro(def.node, llvm_args, arg_types, parent_block);
            }
            else
            {
                return llvm::build_call_2(self.builder, def.type, function, llvm_args, llvm_args.len, "");
            }
        default:
            break;
    }
    return null;
}

fn void Compiler.compile_struct(&self, StructNode node)
{
    LLVMTypeRef[] fields = mem::new_array(LLVMTypeRef, node.fields.len);
    foreach(i, field : node.fields)
    {
        fields[i] = self.get_type((String[]){field.node.field_node.type});
    }
    
    LLVMTypeRef struct_type = self.structs.get(node.name)!!.type;
    llvm::struct_set_body(struct_type, fields, fields.len, llvm::FALSE);

    Type* type = self.type_table.lookup(node.name.zstr_copy(mem));
    (*type).llvm_type = struct_type;
}

fn LLVMValueRef Compiler.resolve_builtin_field(&self, LLVMValueRef value, LLVMTypeRef type, char* prev, char* id)
{
    switch (((ZString)id).str_view())
    {
        case "$typeid":
            return llvm::const_int(/* to get i32/i64 based on system */ self.get_type((String[]){"int"}), self.type_table.lookup(self.type_table.lookup(prev).name).type_id, llvm::FALSE);
        case "$typekind":
            String typekind;
            if (llvm::get_type_kind(type) == STRUCT_TYPE_KIND)
            {
                typekind = "STRUCT";
            } else
            {
                typekind = "BUILTIN";
            }

            return self.create_string(typekind);
        case "$typename":
            String typename = ((ZString)self.type_table.lookup(prev).name).str_view();
            return self.create_string(typename);
        case "$size":
            return self.calculate_type_size(type, prev);
        case "$numfields":
            Type* type_ptr = self.type_table.lookup(prev);
            return create_int(type_ptr.num_fields);
        case "$length":
            if (!self.strlen) self.build_strlen();
            LLVMValueRef[] args = { value };
            return llvm::build_call_2(self.builder, self.strlen_type, self.strlen, args, 1, "");
    }

    return null;
}

fn void Compiler.compile_macro(&self, MacroNode* node, LLVMValueRef[] args, String[] arg_types, LLVMBasicBlockRef parent_block)
{
    String[] types = mem::new_array(String, 1);
    types[0] = node.type;
    LLVMTypeRef type;
    if (node.type == "")
    {
        type = llvm::void_type();
    } else
    {
        type = self.get_type(types);
    }

    LLVMTypeRef[] params = mem::new_array(LLVMTypeRef, 0);
    bool vararg;

    foreach (i, parameter : node.parameters)
    {
        ParameterNode param = parameter.node.parameter_node;

        if (param.vararg)
        {
            vararg = true;
            break;
        }
        util::array_insert(&params, llvm::type_of(args[i]));
    }
    
    LLVMTypeRef fn_type = llvm::function_type(type, params, params.len, vararg ? llvm::TRUE : llvm::FALSE);
    
    LLVMValueRef fN = llvm::add_function(self.mod, node.name, fn_type);

    for (int i = 0; i < params.len; i++) {
        llvm::set_value_name(llvm::get_param(fN, i), (node.parameters)[i].node.parameter_node.name);
    }

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(fN, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    self.scope = (*self.scope).new();
    foreach (index, parameter : node.parameters)
    {
        ParameterNode param = parameter.node.parameter_node;
        LLVMValueRef llvm_param = llvm::get_param(fN, index);
        (*self.scope).parameters.set(param.name, { arg_types[index].copy(mem), llvm_param });
    }

    LLVMBasicBlockRef current_block = entry_block;
    foreach (child : node.children)
    {
        LLVMBasicBlockRef new_block = self.compile_node(child, fN, parent_block: current_block); // switch also gets this as parent rather than the end from if
        if (new_block)
        {
            current_block = new_block;
        }
    }

    NodeType last_child_type = node.children[node.children.len - 1].node_type;
    if (node.children.len == 0 || (last_child_type != RETURN && node.type == "void") || (node.type == "" && last_child_type != RETURN))
    {
        llvm::build_ret_void(self.builder);
    }

    self.scope = (*self.scope).parent;
    llvm::position_builder_at_end(self.builder, parent_block);
    llvm::build_call_2(
        self.builder,
        fn_type,
        fN,
        args,
        args.len,
        ""
    );
}

fn void Compiler.compile_while(&self, WhileNode node, LLVMValueRef fN)
{
    LLVMValueRef condition = self.compile_node(*node.condition);

    // create first for reference to jump
    LLVMBasicBlockRef then_block = llvm::append_basic_block(fN, "");
    LLVMBasicBlockRef end_block = llvm::append_basic_block(fN, "");

    // evaluate condition
    llvm::build_cond_br(self.builder, condition, then_block, end_block);

    // evaluate then
    self.scope = (*self.scope).new();
    llvm::position_builder_at_end(self.builder, then_block);
    foreach (child : node.children)
    {
        self.compile_node(child);
    }
    LLVMValueRef new_condition = self.compile_node(*node.condition);
    llvm::build_cond_br(self.builder, new_condition, then_block, end_block);
    self.scope = (*self.scope).parent;

    // continue code
    llvm::position_builder_at_end(self.builder, end_block);
}

fn LLVMValueRef Compiler.compile_unary(&self, UnaryNode node)
{
    LLVMValueRef expr = self.compile_node(*node.expr);
    
        switch (node.operator)
        {
            case "!":
                return llvm::build_i_cmp(self.builder, llvm::INT_EQ, expr, llvm::const_int(llvm::int1_type(), llvm::FALSE, llvm::FALSE), "");
            case "-":
                return llvm::build_mul(self.builder, expr, create_int(-1), "");
            case "+":
                LLVMValueRef condition = llvm::build_i_cmp(self.builder, llvm::INT_SLT, expr, create_int(0), "");
                LLVMValueRef negated   = llvm::build_mul(self.builder, expr, create_int(-1), "");
                return llvm::build_select(self.builder, condition, negated, expr, "");
            //case "*":
                //return llvm::build_load_2(self.builder, llvm::type_of(expr), expr, "");
                //io::printn((ZString)llvm::print_value_to_string(expr));

            default:
                util::panic("Unreachable", $$FILE, $$LINE);
        }
}

fn LLVMTypeRef Compiler.get_type_node(&self, ASTNode node)
{
    switch (node.node_type)
    {
        case INIT_VALUE: return self.get_type_node(*node.node.init_value_node.value);
        case STR:        return self.get_type((String[]){"str"});
        case INT:        return self.get_type((String[]){"int"});
        case BOOL:       return self.get_type((String[]){"bool"});
        case FLOAT:      return self.get_type((String[]){"float"});
        case DOUBLE:     return self.get_type((String[]){"double"});
        // TODO: do other types later
        case INIT:       return self.get_struct_type(node.node.init_node);
        case BIN:        return self.get_type_node(*node.node.bin_node.left);
        case IDENT:
            ScopeResult res = self.scope.get(node.node.ident_node.name);
            String type_name;
            switch (res.type)
            {
                case VAR:   type_name = res.variable.type;
                case CONST: type_name = res.constant.type;
                case PARAM: type_name = res.parameter.type;
            }
            Type* type = self.type_table.lookup((char*)type_name.zstr_copy(mem));
            String type_str = ((ZString)type.name).str_view();
            return self.get_type((String[]){type_str});

        default: util::panicf("Unimplemented type `%s`", node.node_type, file: $$FILE, line: $$LINE);
    }
}

fn LLVMTypeRef Compiler.get_struct_type(&self, InitNode node)
{
    ASTNode[] values = node.values;
    LLVMTypeRef[] possible_structs = mem::new_array(LLVMTypeRef, 0);

    foreach STRUCTS: (i, str : self.structs.values(mem))
    {
        if (str.fields.len != values.len) continue;
        foreach (j, field : str.fields)
        {
            if (((ZString)llvm::print_type_to_string(self.get_type((String[]){field.type}))) != ((ZString)llvm::print_type_to_string(self.get_type_node(values[j])))) continue STRUCTS;
        }
        util::array_insert(&possible_structs, str.type);
    }

    return possible_structs.len == 0 ? null : possible_structs[0];
}

fn String Compiler.get_type_from_llvm(&self, LLVMValueRef value)
{
    String llvm_type = ((ZString)llvm::print_type_to_string(llvm::type_of(value))).str_view();
    if (llvm_type[0] == '%')
    {
        return llvm_type.tsplit("%")[1].tsplit(" ")[0];
    }

    switch (llvm_type)
    {
        case "ptr":    return "str"; // TODO: other types
        case "i32":
        case "i64":    return "int";
        case "double": return "double";
        case "i1":     return "bool";
        case "i8":     return "char";
    }

    util::panicf("Unreachable: `%s`", llvm_type, file: $$FILE, line: $$LINE);
}

fn LLVMValueRef Compiler.create_string(&self, String value)
{
    if (self.strings.has_key(value))
    {
        return self.strings.get(value)!!;
    }

    String processed = self.process_escape_sequences(value);
    int    len       = processed.len;

    LLVMValueRef str        = llvm::const_string(processed, processed.len, llvm::FALSE);
    LLVMTypeRef  arr_type   = llvm::array_type(llvm::int8_type(), processed.len + 1);
    LLVMValueRef global_str = llvm::add_global(self.mod, arr_type, "");

    llvm::set_initializer(global_str, str);
    llvm::set_linkage(global_str, PRIVATE_LINKAGE);
    llvm::set_unnamed_addr(global_str, llvm::TRUE);
    llvm::set_global_constant(global_str, llvm::TRUE);

    self.strings.set(value, global_str);

    return global_str;
}

fn void Compiler.compile_switch(&self, SwitchNode node, LLVMValueRef fN, LLVMValueRef parent_block)
{
    int      index = (*self).index++;
    ASTNode* left  = node.expr;

    LLVMBasicBlockRef start_block   = llvm::append_basic_block(fN, string::format(mem, "start.%d", index));
    LLVMBasicBlockRef current_block = parent_block;

    foreach (i, case_stmt : node.cases)
    {
        CaseNode case_node = case_stmt.node.case_node;
        ASTNode* right     = case_node.condition;

        LLVMValueRef      condition  = self.compile_bin({ "==", left, right });
        LLVMBasicBlockRef then_block = llvm::append_basic_block(fN, string::format(mem, "then.%d", index + i));
        LLVMBasicBlockRef next_block = llvm::append_basic_block(fN, string::format(mem, "next.%d", index + i));

        // break
        llvm::build_cond_br(self.builder, condition, then_block, next_block);
        
        // then
        llvm::position_builder_at_end(self.builder, then_block);
        
        self.scope = (*self.scope).new();
        foreach (child : case_node.children)
        {
            self.compile_node(child, fN, parent_block: then_block);
        }
        self.scope = self.scope.parent;

        llvm::build_br(self.builder, start_block);

        llvm::position_builder_at_end(self.builder, next_block);
        current_block = next_block;

        // only add break on last
        if (i == node.cases.len - 1)
        {
            llvm::build_br(self.builder, start_block);
        }
    }

    LLVMBasicBlockRef end_block = llvm::append_basic_block(fN, string::format(mem, "end.%d", index));
    llvm::position_builder_at_end(self.builder, start_block);
    llvm::build_br(self.builder, end_block);

    llvm::position_builder_at_end(self.builder, end_block);
}

fn void Compiler.build_strcmp(&self) {
    LLVMBuilderRef builder = llvm::create_builder();

    LLVMTypeRef str_type = llvm::pointer_type(llvm::int8_type(), 0);
    LLVMTypeRef char_type = llvm::int8_type();
    LLVMTypeRef[] param_types = { str_type, str_type, llvm::int1_type() };
    LLVMTypeRef func_type = llvm::function_type(llvm::int1_type(), param_types, 3, llvm::FALSE);
    LLVMValueRef strcmp_func = llvm::add_function(self.mod, ".strcmp", func_type);

    llvm::set_value_name(llvm::get_param(strcmp_func, 0), "str_1");
    llvm::set_value_name(llvm::get_param(strcmp_func, 1), "str_2");
    llvm::set_value_name(llvm::get_param(strcmp_func, 2), "op_eq");

    LLVMBasicBlockRef entry_block       = llvm::append_basic_block(strcmp_func, "entry");
    LLVMBasicBlockRef loop_block        = llvm::append_basic_block(strcmp_func, "loop");
    LLVMBasicBlockRef neq_cond_block    = llvm::append_basic_block(strcmp_func, "neq");
    LLVMBasicBlockRef check_null_block  = llvm::append_basic_block(strcmp_func, "check_null");
    LLVMBasicBlockRef check_chars_block = llvm::append_basic_block(strcmp_func, "check_chars");
    LLVMBasicBlockRef true_block        = llvm::append_basic_block(strcmp_func, "true");
    LLVMBasicBlockRef false_block       = llvm::append_basic_block(strcmp_func, "false");
    LLVMBasicBlockRef loop_cont_block   = llvm::append_basic_block(strcmp_func, "loop_cont");

    llvm::position_builder_at_end(builder, entry_block);
    LLVMValueRef str_1 = llvm::get_param(strcmp_func, 0);
    LLVMValueRef str_2 = llvm::get_param(strcmp_func, 1);
    LLVMValueRef op_eq = llvm::get_param(strcmp_func, 2);
    llvm::build_br(builder, loop_block);
    
    // loop
    llvm::position_builder_at_end(builder, loop_block);
    
    LLVMValueRef ptr1_phi = llvm::build_phi(builder, str_type, "ptr1");
    LLVMValueRef ptr2_phi = llvm::build_phi(builder, str_type, "ptr2");
    
    llvm::add_incoming(ptr1_phi, &str_1, &entry_block, 1);
    llvm::add_incoming(ptr2_phi, &str_2, &entry_block, 1);

    LLVMValueRef zero = llvm::const_int(llvm::int64_type(), 0, 0);
    LLVMValueRef[] indices = { zero };

    LLVMValueRef gep_1 = llvm::build_gep_2(builder, char_type, ptr1_phi, indices, 1, "gep_1");
    LLVMValueRef gep_2 = llvm::build_gep_2(builder, char_type, ptr2_phi, indices, 1, "gep_2");

    LLVMValueRef char_1 = llvm::build_load_2(builder, char_type, gep_1, "char_1");
    LLVMValueRef char_2 = llvm::build_load_2(builder, char_type, gep_2, "char_2");

    LLVMValueRef chars_diff = llvm::build_i_cmp(builder, llvm::INT_NE, char_1, char_2, "chars_diff");
    
    llvm::build_cond_br(builder, chars_diff, false_block, check_null_block);

    // check null
    llvm::position_builder_at_end(builder, check_null_block);

    LLVMValueRef null_char = llvm::const_int(char_type, 0, 0);
    LLVMValueRef end1 = llvm::build_i_cmp(builder, llvm::INT_EQ, char_1, null_char, "end1");
    LLVMValueRef end2 = llvm::build_i_cmp(builder, llvm::INT_EQ, char_2, null_char, "end2");
    LLVMValueRef both_end = llvm::build_and(builder, end1, end2, "both_end");
    
    llvm::build_cond_br(builder, both_end, true_block, check_chars_block);
    
    // check chars
    llvm::position_builder_at_end(builder, check_chars_block);

    LLVMValueRef either_end = llvm::build_or(builder, end1, end2, "either_end");
    llvm::build_cond_br(builder, either_end, false_block, loop_cont_block);

    // loop cont
    llvm::position_builder_at_end(builder, loop_cont_block);
    LLVMValueRef next_ptr1 = llvm::build_gep_2(builder, char_type, ptr1_phi, &&llvm::const_int(llvm::int64_type(), 1, 0), 1, "next_ptr1");
    LLVMValueRef next_ptr2 = llvm::build_gep_2(builder, char_type, ptr2_phi, &&llvm::const_int(llvm::int64_type(), 1, 0), 1, "next_ptr2");
    
    llvm::add_incoming(ptr1_phi, &next_ptr1, &loop_cont_block, 1);
    llvm::add_incoming(ptr2_phi, &next_ptr2, &loop_cont_block, 1);
    
    llvm::build_br(builder, loop_block);

    // true
    llvm::position_builder_at_end(builder, true_block);
    LLVMValueRef true_result = llvm::build_xor(builder, llvm::const_int(llvm::int1_type(), 0, 0), op_eq, "true_result");
    llvm::build_ret(builder, true_result);

    // false
    llvm::position_builder_at_end(builder, false_block);
    LLVMValueRef false_result = llvm::build_xor(builder, llvm::const_int(llvm::int1_type(), 1, 0), op_eq, "false_result");
    llvm::build_ret(builder, false_result);

    llvm::dispose_builder(builder);

    self.strcmp      = strcmp_func;
    self.strcmp_type = func_type;
}

fn LLVMValueRef create_int(int value) @private => llvm::const_int(llvm::int32_type(), value, llvm::FALSE);

fn LLVMValueRef Compiler.calculate_type_size(&self, LLVMTypeRef type, char* type_name)
{
    Type* type_info = self.type_table.lookup(type_name);

    switch (((ZString)type_name).str_view())
    {
        case "int":    return create_int(4);
        case "str":    return create_int(8);
        case "bool":   return create_int(1);
        case "char":   return create_int(1);
        case "float":  return create_int(4);
        case "double": return create_int(8);
    }

    if (type_info.fields && type_info.num_fields > 0)
    {
        int max_alignment  = 1;
        int current_offset = 0;

        for (int i = 0; i < type_info.num_fields; i++)
        {
            Field* field    = &type_info.fields[i];
            int field_align = self.get_type_alignment(field.type);
            if (field_align > max_alignment)
            {
                max_alignment = field_align;
            }
        }

        for (int i = 0; i < type_info.num_fields; i++)
        {
            Field* field    = &type_info.fields[i];
            int field_align = self.get_type_alignment(field.type);

            int padding    = (field_align - (current_offset % field_align)) % field_align;
            current_offset += padding;

            LLVMValueRef field_size = self.calculate_type_size(field.type.llvm_type, field.type.name);
            current_offset += llvm::const_int_get_z_ext_value(field_size);
        }

        int final_padding = (max_alignment - (current_offset % max_alignment)) % max_alignment;
        current_offset    += final_padding;

        return create_int(current_offset);
    }

    return create_int(0);
}

fn int Compiler.get_type_alignment(&self, Type* type)
{
    if (!type) return 1;

    switch (type.name)
    {
        case "int":    return 4;
        case "str":    return 8;
        case "bool":   return 1;
        case "char":   return 1;
        case "float":  return 4;
        case "double": return 8;
    }

    if (type.fields && type.num_fields > 0)
    {
        int max_alignment = 1;
        for (int i = 0; i < type.num_fields; i++)
        {
            Field* field    = &type.fields[i];
            int field_align = self.get_type_alignment(field.type);
            if (field_align > max_alignment)
            {
                max_alignment = field_align;
            }
        }
        return max_alignment;
    }

    return 1;
}

fn void Compiler.build_strlen(&self) {
    LLVMBuilderRef builder = llvm::create_builder();

    LLVMTypeRef str_ptr_type = llvm::pointer_type(llvm::int8_type(), 0);
    LLVMTypeRef str_ptr_ptr_type = llvm::pointer_type(str_ptr_type, 0);
    LLVMTypeRef int_type = self.get_type((String[]){"int"});
    LLVMTypeRef[] param_types = { str_ptr_ptr_type };
    LLVMTypeRef func_type = llvm::function_type(int_type, param_types, 1, llvm::FALSE);
    LLVMValueRef strlen_func = llvm::add_function(self.mod, ".strlen", func_type);

    llvm::set_value_name(llvm::get_param(strlen_func, 0), "str_ptr");

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(strlen_func, "entry");
    LLVMBasicBlockRef loop_block = llvm::append_basic_block(strlen_func, "loop");
    LLVMBasicBlockRef loop_cont_block = llvm::append_basic_block(strlen_func, "loop_cont");
    LLVMBasicBlockRef exit_block = llvm::append_basic_block(strlen_func, "exit");

    // entry
    llvm::position_builder_at_end(builder, entry_block);
    LLVMValueRef str_ptr = llvm::get_param(strlen_func, 0);
    
    LLVMValueRef str = llvm::build_load_2(builder, str_ptr_type, str_ptr, "str");
    
    llvm::build_br(builder, loop_block);

    // loop
    llvm::position_builder_at_end(builder, loop_block);
    
    LLVMValueRef ptr_phi = llvm::build_phi(builder, str_ptr_type, "ptr");
    LLVMValueRef length_phi = llvm::build_phi(builder, int_type, "length");

    llvm::add_incoming(ptr_phi, &str, &entry_block, 1);
    LLVMValueRef length_init = llvm::const_int(int_type, 0, 0);
    llvm::add_incoming(length_phi, &length_init, &entry_block, 1);

    LLVMValueRef zero = llvm::const_int(int_type, 0, 0);
    LLVMValueRef gep = llvm::build_gep_2(builder, llvm::int8_type(), ptr_phi, &zero, 1, "gep");
    LLVMValueRef char_val = llvm::build_load_2(builder, llvm::int8_type(), gep, "char");

    LLVMValueRef null_char = llvm::const_int(llvm::int8_type(), 0, 0);
    LLVMValueRef is_null = llvm::build_i_cmp(builder, llvm::INT_EQ, char_val, null_char, "is_null");
    llvm::build_cond_br(builder, is_null, exit_block, loop_cont_block);

    // loop cont
    llvm::position_builder_at_end(builder, loop_cont_block);
    
    LLVMValueRef one = llvm::const_int(int_type, 1, 0);
    LLVMValueRef next_ptr = llvm::build_gep_2(builder, llvm::int8_type(), ptr_phi, &one, 1, "next_ptr");
    LLVMValueRef next_length = llvm::build_add(builder, length_phi, one, "next_length");
    
    llvm::add_incoming(ptr_phi, &next_ptr, &loop_cont_block, 1);
    llvm::add_incoming(length_phi, &next_length, &loop_cont_block, 1);
    
    llvm::build_br(builder, loop_block);

    // exit
    llvm::position_builder_at_end(builder, exit_block);
    llvm::build_ret(builder, length_phi);

    llvm::dispose_builder(builder);

    self.strlen = strlen_func;
    self.strlen_type = func_type;
}

fn LLVMValueRef Compiler.compile_inc(&self, IncNode node)
{
    Var variable = self.scope.get_var(node.name);
    
    switch (node.operator)
    {
        case "+":
            LLVMValueRef ptr   = llvm::build_load_2(self.builder, self.get_type((String[]){"int"}), variable.value, "");
            LLVMValueRef value = llvm::build_add(self.builder, ptr, create_int(1), "");
            llvm::build_store(self.builder, value, variable.value);
            return ptr;
        case "-":
            LLVMValueRef ptr   = llvm::build_load_2(self.builder, self.get_type((String[]){"int"}), variable.value, "");
            LLVMValueRef value = llvm::build_sub(self.builder, ptr, create_int(1), "");
            llvm::build_store(self.builder, value, variable.value);
            return ptr;
        case "!":
            LLVMValueRef ptr   = llvm::build_load_2(self.builder, self.get_type((String[]){"bool"}), variable.value, "");
            LLVMValueRef value = llvm::build_not(self.builder, ptr, "");
            llvm::build_store(self.builder, value, variable.value);
            return ptr;
    }
    util::panic("Unreachable", $$FILE, $$LINE);
}

fn void Compiler.compile_for(&self, ForNode node, LLVMValueRef fN)
{
    int index = self.index++;
    LLVMBasicBlockRef loop_block = llvm::append_basic_block(fN, string::format(mem, "loop.%d", index));
    LLVMBasicBlockRef end_block  = llvm::append_basic_block(fN, string::format(mem, "end.%d", index));

    self.scope = self.scope.new();

    self.compile_node(*node.statement);
    
    LLVMValueRef condition = self.compile_node(*node.condition);
    llvm::build_cond_br(self.builder, condition, loop_block, end_block);

    llvm::position_builder_at_end(self.builder, loop_block);
    foreach (child : node.children)
    {
        self.compile_node(child);
    }
    self.compile_node(*node.expression);

    LLVMValueRef new_condition = self.compile_node(*node.condition);
    llvm::build_cond_br(self.builder, new_condition, loop_block, end_block);

    self.scope = self.scope.parent;

    llvm::position_builder_at_end(self.builder, end_block);
}

fn void Compiler.build_strcon(&self) {
    if (!self.strlen) self.build_strlen();

    LLVMBuilderRef builder = llvm::create_builder();

    LLVMTypeRef str_type = llvm::pointer_type(llvm::int8_type(), 0);

    LLVMTypeRef[] param_types = { str_type, str_type };
    LLVMTypeRef func_type = llvm::function_type(str_type, param_types, 2, llvm::FALSE);
    LLVMValueRef strcon_func = llvm::add_function(self.mod, ".strcon", func_type);

    llvm::set_value_name(llvm::get_param(strcon_func, 0), "str_1");
    llvm::set_value_name(llvm::get_param(strcon_func, 1), "str_2");

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(strcon_func, "entry");
    llvm::position_builder_at_end(builder, entry_block);

    LLVMValueRef str_1 = llvm::get_param(strcon_func, 0);
    LLVMValueRef str_2 = llvm::get_param(strcon_func, 1);
    LLVMValueRef ptr_1 = llvm::build_alloca(builder, str_type, "ptr_1");
    LLVMValueRef ptr_2 = llvm::build_alloca(builder, str_type, "ptr_2");

    llvm::build_store(builder, str_1, ptr_1);
    llvm::build_store(builder, str_2, ptr_2);

    LLVMValueRef len_1 = llvm::build_call_2(builder, self.strlen_type, self.strlen, (LLVMValueRef[]){ptr_1}, 1, "len_1");
    LLVMValueRef len_2 = llvm::build_call_2(builder, self.strlen_type, self.strlen, (LLVMValueRef[]){ptr_2}, 1, "len_2");

    LLVMValueRef total = llvm::build_add(builder, len_1, len_2, "total");
    LLVMValueRef size = llvm::build_add(builder, total, create_int(1), "size");

    LLVMValueRef size64 = llvm::build_zext(builder, size, self.get_type((String[]){"int"}), "size64");
    
    LLVMValueRef buf = llvm::build_array_malloc(builder, llvm::int8_type(), size64, "buf");

    llvm::build_memcpy(builder, buf, 1, str_1, 1, len_1, llvm::FALSE);
    
    LLVMValueRef dest = llvm::build_gep_2(builder, llvm::int8_type(), buf, (LLVMValueRef[]){len_1}, 1, "dest");
    llvm::build_memcpy(builder, dest, 1, str_2, 1, len_2, llvm::FALSE);
    
    LLVMValueRef end = llvm::build_gep_2(builder, llvm::int8_type(), buf, (LLVMValueRef[]){total}, 1, "end");
    llvm::build_store(builder, llvm::const_int(llvm::int8_type(), 0, 0), end);

    llvm::build_ret(builder, buf);
    llvm::dispose_builder(builder);

    self.strcon      = strcon_func;
    self.strcon_type = func_type;
}

fn void Compiler.compile_use(&self, UseNode node)
{
    util::array_insert(&self.imports, node.path);
}
