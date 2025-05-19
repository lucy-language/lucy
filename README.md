# Lucy Compiler

# ⚠️ DISCLAIMER ⚠️

### this project is unfinished and can't do much at the current state of development. it can simply create functions without parameters and declare externs. the parser is capable of running the example below but will not compile to something expected.

## Description

This is a compiler written in [C3](https://c3-lang.org/).

## Key features
- #### in-file linker options*
- #### package- or module-like structure
- #### simple syntax

*for more readability and less guessing. the compiler automatically links with everything specified in the files to remove need to figure out what to link with and manually link it

## Code Example

```
# Sample program in our custom language
%"c";

pkg main;

ext void printf(str fmt, var str args);

def void main() 
{
    greet("Kiana");
}

def void greet(str name)
{
    printf("Hello, %s!\n", name)
}
```

## Building and Running

### Prerequisites
- C3 compiler installed (available from [c3-lang.org](https://c3-lang.org/))
- clang
- libLLVM (available from [releases.llvm.org](https://releases.llvm.org/download.html))

## Running the project (no build)
```bash
make
```

### Building the Compiler

```bash
# Compile the compiler source
c3c build -l LLVM
```

### Using the Compiler

```bash
# Compile a source file
./build/lucy -f <file_name>.lc
clang <file_name>.ll -o output_file_name

# Show help message
./build/lucy --help
```

### Example of the original version

this is a code example of what is possible in the original version written in kotlin that will soon be possible here too.

#### file raylib.lc
```lc
%"raylib";

pkg raylib;

global const LOG_NONE = 7;

global ext void InitWindow(num width, num height, str title) as init_window; # alias is optional
global ext void CloseWindow() as close_window;
global ext bool WindowShouldClose() as window_should_close;
global ext void ClearBackground(num color) as clear_background;
global ext void BeginDrawing() as begin_drawing;
global ext void EndDrawing() as end_drawing;
global ext void SetTraceLogLevel(num level) as set_trace_log_level;
```
#### file main.lc
```lc
%"c";

pkg main;

import raylib as rl; # alias is optional

ext void printf(str fmt, var str args);

def void main()
{
    printf("Hello, World!\n");

    rl.set_trace_log_level(rl.LOG_LONE);
    rl.init_window(800, 500, "Example window");
    
    while (!rl.window_should_close())
    {
        rl.begin_drawing();
        rl.crear_background(0xffccffff); # rgba
        
        rl.end_drawing();
    }
    
    rl.close_window();
}
```

the command to compile would simply be this
```bash
lucy compile main.lc
```
as it will automatically compile any used imports and link them with what they require so what it does internally is
```bash
clang main.ll raylib.ll -o main -lc -lraylib
```

you don't have to specify linked libraries like this, it's fully optional but recommended for readability and simplicity. you can remove the link options at the top of the file and run this instead
```bash
lucy compile main.lc -lc -lraylib
```

## Contributing

Contributions are welcome! Please submit pull requests or open issues for any bugs or feature requests.

## [License](LICENSE)