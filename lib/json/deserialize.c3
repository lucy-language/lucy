module json::deserialize;
import std::collections;
import std::core;
import json::lex;

macro parse($Type, Allocator alloc, Lexer* lex) {
	$if ($defined($Type.parse_json)):
		$Type custom;
		// NOTE if just rethrowing, macro doesn't seem to realize
		// that the return type is $TYPE!
		if (catch custom.parse_json(alloc, lex)) {
			return PARSE_ERROR?;
		}
		return custom;
	$endif

	// Maybe needs to be checked before `lex.next()`
	$switch ($Type.kindof):
		$case TypeKind.STRUCT:
			$if ($Type.nameof == "Maybe"):
				// TODO can I name type in a variable?
				if (try value = parse($typefrom($Type.membersof[0].typeid), alloc, lex)) {
					return maybe::value{$typefrom($Type.membersof[0].typeid)}(value);
				} else if (lex.token_slice == "null") {
					return maybe::EMPTY{$typefrom($Type.membersof[0].typeid)};
				} else {
					return PARSE_ERROR?;
				}
			$endif
	$endswitch

	Tag first_tag = lex.next()!!;
	// hack for array end, see below.
	if (first_tag == ARRAY_END) return PARSE_ARRAY_END?;

	// Switch on primitives
	$switch ($Type):
		$case String:
			switch(first_tag) {
				case STRING: return (String)lex.token_slice;
				default: return PARSE_ERROR?;
			}
		$case bool:
			switch(first_tag) {
				case TRUE: return true;
				case FALSE: return false;
				default: return PARSE_ERROR?;
			}
		$case int:
			switch(first_tag) {
				case NUM: return ((String)lex.token_slice).to_int(10);
				default: return PARSE_ERROR?;
			}
	$endswitch

	// Switch on complex types
	$switch ($Type.kindof):
		$case TypeKind.ENUM:
			switch(first_tag) {
				case STRING:
					$foreach $value : $Type.values:
						$if ($defined($Type.json_repr)):
							if ($value.json_repr == lex.token_slice) {
								return $value;
							}
						$endif
						if ($value.nameof == lex.token_slice) {
							return $value;
						}
					$endforeach
				default: return PARSE_ERROR?;
			}
		$case TypeKind.STRUCT:
			$Type obj;
			if (first_tag != OBJ_START) return PARSE_ERROR?;
			// iterate through each parsed field, do linear search against
			//members of struct.
			while (true) {
				Tag tag = lex.next()!!;
				if (tag == OBJ_END) break;
				if (tag != FIELD_NAME) return PARSE_ERROR?;
				String field_name = (String)lex.token_slice;
				$foreach $member : $Type.membersof:
					$if ($member.kindof == TypeKind.UNION):
						return UNION_NOT_SUPPORTED?;
					$else
						if (field_name == $member.nameof) {
							obj.$eval($member.nameof) = parse($typefrom($member.typeid), alloc, lex)!!;
							// break; no break in compile-time foreach?
						}
					$endif

				$endforeach
			}
			return obj;
		$case TypeKind.SLICE:
			if (first_tag != ARRAY_START) return PARSE_ERROR?;
			@pool() {
				List{$typefrom($Type.inner)} arr;
				arr.tinit();

				while (true) {
					var value = parse($typefrom($Type.inner), alloc, lex);
					if (catch err = value) {
						// This is a hacky way to catch the end of the array.
						// But checking the tag will advance one. FIX
						if (err == PARSE_ARRAY_END) break;
						return PARSE_ERROR?;
					}
					arr.push(value);
				}
				return arr.to_array(alloc);
			};
		$case TypeKind.UNION:
			return UNION_NOT_SUPPORTED?;
	$endswitch

	return PARSE_ERROR?;
}

faultdef
	PARSE_ERROR,
	UNION_NOT_SUPPORTED,
	PARSE_ARRAY_END, // TODO fix this hack
;
