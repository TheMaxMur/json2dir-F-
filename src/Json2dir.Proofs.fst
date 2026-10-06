module Json2dir.Proofs
open Json2dir.Json
open Json2dir.Spec
module L = FStar.List.Tot

// Counterparts of every theorem in the pinned Lean Spec.lean. These prove
// properties of Json2dir.Spec, which is imported by the actual CLI.

let interpret_parts_safe (parts:list text) (prefix:bool) (part:text)
  : Lemma
    (requires (interpret_parts parts prefix == NameOk part))
    (ensures (safe_component part == true)) =
  match parts with
  | [p] -> ()
  | _ -> ()

let parse_name_safe (name:text) (part:text)
  : Lemma
    (requires (parse_name name == NameOk part))
    (ensures (safe_component part == true)) =
  interpret_parts_safe (meaningful (split_path name [] [])) (has_prefix name) part

let parse_name_no_traversal (name:text) (part:text)
  : Lemma
    (requires (parse_name name == NameOk part))
    (ensures (part <> [] /\ part <> [46] /\ part <> [46;46] /\
              L.mem 47 part == false /\ L.mem 0 part == false)) =
  parse_name_safe name part

// Also expose the relation between success, normalization and the original
// key. This rules out a prefix and NUL in the raw key, not just in its result.
let parse_name_single_component (name:text) (part:text)
  : Lemma
    (requires (parse_name name == NameOk part))
    (ensures (meaningful (split_path name [] []) == [part] /\
              has_prefix name == false /\ L.mem 0 name == false)) =
  match meaningful (split_path name [] []) with
  | [p] -> ()
  | _ -> ()

let valid_name_has_safe_component (name:text)
  : Lemma
    (requires (valid_name name == true))
    (ensures (exists part. parse_name name == NameOk part /\ safe_component part == true)) =
  match parse_name name with
  | NameOk part -> parse_name_safe name part
  | NameError _ -> ()

let classify_directory (children:list (text & json))
  : Lemma (classify (Object children) == EntryOk (Directory children)) = ()

let classify_file (content:text)
  : Lemma (classify (String content) == EntryOk (File content)) = ()

let classify_link (target:text)
  : Lemma (classify (Array [String link_tag; String target]) == EntryOk (Link target)) = ()

let classify_script (content:text)
  : Lemma (classify (Array [String script_tag; String content]) == EntryOk (Script content)) = ()

let classify_unknown_kind (kind:text) (payload:text)
  : Lemma
    (requires (kind <> link_tag /\ kind <> script_tag))
    (ensures (classify (Array [String kind; String payload]) == EntryError InvalidArrayKind)) = ()

let classify_empty_array ()
  : Lemma (classify (Array []) == EntryError InvalidArray) = ()

let classify_null ()
  : Lemma (classify Null == EntryError InvalidPart) = ()

let classify_bool (b:bool)
  : Lemma (classify (Bool b) == EntryError InvalidPart) = ()

let classify_num (number:text)
  : Lemma (classify (Number number) == EntryError InvalidPart) = ()
