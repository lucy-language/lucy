module lucy::linker;

import lucy::util;
import std::io, std::os, libc;
import llvm;

fn void link(LLVMModuleRef mod, String module_name, String[] linker_option_arr)
{
    LLVMModuleRef[] link_mods;

    create_main(mod, module_name);

    LLVMTargetRef target        = initialize("");
    ichar*        target_triple = "x86_64-unknown-unknown";

    llvm::set_target(mod, target_triple);

    LLVMTargetMachineRef target_machine = llvm::create_target_machine(
        target,
        target_triple,
        "generic",
        "+avx2",
        llvm::CODEGENLEVELDEFAULT,
        llvm::RELOCDEFAULT,
        llvm::CODEMODELDEFAULT
    );
    
    LLVMTargetDataRef data_layout     = llvm::create_target_data_layout(target_machine);
    ichar*            data_layout_str = llvm::copy_string_rep_of_target_data(data_layout);
    llvm::set_data_layout(mod, data_layout_str);
    llvm::dispose_target_data(data_layout);

    ichar* error = null;
    if (llvm::target_machine_emit_to_file(target_machine, mod, (CChar*)string::format(mem, "%s.o", module_name), llvm::OBJECTFILE, &error))
    {
        io::printfn("Failed to emit object file: %s", (ZString)error);
        llvm::dispose_message(error);
        os::exit(1);
    }

    // TODO: make system specific options work
    String linker_option_str = util::join_to_string(linker_option_arr, " ");

    String[] linker_options;
    add_option(&linker_options, "ld");
    add_option(&linker_options, "/usr/lib/crt1.o"); 
    add_option(&linker_options, "/usr/lib/crti.o");
    add_option(&linker_options, "-e");
    add_option(&linker_options, "_start");
    add_option(&linker_options, "/usr/lib/crtn.o");
    add_option(&linker_options, "-lc");
    add_option(&linker_options, string::format(mem, "%s.o", module_name));
    add_option(&linker_options, "-o");
    add_option(&linker_options, module_name);
    add_option(&linker_options, "--dynamic-linker");
    add_option(&linker_options, "/usr/lib/ld-linux-x86-64.so.2");

    foreach (link : linker_option_arr)
    {
        add_option(&linker_options, string::format(mem, "-l%s", link));
    }

    int exit_code = libc::system(util::join_to_string(linker_options, " ").zstr_copy(mem));

    (void)file::delete(string::format(mem, "%s.o", module_name));
}

fn void create_main(LLVMModuleRef mod, String module_name)
{
    LLVMBuilderRef builder = llvm::create_builder();

    LLVMValueRef main_func = llvm::get_named_function(mod, (CChar*)string::format(mem, "%s.main", module_name));
    LLVMTypeRef  func_type = llvm::function_type(llvm::int_32_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);

    LLVMTypeRef       entrypoint_type = llvm::function_type(llvm::int_32_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);
    LLVMValueRef      entrypoint      = llvm::add_function(mod, "main", entrypoint_type);
    LLVMBasicBlockRef entry_block     = llvm::append_basic_block(entrypoint, "entry");

    llvm::position_builder_at_end(builder, entry_block);
    LLVMValueRef ret_value = llvm::build_call_2(builder, func_type, main_func, (LLVMValueRef[]){}, 0, "");
    llvm::build_ret(builder, ret_value);

    llvm::dispose_builder(builder);
}

fn LLVMTargetRef initialize(String target_name) @private
{
    llvm::initialize_x86_target_info();
    llvm::initialize_x86_target();
    llvm::initialize_x86_target_mc();
    llvm::initialize_x86_asm_parser();
    llvm::initialize_x86_asm_printer();
    return llvm::get_target_from_name("x86-64");
}

fn void add_option(String[]* options, String option)
{
    util::array_insert(options, option);
}
