module json;

// Deserialize basic types from json
// - number
// - string
// - array
// - struct
// - null?

// zero copy, only allocates for slices (json arrays)
macro from_str($Type, Allocator alloc, String s) {
	Lexer lex;
	lex.init(s);
	return deserialize::parse($Type, alloc, &lex);
}

macro String? to_json(expr, Allocator alloc) {
	@pool() {
		DString s;
		s.tinit();
		serialize::add_json(expr, &s)!;
		return s.copy_str(alloc);
	};
}
