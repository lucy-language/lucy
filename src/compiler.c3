module lucy::compiler;

import std::collections::map, std::collections::list, std::os, std::io;
import lucy::node, lucy::errors, lucy::scope::comp, lucy::util, lucy::lookup_table;
import llvm;

extern fn int strcmp(char* s1, char* s2);

faultdef INVALID_TYPE;

struct Compiler
{
    FileNode                file_node;
    String                  module_name;
    String                  file_path;
    LLVMModuleRef           mod;
    LLVMBuilderRef          builder;
    LLVMContextRef          context;
    HashMap{String, Def}    functions;
    HashMap{String, Struct} structs;
    Scope*                  scope;
    int                     index;
    LLVMValueRef            true_ptr;
    LLVMValueRef            false_ptr;
    LLVMValueRef            strcmp;
    TypeTable*              type_table;
}

struct Def
{
    LLVMValueRef function;
    LLVMTypeRef  type;
}

struct Struct
{
    LLVMTypeRef type;
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
        .type_table  = type_table
    };
}

fn void Compiler.compile(&self)
{
    // register functions first so they can be found even if declared later than call
    foreach (child : self.file_node.children)
    {
        switch (child.node_type)
        {
            case DEF:    self.add_def(child.node.def_node);
            case STRUCT: self.add_struct(child.node.struct_node);
            default: break;
        }
    }
    
    defer llvm::dispose_builder(self.builder);
    foreach (ast : self.file_node.children)
    {
        self.compile_node(ast);
    }

    char* error;
    if (llvm::print_module_to_file(self.mod, string::tformat("%s.ll", self.module_name), &error))
    {
        util::panic(string::tformat("Failed to write IR: %s", *error), $$FILE, $$LINE);
    }
}

fn void Compiler.add_def(&self, DefNode node)
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
        llvm::set_value_name(llvm::get_param(fN, i), (node.parameters)[i].node.parameter_node.name);
    }
    
    self.functions.set(node.name, { fN, fn_type });
}

fn void Compiler.add_struct(&self, StructNode node)
{
    LLVMTypeRef struct_type = llvm::struct_create_named(self.context, node.name);

    self.structs.set(node.name, { struct_type });
}

