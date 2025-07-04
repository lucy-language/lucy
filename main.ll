; ModuleID = 'main'
source_filename = "main"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-unknown"

@0 = internal unnamed_addr constant [6 x i8] c"Kiana\00"
@1 = internal unnamed_addr constant [12 x i8] c"Hello, %s!\0A\00"

declare void @InitWindow(i32, i32, ptr)

declare void @CloseWindow()

define i32 @main.main() {
entry:
  call void @greet(ptr @0)
  ret i32 0
}

define void @greet(ptr %name) {
entry:
  call void (ptr, ...) @InitWindow(ptr @1, ptr %name)
  ret void
}

define void @_start() {
entry:
  %0 = call i32 @main.main()
  call void asm sideeffect "movq $$60, %rax\0Amovq $$0, %rdi\0Asyscall", ""()
  unreachable
}
