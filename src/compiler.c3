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
    HashMap{String, LLVMValueRef} variables;
}

fn Compiler new(Parser parser)
{
    ASTNode file = parser.parse();
    String mod_name = file.node.file_node.module_name;
    LLVMModuleRef mod = llvm::module_create_with_name(mod_name);
    LLVMBuilderRef builder = llvm::create_builder();

    return
    {
        .file_node   = file.node.file_node,
        .module_name = mod_name,
        .file_path   = parser.file_path,
        .mod         = mod,
        .builder     = builder,
        .variables   = {}
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

fn void Compiler.compile_node(&self, ASTNode ast)
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
        default: break;
    }
}

fn void Compiler.compile_def(&self, DefNode node)
{
    LLVMTypeRef type;

    switch (node.type)
    {
        case "void": type = llvm::void_type();
        case "double": type = llvm::double_type();
        case "float": type = llvm::float_type();
        case "bool": type = llvm::int1_type();
        case "int": type = llvm::int32_type();
    }

    List{LLVMTypeRef} param_list;
    bool vararg;

    // TODO: temp, make actually function for all types
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

    LLVMTypeRef fn_type = llvm::function_type(type, parameters, parameters.len, vararg ? 1 : 0);
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
}

fn void Compiler.compile_return(&self, ReturnNode node)
{
    LLVMTypeRef type = llvm::int32_type(); // TODO: figure out type from expression

    ASTNode value = node.value[0];

    // TODO: catch error early
    if (catch value.node.int_node.value.to_long())
    {
        errors::print_node(self.file_path, value, "int expected, got string");
    }

    // TODO: assume value is INT for now
    LLVMValueRef value_ref = llvm::const_int(type, value.node.int_node.value.to_int(), 0)!!;
    llvm::build_ret(self.builder, value_ref);
}

// TODO: handle actual types and names
fn void Compiler.compile_ext(&self, ExtNode node)
{
    LLVMTypeRef int_type = llvm::int32_type();
    LLVMTypeRef str_type = llvm::pointer_type(llvm::int8_type(), 0);
    LLVMTypeRef[] printf_args = {str_type};

    bool vararg;

    foreach (param : node.parameters)
    {
        if (param.node.parameter_node.vararg)
        {
            vararg = true;
            break;
        }
    }

    LLVMTypeRef printf_type = llvm::function_type(int_type, printf_args, 1, vararg ? 1 : 0);
    llvm::add_function(self.mod, node.name, printf_type);
}

fn void Compiler.compile_const(&self, ConstNode node, bool global = false)
{
    // TODO: figure out types

    LLVMValueRef value;

    switch (node.type)
    {
        case "bool": value = llvm::const_int(llvm::int1_type(), node.value[0].node.bool_node.value == "true" ? 1 : 0, 0);
//        case "char": value = llvm::const_int(llvm::int8_type(), node.value[0].node.char_node.value, 1); // TODO: add char type
        case "int": value = llvm::const_int(llvm::int32_type(), node.value[0].node.int_node.value.to_int(), 1)!!; // TODO: return llvm::int64_type() if on 64 bit system
        case "float": value = llvm::const_real(llvm::float_type(), node.value[0].node.float_node.value.to_float())!!;
        case "double": value = llvm::const_real(llvm::double_type(), node.value[0].node.double_node.value.to_double())!!;
        case "str": value = llvm::const_string(node.value[0].node.str_node.value, node.value[0].node.str_node.value.len, 1);
    }
    LLVMValueRef constant = llvm::add_global(self.mod, llvm::type_of(value), node.name);

    llvm::set_initializer(constant, value);
    llvm::set_linkage(constant, global ? EXTERNAL_LINKAGE : PRIVATE_LINKAGE);
    llvm::set_global_constant(constant, 1);
    llvm::set_unnamed_addr(constant, 1);
}

<*
    @param self : "The Compiler"
    @param type : "The type string"
*>
fn LLVMTypeRef Compiler.get_type(&self, String type)
{
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

    io::eprintfn("Type `%s` could not be matched", type);
    os::exit(1);
    return {};
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
    LLVMValueRef variable = llvm::build_alloca(self.builder, self.get_type(node.type), node.name);

    LLVMValueRef value;
    switch (node.type)
        {
            case "bool": value = llvm::const_int(llvm::int1_type(), node.value[0].node.bool_node.value == "true" ? 1 : 0, 0);
    //        case "char": value = llvm::const_int(llvm::int8_type(), node.value[0].node.char_node.value, 1); // TODO: add char type
            case "int": value = llvm::const_int(llvm::int32_type(), node.value[0].node.int_node.value.to_int(), 1)!!; // TODO: return llvm::int64_type() if on 64 bit system
            case "float": value = llvm::const_real(llvm::float_type(), node.value[0].node.float_node.value.to_float())!!;
            case "double": value = llvm::const_real(llvm::double_type(), node.value[0].node.double_node.value.to_double())!!;
            case "str": value = llvm::const_string(node.value[0].node.str_node.value, node.value[0].node.str_node.value.len, 1);
        }

    self.variables.set(node.name, variable);
    llvm::build_store(self.builder, value, variable);
}

fn void Compiler.compile_reassign(&self, ReassignNode node)
{
    LLVMValueRef value = llvm::const_string(node.value[0].node.str_node.value, node.value[0].node.str_node.value.len, 1);
    llvm::build_store(self.builder, value, self.variables.get(node.name))!!;
}