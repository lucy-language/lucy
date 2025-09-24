pkg test;

def void main()
{
    var char a = 'a';
    var char b = '\u0ffa';
    var char c = '\n';
    var char d = '\033';
}

# define i64 @test.main() {
# entry:
#   %c = alloca i8, align 4
#   store i8 10, ptr %c, align 4
#   ret i64 0
# }