fn LLVMValueRef Compiler.compile_node(&self, ASTNode ast, LLVMValueRef fN = null, LLVMTypeRef type = null)
{
    switch (ast.node_type)
    {
        case DEF:               self.compile_def(ast.node.def_node);
        case RETURN:            self.compile_return(ast.node.return_node);
        case EXT:               self.compile_ext(ast.node.ext_node);
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
        case CALL:       return self.compile_call(ast.node.call_node);
        case IDENT:      return self.compile_ident(ast.node.ident_node);
        case IF:                self.compile_if(ast.node.if_node, fN);
        case BIN:        return self.compile_bin(ast.node.bin_node);
        case INIT:       return self.compile_init(ast.node.init_node, type);
        case INIT_VALUE: return self.compile_node(*ast.node.init_value_node.value);
        case ACCESS:     return self.compile_access(ast.node.access_node);
        case STRUCT:            self.compile_struct(ast.node.struct_node);
        case MACRO:             self.compile_macro(ast.node.macro_node);
        case WHILE:             self.compile_while(ast.node.while_node, fN);
        case UNARY:      return self.compile_unary(ast.node.unary_node);

        default:         util::panic(string::tformat("Missing compile function `%s`", ast.node_type), $$FILE, $$LINE);
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
        self.compile_node(child, function);
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
    self.functions.set(name, { fN, fn_type });
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
        case "str": value = llvm::const_string(node.value.node.str_node.value, node.value.node.str_node.value.len, llvm::TRUE);
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
        LLVMValueRef value = self.compile_node(*node.value, type: type);
        llvm::build_store(self.builder, value, variable);

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
    String value     = node.value;
    String processed = self.process_escape_sequences(value);
    int    len       = processed.len;

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
    int value = (int)node.value.to_uint()!!;
    LLVMTypeRef type = llvm::int32_type(); // TODO: return llvm::int64_type() if on 64 bit system

    return llvm::const_int(type, value, llvm::FALSE);
}

fn LLVMValueRef Compiler.compile_bool(&self, BoolNode node)
{
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

fn LLVMValueRef Compiler.compile_call(&self, CallNode node)
{
    Def? def = self.functions.get(node.name);
    if (catch error = def)
    {
        util::panic(string::tformat("Could not find function `%s`", node.name), $$FILE, $$LINE);
    }

    LLVMValueRef function = def.function;
    LLVMTypeRef function_type = def.type;

    LLVMValueRef[] llvm_args = mem::new_array(LLVMValueRef, node.arguments.len);
    for (int i = 0; i < node.arguments.len; ++i) {
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
    String name = node.name;
    LLVMValueRef loaded;
    if ((self.scope).has_var(name))
    {
        Var variable = (*self.scope).get_var(name);
        LLVMTypeRef type = self.get_type((String[]){ variable.type });
        loaded = llvm::build_load_2(self.builder, type, variable.value, "");
    } else if ((*self.scope).has_const(name))
    {
        Const constant = (*self.scope).get_const(name);
        LLVMTypeRef type = self.get_type((String[]){ constant.type });
        loaded = llvm::build_load_2(self.builder, type, constant.value, "");
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

fn void Compiler.compile_if(&self, IfNode node, LLVMValueRef* fN)
{
    LLVMValueRef condition = self.compile_node(*node.condition);

    // create first for reference to jump
    LLVMBasicBlockRef then_block = llvm::append_basic_block(fN, "");
    LLVMBasicBlockRef else_block = llvm::append_basic_block(fN, "");
    LLVMBasicBlockRef end_block = llvm::append_basic_block(fN, "");

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

    // evaluate else
    self.scope = (*self.scope).new();
    llvm::position_builder_at_end(self.builder, else_block);
    foreach (child : node.else_children)
    {
        self.compile_node(child);
    }
    llvm::build_br(self.builder, end_block);
    self.scope = (*self.scope).parent;

    // continue code
    llvm::position_builder_at_end(self.builder, end_block);
}

fn LLVMValueRef Compiler.compile_bin(&self, BinNode node)
{
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
    // strings
    {
        util::panic("comparing strings. use libc->strcmp instead", $$FILE, $$LINE);
        /*
        if (self.strcmp == null)
        {
            self.build_strcmp();
        }

        LLVMValueRef[] args =
        {
            left,
            right
        };

        return llvm::build_call_2(self.builder, llvm::int1_type(), self.strcmp, args, 2, "");
        */
    }

    return null;
}

fn LLVMValueRef Compiler.compile_float(&self, FloatNode node)
{
    return llvm::const_real(llvm::float_type(), node.value.to_float())!!;
}

fn LLVMValueRef Compiler.compile_double(&self, DoubleNode node)
{
    return llvm::const_real(llvm::double_type(), node.value.to_double())!!;
}

fn LLVMValueRef Compiler.compile_init(&self, InitNode node, LLVMTypeRef type)
{
    LLVMValueRef[] values = mem::new_array(LLVMValueRef, node.values.len);
    foreach (i, value : node.values)
    {
        values[i] = self.compile_node(value);
    }

    LLVMValueRef instance = llvm::const_struct(values, values.len, 0);

    return instance;
}

fn LLVMValueRef Compiler.compile_access(&self, AccessNode node)
{
    Var variable = self.scope.get_var(node.id);
    LLVMValueRef struct_value = variable.value;
    LLVMTypeRef struct_type = self.structs.get(variable.type)!!.type;
    
    return self.resolve_access(struct_value, struct_type, variable.type.zstr_copy(mem), node.node);
}

fn LLVMValueRef Compiler.resolve_access(&self, LLVMValueRef base_value, LLVMTypeRef base_type, char* prev_id, ASTNode* next_node)
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
                    
                    return self.resolve_access(field_ptr, field.type.llvm_type, field.type.name, access.node);
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
        default:
            util::panic("Unsupported node type in access chain", $$FILE, $$LINE);
    }
    util::panic("Unreachable", $$FILE, $$LINE);
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
    io::printn((ZString)self.type_table.lookup(prev).name);

    io::printn((ZString)llvm::print_value_to_string(value));
    
    return null;
}

fn void Compiler.compile_macro(&self, MacroNode node)
{
    // TODO
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
    
    if (llvm::type_of(expr) == llvm::int1_type())
    {
        switch (node.operator)
        {
            case "!":
                return llvm::build_i_cmp(self.builder, llvm::INT_EQ, expr, llvm::const_int(llvm::int1_type(), llvm::FALSE, llvm::FALSE), "");
            default:
                util::panicf("Unsupported operator `%s` for type `bool`", node.operator, file: $$FILE, line: $$LINE);
        }
    }
    util::panic("Unreachable", $$FILE, $$LINE);
}
