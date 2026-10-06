[@@"no_prelude"]
module Json2dir.Tree
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
open Json2dir.Json

module L = FStar.List.Tot
module S = FStar.String
module IO = FStar.IO

exception TreeError of string

let error (message:string) : ML unit = raise (TreeError message)

// Rust Path::components ignores trailing separators and interior '.' parts.
// Accept the same single normal component, but retain its spelling for I/O.
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

let valid_name (cs:text) : Tot bool =
  match cs with
  | [] | 47::_ | 46::_ ->
    // A leading dot is regular except '.' itself and a leading './'.
    if cs = [] || cs = [46] || cs = [46;46] then false
    else (match cs with
          | 47::_ | 46::47::_ -> false
          | _ ->
            match meaningful (split_path cs [] []) with
            | [p] -> p <> [46;46] && not (L.mem 0 cs)
            | _ -> false)
  | _ ->
    match meaningful (split_path cs [] []) with
    | [p] -> p <> [46;46] && not (L.mem 0 cs)
    | _ -> false

let rec text_compare (a:text) (b:text) : Tot int =
  match a, b with
  | [], [] -> 0
  | [], _ -> -1
  | _, [] -> 1
  | x::xs, y::ys ->
    if x < y then -1 else if x > y then 1 else text_compare xs ys

// serde_json keeps the last duplicate value, then iterates in key order.
let rec replace (key:text) (v:json) (entries:list (text & json))
  : Tot (list (text & json)) =
  match entries with
  | [] -> [(key,v)]
  | (k,old)::rest ->
    if key = k then (key,v)::rest else (k,old)::replace key v rest

let rec deduplicate (entries:list (text & json)) (acc:list (text & json))
  : Tot (list (text & json)) =
  match entries with
  | [] -> acc
  | (key,v)::rest -> deduplicate rest (replace key v acc)

let ordered (entries:list (text & json)) : Tot (list (text & json)) =
  L.sortWith (fun (a,_) (b,_) -> text_compare a b) (deduplicate entries [])

let describe (e:exn) : Tot string = FStar.Exception.string_of_exn e

let attempt (kind:string) (path:string) (work:unit -> ML unit) : ML unit =
  try work () with e -> error ("couldn't create a " ^ kind ^ " at " ^ path ^ ": " ^ describe e)

let write (kind:string) (path:string) (cs:text) : ML unit =
  let content = Json2dir.Utf8.encode cs in
  attempt kind path (fun () ->
    let fd = IO.open_write_file path in
    try (IO.write_string fd content; IO.close_write_file fd)
    with e ->
      (try IO.close_write_file fd with _ -> ());
      raise e)

let make_directory (path:string) : ML unit =
  attempt "directory" path (fun () ->
    (try Unix.mkdir path (Z.to_int 0o777)
     with e -> if Sys.is_directory path then () else raise e);
    // Rust enters the directory even for an empty object. Check the same
    // search permission while keeping our explicit-path traversal.
    Unix.access path [Unix.X_OK])

// Explicit paths avoid changing process cwd. Existing directories are merged,
// and are never recursively removed (matching the Rust implementation).
let rec materialize (parent:string) (entries:list (text & json)) : ML unit =
  match entries with
  | [] -> ()
  | (key,v)::rest ->
    let name = Json2dir.Utf8.encode key in
    if not (valid_name key) then error ("the key " ^ name ^ " under " ^ parent ^ " must have exactly one regular path component");
    let path = parent ^ "/" ^ name in
    (try Unix.unlink path with _ -> ());
    (match v with
     | Object children -> make_directory path; materialize path (ordered children)
     | String content -> write "regular file" path content
     | Array [String kind; String payload] ->
       if kind = [108;105;110;107] then
         let target = Json2dir.Utf8.encode payload in
         attempt "symlink" path (fun () -> Unix.symlink target path)
       else if kind = [115;99;114;105;112;116] then (
         write "script" path payload;
         try
           let mode = (Unix.stat path).Unix.st_perm in
           Unix.chmod path (Int.logor mode (Z.to_int 0o111))
         with e -> error ("couldn't make the script executable at " ^ path ^ ": " ^ describe e))
       else error ("expected a JSON array's first element to be either \"link\" or \"script\" while at " ^ path)
     | Array _ -> error ("expected a JSON array to be of the form [type, payload] while at " ^ path)
     | Number _ | Scalar -> error ("expected a JSON value to be an object, an array, or a string while at " ^ path));
    materialize parent rest

let run (v:json) : ML unit =
  match v with
  | Object entries -> materialize "." (ordered entries)
  | _ -> error "expected provided JSON to be an object"
