module Json2dir.Spec
open Json2dir.Json
module L = FStar.List.Tot

// F* adaptation of the executable specification in tsalkenov/json2dir-lean,
// Spec.lean at 1d307a44d04a690fdc142ae7b219ede83195dd27 (WTFPL).
// Theorems for these exact runtime functions live in Json2dir.Proofs.

let safe_component (part:text) : Tot bool =
  part <> [] && part <> [46] && part <> [46;46] &&
  not (L.mem 47 part) && not (L.mem 0 part)

type name_error = | MultipleComponents | NonRegularComponent
type name_result = | NameOk : text -> name_result | NameError : name_error -> name_result

let rec split_path (cs:text) (current:text) (acc:list text) : Tot (list text) =
  match cs with
  | [] -> L.rev ((L.rev current)::acc)
  | 47::rest -> split_path rest [] ((L.rev current)::acc)
  | c::rest -> split_path rest (c::current) acc

let rec meaningful (parts:list text) : Tot (list text) =
  match parts with
  | [] -> []
  | p::rest ->
    if p = [] || p = [46] then meaningful rest else p::meaningful rest

let has_prefix (name:text) : Tot bool =
  match name with
  | 47::_ | 46::47::_ | [46] -> true
  | _ -> false

let interpret_parts (parts:list text) (prefix:bool) : Tot name_result =
  if L.length parts + (if prefix then 1 else 0) <> 1 then NameError MultipleComponents
  else if prefix || parts = [[46;46]] then NameError NonRegularComponent
  else match parts with
  | [part] -> if safe_component part then NameOk part else NameError NonRegularComponent
  | _ -> NameError MultipleComponents

let parse_name (name:text) : Tot name_result =
  if L.mem 0 name then NameError NonRegularComponent
  else interpret_parts (meaningful (split_path name [] [])) (has_prefix name)

let valid_name (name:text) : Tot bool =
  match parse_name name with
  | NameOk _ -> true
  | NameError _ -> false

type entry =
  | Directory : list (text & json) -> entry
  | File : text -> entry
  | Link : text -> entry
  | Script : text -> entry

type entry_error = | InvalidPart | InvalidArray | InvalidArrayKind
type entry_result = | EntryOk : entry -> entry_result | EntryError : entry_error -> entry_result

let link_tag : text = [108;105;110;107]
let script_tag : text = [115;99;114;105;112;116]

let classify (value:json) : Tot entry_result =
  match value with
  | Object children -> EntryOk (Directory children)
  | String content -> EntryOk (File content)
  | Array [String kind; String payload] ->
    if kind = link_tag then EntryOk (Link payload)
    else if kind = script_tag then EntryOk (Script payload)
    else EntryError InvalidArrayKind
  | Array _ -> EntryError InvalidArray
  | Null | Bool _ | Number _ -> EntryError InvalidPart
