module lucy::compiler;

import std;
import lucy;
import llvm;

faultdef INVALID_TYPE;

struct Compiler
{
    FileNode                      file_node;
    String                        module_name;
    String                        file_path;
    LLVMModuleRef                 mod;
    LLVMBuilderRef                builder;
    HashMap{String, Def}          functions;
    Scope                         scope;
}

struct Def
{
    LLVMValueRef function;
    LLVMTypeRef  type;
}

fn Compiler new(String file_path, ASTNode file)
{
    String mod_name = file.node.file_node.module_name;
    LLVMModuleRef mod = llvm::module_create_with_name(mod_name);
    LLVMBuilderRef builder = llvm::create_builder();

    return
    {
        .file_node   = file.node.file_node,
        .module_name = mod_name,
        .file_path   = file_path,
        .mod         = mod,
        .builder     = builder
    };
}

fn void Compiler.compile(&self)
{
    defer llvm::dispose_builder(self.builder);
    foreach (ast : self.file_node.children)
    {
        self.compile_node(ast);
    }

    char* error;
    if (llvm::print_module_to_file(self.mod, string::tformat("%s.ll", self.module_name), &error))
    {
        io::eprintfn("Failed to write IR: %s", *error);
        llvm::dispose_message(error);
        return;
    }
}

fn LLVMValueRef Compiler.compile_node(&self, ASTNode ast)
{
    switch (ast.node_type)
    {
        case DEF: self.compile_def(ast.node.def_node);
        case RETURN: self.compile_return(ast.node.return_node);
        case EXT: self.compile_ext(ast.node.ext_node);
        case CONST: self.compile_const(ast.node.const_node);
        case GLOBAL: self.compile_global(ast.node.global_node);
        case VAR: self.compile_var(ast.node.var_node);
        case REASSIGN: self.compile_reassign(ast.node.reassign_node);
        case STR: return self.compile_str(ast.node.str_node);
        case INT: return self.compile_int(ast.node.int_node);
        case BOOL: return self.compile_bool(ast.node.bool_node);
        case CALL: return self.compile_call(ast.node.call_node);
        case IDENT: return self.compile_ident(ast.node.ident_node);
        default: break;
    }

    return {};
}

fn void Compiler.compile_def(&self, DefNode node)
{
    LLVMTypeRef type = self.get_type(node.types);

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

        switch (param.type)
        {
            case "str": param_list.push(llvm::pointer_type(llvm::int8_type(), 0));
            case "str[]": param_list.push(llvm::pointer_type(llvm::pointer_type(llvm::int8_type(), 0), 0));
            case "int": param_list.push(llvm::int32_type());
            default: errors::print_node(self.file_path, parameter, string::format(mem, "Invalid type `%s`", param.type));
        }
    }

    LLVMTypeRef[] parameters = mem::new_array(LLVMTypeRef, param_list.len());

    for (int i = 0; i < param_list.len(); i++)
    {
        parameters[i] = param_list.get(i);
    }

    LLVMTypeRef fn_type = llvm::function_type(type, parameters, parameters.len, vararg ? llvm::TRUE : llvm::FALSE);
    LLVMValueRef fN = llvm::add_function(self.mod, node.name, fn_type);

    for (int i = 0; i < parameters.len; i++) {
        llvm::set_value_name(llvm::get_param(fN, i), node.parameters[i].node.parameter_node.name);
    }

    LLVMBasicBlockRef entry_block = llvm::append_basic_block(fN, "entry");
    llvm::position_builder_at_end(self.builder, entry_block);

    foreach (child : node.children)
    {
        self.compile_node(child);
    }

    self.functions.set(node.name, { fN, fn_type });
}

fn void Compiler.compile_return(&self, ReturnNode node)
{
    ASTNodeList values = node.values;
    if (values.len() == 0)
    {
        llvm::build_ret_void(self.builder);
    } else if (values.len() == 1)
    {
        llvm::build_ret(self.builder, self.compile_node(values[0]));
    } else
    {
        LLVMValueRef[] llvm_values = mem::new_array(LLVMValueRef, values.len());
        for (int i = 0; i < llvm_values.len; i++)
        {
            llvm_values[i] = self.compile_node(values[i]);
        }

        llvm::build_ret(self.builder, llvm::const_struct(llvm_values, values.len(), llvm::FALSE));
    }
}

// TODO: handle actual types and names
fn void Compiler.compile_ext(&self, ExtNode node)
{
    StringList types;
    types.push(node.type);
    LLVMTypeRef type = self.get_type(types);

    bool vararg;
    foreach (param : node.parameters)
    {
        if (param.node.parameter_node.vararg)
        {
            vararg = true;
            break;
        }
    }

    usz size = vararg ? node.parameters.len() - 1 : node.parameters.len();
    LLVMTypeRef[] llvm_param_types = mem::new_array(LLVMTypeRef, size);
    for (int i = 0; i < size; i++)
    {
        ParameterNode param = node.parameters[i].node.parameter_node;
        StringList param_types;
        param_types.push(param.type);

        llvm_param_types[i] = self.get_type(param_types);
    }

    LLVMTypeRef fn_type = llvm::function_type(type, llvm_param_types, llvm_param_types.len, vararg ? llvm::TRUE : llvm::FALSE);
    LLVMValueRef fN = llvm::add_function(self.mod, node.name, fn_type);

    self.functions.set(node.name, { fN, fn_type });
}

