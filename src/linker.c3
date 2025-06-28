module lucy::linker;

import lucy::util;
import std::io, std::os, libc;
import llvm;

fn void link(LLVMModuleRef mod, String module_name, String[] linker_option_arr)
{
    LLVMTargetRef target      = initialize("");
    char*         target_name = llvm::get_target_name(target);
    //char*         cpu         = llvm::get_host_cpu(); // TODO: add cpu param

    llvm::set_target(mod, llvm::get_default_target_triple());

    LLVMTargetMachineRef target_machine = llvm::create_target_machine(
        target,
        llvm::get_default_target_triple(),
        //target_name,
        "generic",
        llvm::get_host_cpu_features(),
        //"+avx2",
        CODE_GEN_LEVEL_DEFAULT,
        RELOC_DEFAULT,
        CODE_MODEL_DEFAULT
    );
    
    LLVMTargetDataRef data_layout = llvm::create_target_data_layout(target_machine);
    char* data_layout_str = llvm::copy_string_rep_of_target_data(data_layout);
    llvm::set_data_layout(mod, data_layout_str);
    llvm::dispose_message(data_layout);

    LLVMPassManagerRef pass_manager = llvm::create_pass_manager();

    llvm::run_pass_manager(pass_manager, mod);

    char* error = null;
    if (llvm::target_machine_emit_to_file(target_machine, mod, string::format(mem, "%s.o", module_name), OBJECT_FILE, &error))
    {
        io::printfn("Failed to emit object file: %s", (ZString)error);
        llvm::dispose_message(error);
        llvm::dispose_pass_manager(pass_manager);
        os::exit(1);
    }
    llvm::dispose_pass_manager(pass_manager);

    // TODO: make system specific options work
    String linker_options = util::join_to_string(linker_option_arr, " ");

    $switch:
    $case env::LINUX:
        int exit_code = libc::system(string::format(mem, "ld -e main %s.o -o %s --dynamic-linker /lib64/ld-linux-x86-64.so.2 -lc %s", module_name, module_name, linker_options).zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $case env::DARWIN:
        int exit_code = libc::system(string::format(mem, "ld -e main %s.o -o %s -lSystem -syslibroot $(xcrun --show-sdk-path) %s", module_name, module_name, linker_options).zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $case env::WIN32:
        int exit_code = libc::system(string::format(mem, "link.exe -e main %s.o -o %s.exe %s", module_name, module_name, linker_options).zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $default:
        io::eprintfn("Unrecognized system: `%s`", env::OS_TYPE);
    $endswitch

    (void)file::delete(string::format(mem, "%s.o", module_name));

    //file::rm
}

// TODO: change to target var passed from main
fn LLVMTargetRef initialize(String target_name) @private
{
    LLVMTargetRef target;
    $switch env::ARCH_TYPE:
    $case AARCH64:
    $case AARCH64_BE:
    $case AARCH64_32:
        llvm::initialize_aarch64_target_info();
        llvm::initialize_aarch64_target();
        llvm::initialize_aarch64_target_mc();
        llvm::initialize_aarch64_asm_parser();
        llvm::initialize_aarch64_asm_printer();
        target = llvm::get_target_from_name("aarch64");
    
    $case ARM:
    $case ARMB:
    $case THUMB:
    $case THUMBEB:
        llvm::initialize_arm_target_info();
        llvm::initialize_arm_target();
        llvm::initialize_arm_target_mc();
        llvm::initialize_arm_asm_parser();
        llvm::initialize_arm_asm_printer();
        target = llvm::get_target_from_name("arm");

    $case RISCV32:
    $case RISCV64:
        llvm::initialize_riscv_target_info();
        llvm::initialize_riscv_target();
        llvm::initialize_riscv_target_mc();
        llvm::initialize_riscv_asm_parser();
        llvm::initialize_riscv_asm_printer();
        target = llvm::get_target_from_name("riscv");

    $case X86:
    $case X86_64:
        llvm::initialize_x86_target_info();
        llvm::initialize_x86_target();
        llvm::initialize_x86_target_mc();
        llvm::initialize_x86_asm_parser();
        llvm::initialize_x86_asm_printer();
        target = llvm::get_target_from_name("x86-64");

    $case XCORE:
        llvm::initialize_x_core_target_info();
        llvm::initialize_x_core_target();
        llvm::initialize_x_core_target_mc();
        llvm::initialize_x_core_asm_parser();
        llvm::initialize_x_core_asm_printer();
        target = llvm::get_target_from_name("core");

    $default:
        io::eprintfn("Unsupportsed system: `%s`", ARCH_TYPE);
    $endswitch

    return target;
}

macro handle_error(int code) @private
{
    io::eprintfn("An error occurred with the linker. exit code %d", code);

    $switch:
    $case env::LINUX:  print_linux_error_code(code);
    $case env::DARWIN: print_darwin_error_code(code);
    $case env::WIN32:  print_win_error_code(code);
    $endswitch
}

macro print_linux_error_code(int code) @private
{
}

macro print_darwin_error_code(int code) @private
{
}

macro print_win_error_code(int code) @private
{
}
