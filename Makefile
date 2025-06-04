all: clean build run compile exec

run: build
	./build/lucy -f test.lc --ast

compile: run
	clang *.ll -o program

build: clean
	c3c build -l LLVM

clean:
	rm -rf ./build
	rm -f *.ll
	rm -f program

exec: compile
	./program
