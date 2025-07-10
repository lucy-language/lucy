/*
module lucy::linker;

import lucy::util, lucy::lexer, lucy::parser, lucy::lookup_table, lucy::compiler, lucy::semantic_analyser, lucy::node;
import std::io, std::os, libc;
import llvm;

fn void link(LLVMModuleRef mod, String module_name, String[] linker_option_arr, bool use_libc = true)
{
    LLVMModuleRef[] link_mods;

    if (use_libc)
    {
        create_main(mod, module_name);
    } else
    {
        create_entrypoint(mod, module_name);
    }

    LLVMTargetRef target        = initialize("");
    char*         target_name   = llvm::get_target_name(target);
    char*         target_triple = null;
    switch (((ZString)target_name).str_view())
    {
        case "x86":     target_triple = "i386-unknown-unknown";
        case "x86-64":  target_triple = "x86_64-unknown-unknown";
        case "arm":     target_triple = "arm-unknown-unknown";
        case "aarch64": target_triple = "aarch64-unknown-unknown";
        case "riscv":   target_triple = "riscv64-unknown-unknown";
    }

    llvm::set_target(mod, target_triple);

    LLVMTargetMachineRef target_machine = llvm::create_target_machine(
        target,
        target_triple,
        "generic",
        "+avx2",
        CODE_GEN_LEVEL_DEFAULT,
        RELOC_DEFAULT,
        CODE_MODEL_DEFAULT
    );
    
    LLVMTargetDataRef data_layout = llvm::create_target_data_layout(target_machine);
    char* data_layout_str = llvm::copy_string_rep_of_target_data(data_layout);
    llvm::set_data_layout(mod, data_layout_str);
    llvm::dispose_message(data_layout);

    char* error = null;
    if (llvm::target_machine_emit_to_file(target_machine, mod, string::format(mem, "%s.o", module_name), OBJECT_FILE, &error))
    {
        io::printfn("Failed to emit object file: %s", (ZString)error);
        llvm::dispose_message(error);
        os::exit(1);
    }

    // llvm::print_module_to_file(mod, string::format(mem, "%s.ll", module_name), null);

    // TODO: make system specific options work
    String linker_option_str = util::join_to_string(linker_option_arr, " ");

    $switch:
    $case env::LINUX:
        String[] linker_options;
        add_option(&linker_options, "ld");

        if (use_libc)
        {
            add_option(&linker_options, "/usr/lib/crt1.o"); 
            add_option(&linker_options, "/usr/lib/crti.o");
        }

        add_option(&linker_options, "-e");
        add_option(&linker_options, "_start");

        if (use_libc)
        {
            add_option(&linker_options, "/usr/lib/crtn.o");
            add_option(&linker_options, "-lc");
        }

        add_option(&linker_options, string::format(mem, "%s.o", module_name));
        add_option(&linker_options, "-o");
        add_option(&linker_options, module_name);
        add_option(&linker_options, "--dynamic-linker");
        add_option(&linker_options, get_dynamic_linker());
        add_option(&linker_options, linker_option_str);

        int exit_code = libc::system(util::join_to_string(linker_options, " ").zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $case env::DARWIN:
        int exit_code = libc::system(string::format(mem, "ld -e _start %s.o -o %s -lSystem -syslibroot $(xcrun --show-sdk-path) %s", module_name, module_name, linker_options).zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $case env::WIN32:
        int exit_code = libc::system(string::format(mem, "link.exe -e _start %s.o -o %s.exe %s", module_name, module_name, linker_options).zstr_copy(mem));
        if (exit_code != 0) handle_error(exit_code);
    $default:
        io::eprintfn("Unrecognized system: `%s`", env::OS_TYPE);
    $endswitch

    (void)file::delete(string::format(mem, "%s.o", module_name));

    //file::rm
}

fn void create_main(LLVMModuleRef mod, String module_name)
{
    // create builder
    LLVMBuilderRef builder = llvm::create_builder();

    // find main fn
    LLVMValueRef main_func = llvm::get_named_function(mod, string::format(mem, "%s.main", module_name));
    LLVMTypeRef  func_type = llvm::function_type(llvm::int32_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);

    // create entrypoint
    LLVMTypeRef       entrypoint_type = llvm::function_type(llvm::int32_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);
    LLVMValueRef      entrypoint      = llvm::add_function(mod, "main", entrypoint_type);
    LLVMBasicBlockRef entry_block     = llvm::append_basic_block(entrypoint, "entry");

    // startup code
    llvm::position_builder_at_end(builder, entry_block);
    LLVMValueRef ret_value = llvm::build_call_2(builder, func_type, main_func, (LLVMValueRef[]){}, 0, "");
    llvm::build_ret(builder, ret_value);

    // cleanup
    llvm::dispose_builder(builder);
}

fn String get_dynamic_linker()
{
    $switch env::OS_TYPE:
    $case LINUX:
        $switch env::ARCH_TYPE:
        $case AARCH64:
        $case AARCH64_BE:
        $case AARCH64_32:
            return "/usr/lib/ld-linux-aarch64.so.1";
        $case ARM:
        $case ARMB:
            return "/usr/lib/ld-linux-armhf.so.3";
        $case RISCV32:
            return "/usr/lib/ld-linux-riscv32-ilp32d.so.1";
        $case RISCV64:
            return "/usr/lib/ld-linux-riscv64-lp64d.so.1";
        $case X86:
            return "/usr/lib/ld-linux.so.2";
        $case X86_64:
            return "/usr/lib/ld-linux-x86-64.so.2";
        $endswitch
    $endswitch
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
        llvm::initialize_x86_target_info();
        llvm::initialize_x86_target();
        llvm::initialize_x86_target_mc();
        llvm::initialize_x86_asm_parser();
        llvm::initialize_x86_asm_printer();
        target = llvm::get_target_from_name("x86");

    $case X86_64:
        llvm::initialize_x86_target_info();
        llvm::initialize_x86_target();
        llvm::initialize_x86_target_mc();
        llvm::initialize_x86_asm_parser();
        llvm::initialize_x86_asm_printer();
        target = llvm::get_target_from_name("x86-64");

    $default:
        io::eprintfn("Unsupportsed system: `%s`", ARCH_TYPE);
    $endswitch

    return target;
}

fn void add_option(String[]* options, String option)
{
    util::array_insert(options, option);
}

fn void create_entrypoint(LLVMModuleRef mod, String module_name)
{
    // create builder
    LLVMBuilderRef builder = llvm::create_builder();

    // find main fn
    LLVMValueRef main_func = llvm::get_named_function(mod, string::format(mem, "%s.main", module_name));
    LLVMTypeRef  func_type = llvm::function_type(llvm::int32_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);

    // create entrypoint
    LLVMTypeRef       entrypoint_type = llvm::function_type(llvm::void_type(), (LLVMTypeRef[]){}, 0, llvm::FALSE);
    LLVMValueRef      entrypoint      = llvm::add_function(mod, "_start", entrypoint_type);
    LLVMBasicBlockRef entry_block     = llvm::append_basic_block(entrypoint, "entry");

    // startup code
    llvm::position_builder_at_end(builder, entry_block);
    llvm::build_call_2(builder, func_type, main_func, (LLVMValueRef[]){}, 0, "");
    build_exit(mod, builder);
    llvm::build_unreachable(builder);

    // cleanup
    llvm::dispose_builder(builder);
}

fn void build_exit(LLVMModuleRef mod, LLVMBuilderRef builder)
{
    LLVMValueRef call;
    $switch env::ARCH_TYPE:
    $case AARCH64:
    $case AARCH64_BE:
    $case AARCH64_32:
        $switch env::OS_TYPE:
        $case LINUX:
            String $asm = "mov x8, #93\n" "mov x0, #0\n" "svc #0";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $case DARWIN:
            String $asm = "mov x16, #1\n" "mov x0, #0\n" "svc #0x80";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $endswitch
    $case ARM:
    $case ARMB:
        $switch env::OS_TYPE:
        $case LINUX:
            String $asm = "mov r7, #1\n" "mov r0, #0\n" "swi #0";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $endswitch
    $case RISCV32:
    $case RISCV64:
        $switch env::OS_TYPE:
        $case LINUX:
            String $asm = "li a7, 93\n" "li a0, 0\n" "ecall";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $endswitch
    $case X86:
        $switch env::OS_TYPE:
        $case LINUX:
            String $asm = "movl $$1, %eax\n" "movl $$0, %ebx\n" "int 0x80";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $case WIN32:
            String $asm = "push $$0\n" "call _ExitProcess@4";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_INTEL, llvm::FALSE);
        $endswitch
    $case X86_64:
        $switch env::OS_TYPE:
        $case LINUX:
            String $asm = "movq $$60, %rax\n" "movq $$0, %rdi\n" "syscall";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $case DARWIN:
            String $asm = "movq $$0x2000001, %rax\n" "movq $$0, %rdi\n" "syscall";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_ATT, llvm::FALSE);
        $case WIN32:
            String $asm = "mov rcx, 0\n" "sub rsp, 32\n" "call ExitProcess";
            call = llvm::get_inline_asm(llvm::void_type(), $asm, $asm.len, "", 0, llvm::TRUE, llvm::FALSE, INLINE_ASM_DIALECT_INTEL, llvm::FALSE);
        $endswitch
    $endswitch
    // TODO: differ system
    //LLVMTypeRef  func_type = llvm::function_type(llvm::void_type(), (LLVMTypeRef[]){llvm::int32_type()}, 1, llvm::FALSE);
    //LLVMValueRef exit_func = llvm::add_function(mod, "exit", func_type);

    //llvm::build_call_2(builder, func_type, exit_func, (LLVMValueRef[]){llvm::const_int(llvm::int32_type(), 0, llvm::FALSE)}, 1, "");
    llvm::build_call_2(builder, llvm::function_type(llvm::void_type(), null, 0, llvm::FALSE), call, (LLVMValueRef[]){}, 0, "");
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
*/