fn void Compiler.compile_const(&self, ConstNode node, bool global = false)
{
    // TODO: figure out types

    LLVMValueRef value;

    switch (node.type)
    {
        case "bool": value = llvm::const_int(llvm::int1_type(), node.value[0].node.bool_node.value == "true" ? 1 : 0, llvm::FALSE);
//        case "char": value = llvm::const_int(llvm::int8_type(), node.value[0].node.char_node.value, 1); // TODO: add char type
        case "int": value = llvm::const_int(llvm::int32_type(), node.value[0].node.int_node.value.to_int(), llvm::TRUE)!!; // TODO: return llvm::int64_type() if on 64 bit system
        case "float": value = llvm::const_real(llvm::float_type(), node.value[0].node.float_node.value.to_float())!!;
        case "double": value = llvm::const_real(llvm::double_type(), node.value[0].node.double_node.value.to_double())!!;
        case "str": value = llvm::const_string(node.value[0].node.str_node.value, node.value[0].node.str_node.value.len, llvm::TRUE);
    }
    LLVMValueRef constant = llvm::add_global(self.mod, llvm::type_of(value), node.name);

    llvm::set_initializer(constant, value);
    llvm::set_linkage(constant, global ? EXTERNAL_LINKAGE : PRIVATE_LINKAGE);
    llvm::set_global_constant(constant, llvm::TRUE);
    llvm::set_unnamed_addr(constant, llvm::TRUE);
}

fn LLVMTypeRef Compiler.get_type(&self, StringList types)
{
    if (types.len() == 1)
    {
        String type = types[0];
        switch (type)
        {
            case "bool": return llvm::int1_type();
            case "char": return llvm::int8_type();
            case "int": return llvm::int32_type(); // TODO: return llvm::int64_type() if on 64 bit system
            case "float": return llvm::float_type();
            case "double": return llvm::double_type();
            case "void": return llvm::void_type();
            case "str": return llvm::pointer_type(llvm::int8_type(), 0);
            // TODO: add struct/custom type
        }
    } else
    {
        LLVMTypeRef[] llvm_types = mem::new_array(LLVMTypeRef, types.len());
        for (int i = 0; i < llvm_types.len; i++)
        {
            StringList tmp;
            tmp.init(mem, String.sizeof);
            tmp.push(types[i]);
            llvm_types[i] = self.get_type(tmp);
        }

        return llvm::struct_type(llvm_types, llvm_types.len, llvm::FALSE);
    }

    io::eprintfn("Type `%s` could not be matched", types);
    os::exit(1);
}

fn void Compiler.compile_global(&self, GlobalNode node)
{
    switch (node.node[0].node_type)
    {
        case DEF: break; // TODO
        case EXT: break; // TODO
        case CONST: self.compile_const(node.node[0].node.const_node, true);
        default: break; // TODO: show error
    }
}

fn void Compiler.compile_var(&self, VarNode node)
{
    if (node.value.len() == 0)
    {
        return;
    }

    if (node.names.len() == 1)
    {
        LLVMValueRef variable = llvm::build_alloca(self.builder, self.get_type(node.types), node.names[0]);
        llvm::build_store(self.builder, self.compile_node(node.value[0]), variable);

        self.scope.variables.set(node.names[0], variable);
        return;
    }

    LLVMValueRef value = self.compile_node(node.value[0]);
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

            self.scope.variables.set(node.names[i], variable);
        }
    }
}

fn void Compiler.compile_reassign(&self, ReassignNode node)
{
    LLVMValueRef value = llvm::const_string(node.value[0].node.str_node.value, node.value[0].node.str_node.value.len, llvm::TRUE);
    llvm::build_store(self.builder, value, self.scope.get_var(node.name));
}

fn LLVMValueRef Compiler.compile_str(&self, StrNode node)
{
    String value = node.value;
    String processed = self.process_escape_sequences(value);

    LLVMValueRef str = llvm::const_string(processed, processed.len, llvm::FALSE);
    LLVMTypeRef arr_type = llvm::array_type(llvm::int8_type(), processed.len + 1);
    LLVMValueRef global_str = llvm::add_global(self.mod, arr_type, "");
    llvm::set_initializer(global_str, str);
    llvm::set_linkage(global_str, PRIVATE_LINKAGE);
    llvm::set_unnamed_addr(global_str, llvm::TRUE);
    llvm::set_global_constant(global_str, llvm::TRUE);

    return global_str;
}

fn LLVMValueRef Compiler.compile_int(&self, IntNode node)
{
    int value = node.value.to_int()!!;
    LLVMTypeRef type = llvm::int32_type(); // TODO: return llvm::int64_type() if on 64 bit system

    return llvm::const_int(type, value, llvm::FALSE);
}

fn LLVMValueRef Compiler.compile_bool(&self, BoolNode node)
{
    return llvm::const_int(llvm::int1_type(), node.value == "true" ? 1 : 0, llvm::FALSE);
}

fn LLVMValueRef Compiler.compile_call(&self, CallNode node)
{
    Def? def = self.functions.get(node.name);
    if (catch error = def)
    {
        io::eprintfn("Could not find function `%s`", node.name);
        os::exit(1);
    }

    LLVMValueRef function = def.function;
    LLVMTypeRef function_type = def.type;

    LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, node.arguments.len());
    for (int i = 0; i < node.arguments.len(); ++i) {
        ASTNode arg_node = node.arguments[i];
        LLVMValueRef arg_value = self.compile_node(arg_node);
        llvm_args[i] = arg_value;
    }

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

fn LLVMValueRef Compiler.compile_ident(&self, IdentNode node)
{
    LLVMValueRef variable = self.scope.get_var(node.name);
    LLVMValueRef loaded = llvm::build_load_2(self.builder, llvm::type_of(variable), variable, "");
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