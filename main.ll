; ModuleID = 'main'
source_filename = "main"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-unknown"

@std.math.E = internal unnamed_addr constant double 0x4005BF0A8B145769
@std.math.PI = internal unnamed_addr constant double 0x400921FB54442D18
@main.LOL = internal unnamed_addr constant [5 x i8] c"TEST\00"

declare i64 @printf(ptr, ...)

define i64 @main.pow(i64 %base, i64 %exponent) {
entry:
  %0 = icmp eq i64 %exponent, 0
  br i1 %0, label %then.0, label %end.0

then.0:                                           ; preds = %entry
  ret i64 1
  br label %end.0

end.0:                                            ; preds = %entry, %then.0
  %result = alloca i64, align 8
  store i64 %base, ptr %result, align 4
  %i = alloca i64, align 8
  store i64 1, ptr %i, align 4
  %1 = load i64, ptr %i, align 4
  %2 = icmp slt i64 %1, %exponent
  br i1 %2, label %loop.1.preheader, label %end.1

loop.1.preheader:                                 ; preds = %end.0
  br label %loop.1

loop.1:                                           ; preds = %loop.1.preheader, %loop.1
  %3 = load i64, ptr %result, align 4
  %4 = mul i64 %3, %base
  store i64 %4, ptr %result, align 4
  %5 = load i64, ptr %i, align 4
  %6 = add i64 %5, i32 1
  store i64 %6, ptr %i, align 4
  %7 = load i64, ptr %i, align 4
  %8 = icmp slt i64 %7, %exponent
  br i1 %8, label %loop.1, label %end.1

end.1:                                            ; preds = %loop.1, %end.0
  %9 = load i64, ptr %result, align 4
  ret i64 %9
}

define i64 @main.main() {
entry:
  ret i32 0
}

define i64 @std.math.pow(i64 %base, i64 %exponent) {
entry:
  %0 = icmp eq i64 %exponent, 0
  br i1 %0, label %then.0, label %end.0

then.0:                                           ; preds = %entry
  ret i64 1
  br label %end.0

end.0:                                            ; preds = %entry, %then.0
  %result = alloca i64, align 8
  store i64 %base, ptr %result, align 4
  %i = alloca i64, align 8
  store i64 1, ptr %i, align 4
  %1 = load i64, ptr %i, align 4
  %2 = icmp slt i64 %1, %exponent
  br i1 %2, label %loop.1.preheader, label %end.1

loop.1.preheader:                                 ; preds = %end.0
  br label %loop.1

loop.1:                                           ; preds = %loop.1.preheader, %loop.1
  %3 = load i64, ptr %result, align 4
  %4 = mul i64 %3, %base
  store i64 %4, ptr %result, align 4
  %5 = load i64, ptr %i, align 4
  %6 = add i64 %5, i32 1
  store i64 %6, ptr %i, align 4
  %7 = load i64, ptr %i, align 4
  %8 = icmp slt i64 %7, %exponent
  br i1 %8, label %loop.1, label %end.1

end.1:                                            ; preds = %loop.1, %end.0
  %9 = load i64, ptr %result, align 4
  ret i64 %9
}

define i32 @main() {
entry:
  %0 = call i32 @main.main()
  ret i32 %0
}
