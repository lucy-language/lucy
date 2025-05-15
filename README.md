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

## Contributing

Contributions are welcome! Please submit pull requests or open issues for any bugs or feature requests.

## [License](LICENSE)