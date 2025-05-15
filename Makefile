all: clean build run compile

run: build
	./build/lucy -f test.lc

compile: run
	clang *.ll -o program

build: clean
	c3c build -l LLVM

clean:
	rm -rf ./build
	rm -f *.ll
	rm -f program