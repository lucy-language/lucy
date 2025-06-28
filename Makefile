all: clean build run exec

run: build
	./build/lucy compile main.lc --ast

#compile: run
#	clang test.ll -l raylib -lc -o program

build: clean
	c3c build -l LLVM

clean:
	rm -rf ./build
	rm -f *.ll
	rm -f main
	rm -f *.o

exec:
	./main
