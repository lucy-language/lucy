module json::serialize;
import std::core;

macro void? add_json(src, DString* dest) {
	$if ($defined($typeof(src).to_json)):
		src.to_json(dest)!;
		return;
	$endif

	// Switch on primitives
	$switch ($typeof(src)):
		$case String:
			dest.append(`"`);
			dest.append(src);
			dest.append(`"`);
			return;
		$case bool:
			if (src) {
				dest.append("true");
			} else {
				dest.append("false");
			}
			return;
		$case int:
			dest.appendf("%d", src);
			return;
	$endswitch

	// Switch on complex types
	$switch ($typeof(src).kindof):
		$case TypeKind.ENUM:
			dest.appendf(`"`);
			$if ($defined($typeof(src).json_repr)):
				dest.appendf(src.json_repr);
			$else
				dest.appendf(src.nameof);
			$endif
			dest.appendf(`"`);
		$case TypeKind.STRUCT:
			// Check Maybe first
			$if ($typeof(src).nameof == "Maybe"):
				if (src.has_value) {
					add_json(src.$eval($typeof(src).membersof[0].nameof), dest)!!;
				} else {
					dest.appendf("null");
				}
				return;
			$endif

			$if ($typeof(src).nameof == "HashMap"):
				add_hashmap(src, dest)!!;
				return;
			$endif

			// Not Maybe, just regular struct
			dest.append("{");
			int members_written;
			$foreach $member : $typeof(src).membersof:
				$if ($member.kindof == TypeKind.UNION):
					return UNION_NOT_SUPPORTED?;
				$else
					// check for @tag("json", "skip_empty")
					bool $memb_is_maybe_skip = false;
					$if ($typefrom($member.typeid).nameof == "Maybe"):
						$if ($member.has_tagof("json")):
							$if ($member.tagof("json") == "skip_empty"):
								$memb_is_maybe_skip = true;
							$endif
						$endif
					$endif

					// TODO clean up this logic. compile time and runtime interaction is a bit messy
					$if ($memb_is_maybe_skip):
						if (!src.$eval($member.nameof).has_value) {
						// do nothing
						} else {
							if (members_written > 0) {
								dest.append(",");
							}
							dest.appendf(`"%s":`, $member.nameof);
							add_json(src.$eval($member.nameof), dest)!!;
							members_written += 1;
						}
					$else
						if (members_written > 0) {
							dest.append(",");
						}
						dest.appendf(`"%s":`, $member.nameof);
						add_json(src.$eval($member.nameof), dest)!!;
						members_written += 1;
					$endif
				$endif
			$endforeach
			dest.append("}");
			return;
		$case TypeKind.SLICE:
			dest.append("[");
			foreach (idx, element : src) {
				if (idx > 0) {
					dest.append(",");
				}
				add_json(element, dest)!!;
			}
			dest.append("]");
			return;
		$case TypeKind.UNION:
			return UNION_NOT_SUPPORTED?;
	$endswitch

	// TODO add error here if type not supported?
}

// Using iter; with the @each_entry, didn't like using var
// in the macro body call.
macro void? add_hashmap(src, DString* dest) {
	$if ($typeof(src).nameof != "HashMap"):
		return EXPECTED_HASHMAP?;
	$endif

	dest.append("{");
	usz idx;
	var iter = src.iter();
	while (idx < iter.len()) {
		var entry = iter.get(idx);
		var key = entry.key;
		var value = entry.value;
		if (idx > 0) {
			dest.append(",");
		}
		add_json(key, dest)!;
		dest.append(":");
		add_json(value, dest)!;
		idx += 1;
	};
	dest.append("}");
}

faultdef UNION_NOT_SUPPORTED, EXPECTED_HASHMAP;
