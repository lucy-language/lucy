module deserialize_test;
import std::collections::maybe;
import std::io;
import json;

fn void test_basic() @test {
	test::eq(json::from_str(bool, allocator::temp(), "true")!!, true);
	test::eq(json::from_str(String, allocator::temp(), "\"foo\"")!!, "foo");
	test::eq(json::from_str(int, allocator::temp(), "1")!!, 1);
}

struct Foo {
	bool is_bar;
	int baz;
	String bee;
}

fn bool Foo.equals(self, Foo other) {
	return
		self.is_bar == other.is_bar &&
		self.baz == other.baz &&
		self.bee == other.bee;
}

fn void test_struct() @test {
	Foo foo = json::from_str(Foo, allocator::temp(), `{ "is_bar": true, "baz": 3, "bee": "buzz" }`)!!;
	test::eq(foo, (Foo){ .is_bar = true, .baz = 3, .bee = "buzz" });
}

fn void test_array() @test {
	test::eq(json::from_str(int[], allocator::temp(), "[ 1, 2 ]")!!, (int[]) { 1, 2 });
}

struct Bar {
	int[] bar;
}
fn void test_soa() @test {
	Bar bar = json::from_str(Bar, allocator::temp(), "{ \"bar\": [ 1, 2 ]}")!!;
	test::eq(bar.bar, (int[]) { 1, 2, });
}

fn void test_aos() @test {
	Foo[] foos= json::from_str(Foo[], allocator::temp(), `[{"is_bar":true},{"is_bar":false}]`)!!;
	// Foo[] doesn't implement equatable even when Foo does?
	test::eq(foos[0], (Foo){ .is_bar = true });
	test::eq(foos[1], (Foo){ .is_bar = false });
}

enum Baz {
	ONE,
	TWO,
}

fn void? Baz.parse_json(&self, Allocator alloc, Lexer* lex) {
	switch (lex.next()!!) {
		case STRING:
			switch (lex.token_slice) {
				case "one": *self = Baz.ONE;
				case "two": *self = Baz.TWO;
			}
		default:
			return deserialize::PARSE_ERROR?;
	}
}

fn void test_custom() @test {
	Baz baz = json::from_str(Baz, allocator::temp(), `"one"`)!!;
	test::eq(baz, Baz.ONE);
}

fn void test_maybe_value() @test {
	Maybe{int} x = json::from_str(Maybe{int}, allocator::temp(), `1`)!!;
	Maybe{int} expected = maybe::value{int}(1);
	test::eq(x.get()!!, expected.get()!!);
}

fn void test_maybe_null() @test {
	Maybe{int} x = json::from_str(Maybe{int}, allocator::temp(), `null`)!!;
	assert(!@ok(x.get()));
}

fn void test_maybe_wrong() @test {
	assert(!@ok(json::from_str(Maybe{int}, allocator::temp(), `"wrong-value"`)));
}

struct MaybeStruct {
	Maybe{int} inner;
}
fn void test_maybe_in_struct() @test {
	MaybeStruct ms = json::from_str(MaybeStruct, allocator::temp(), `{"inner":1}`)!!;
	test::eq(ms.inner.get()!!, 1);
}

enum MyEnum {
	FOO,
	BAR,
}
fn void test_enum() @test {
	MyEnum my = json::from_str(MyEnum, allocator::temp(), `"FOO"`)!!;
	test::eq(my, MyEnum.FOO);
}

enum MyEnumAssoc : char (String json_repr) {
	FOO = "foo",
	BAR = "bar",
}
fn void test_enum_associated_value() @test {
	MyEnumAssoc my = json::from_str(MyEnumAssoc, allocator::temp(), `"bar"`)!!;
	test::eq(my, MyEnumAssoc.BAR);
}

struct NestedMaybeStruct {
	Maybe{Foo} foo;
}
fn void test_nested_maybe_struct() @test {
	NestedMaybeStruct n = json::from_str(NestedMaybeStruct, allocator::temp(), `{"foo":{"is_bar":true}}`)!!;
	test::eq(n.foo.get()!!, (Foo){ .is_bar = true, });
}

struct StructWithUnion {
	union {
		Foo foo;
	}
}
fn void test_struct_with_union() @test {
	StructWithUnion? n = json::from_str(StructWithUnion, allocator::temp(), `{"foo":{"id_bar":true}}`);
	if (catch err = n) {
		test::eq(err, deserialize::UNION_NOT_SUPPORTED);
	}
}
