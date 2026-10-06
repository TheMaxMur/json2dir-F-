[@@"no_prelude"]
module Json2dir.Main
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All

let rec read_lines (buffer:Buffer.t) : ML string =
  let line : option string =
    try Some (Stdlib.input_line Stdlib.stdin)
    with | Stdlib.End_of_file -> None | e -> raise e
  in
  match line with
  | None -> Buffer.contents buffer
  | Some s -> Buffer.add_string buffer s; Buffer.add_string buffer "\n"; read_lines buffer

let fail (message:string) : ML unit =
  FStar.IO.write_string FStar.IO.stderr ("Error: " ^ message ^ ".\n");
  exit 1

// serde_json rejects non-finite numbers while parsing, even in a duplicate
// member that a later value would replace. Validate before any filesystem I/O.
let rec validate_numbers (v:Json2dir.Json.json) : ML unit =
  match v with
  | Json2dir.Json.Number cs ->
    let number = Float.of_string (Json2dir.Utf8.encode cs) in
    if not (Float.is_finite number) then fail "couldn't convert stdin to JSON: number out of range"
  | Json2dir.Json.Object entries ->
    FStar.List.iter (fun (_,child) -> validate_numbers child) entries
  | Json2dir.Json.Array entries -> FStar.List.iter validate_numbers entries
  | _ -> ()

let main () : ML unit =
  match Array.to_list Sys.argv with
  | [_] ->
    let input =
      try read_lines (Buffer.create (Z.to_int 4096))
      with e -> fail ("couldn't read stdin: " ^ FStar.Exception.string_of_exn e); ""
    in
    if not (String.is_valid_utf_8 input) then fail "couldn't read stdin: invalid UTF-8";
    (match Json2dir.Json.parse (Json2dir.Utf8.decode input) with
     | Json2dir.Json.Error e -> fail ("couldn't convert stdin to JSON: " ^ e)
     | Json2dir.Json.Ok v ->
       validate_numbers v;
       try Json2dir.Tree.run v
       with
       | Json2dir.Tree.TreeError e -> fail e
       | e -> fail (FStar.Exception.string_of_exn e))
  | _ ->
    FStar.IO.write_string FStar.IO.stderr "Usage: json2dir < file.json\n";
    exit 1

#push-options "--warn_error -272"
let _ = main ()
#pop-options
