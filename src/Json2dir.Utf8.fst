[@@"no_prelude"]
module Json2dir.Utf8
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All

module L = FStar.List.Tot

let rec bytes (seq:unit -> ML (Seq.node Char.t)) (acc:Json2dir.Json.text)
  : ML Json2dir.Json.text =
  match seq () with
  | Seq.Nil -> L.rev acc
  | Seq.Cons c rest ->
    let n = Z.of_int (Char.code c) in
    if n >= 0 then bytes rest (n::acc) else failwith "invalid byte"

// Called only after String.is_valid_utf_8. All multi-byte cases consume
// a complete scalar; validation rejects overlong forms and surrogates.
let rec decode_bytes (bs:Json2dir.Json.text) (acc:Json2dir.Json.text)
  : Tot Json2dir.Json.text =
  match bs with
  | [] -> L.rev acc
  | a::rest ->
    if a < 0x80 then decode_bytes rest (a::acc)
    else if a < 0xe0 then
      (match rest with
       | b::tail -> decode_bytes tail (((a % 32)*64 + b % 64)::acc)
       | _ -> L.rev acc)
    else if a < 0xf0 then
      (match rest with
       | b::c::tail -> decode_bytes tail (((a % 16)*4096 + (b % 64)*64 + c % 64)::acc)
       | _ -> L.rev acc)
    else
      (match rest with
       | b::c::d::tail -> decode_bytes tail (((a % 8)*262144 + (b % 64)*4096 + (c % 64)*64 + d % 64)::acc)
       | _ -> L.rev acc)

let decode (input:string) : ML Json2dir.Json.text =
  decode_bytes (bytes (String.to_seq input) []) []

// Native calls only encode a byte or append to a buffer. The UTF-8 conversion
// itself is implemented here, with no custom OCaml source or subprocesses.
let byte (buffer:Buffer.t) (n:nat) : ML unit =
  Buffer.add_char buffer (Char.chr (Z.to_int n))

let scalar (buffer:Buffer.t) (n:nat) : ML unit =
  if n <= 0x7f then byte buffer n
  else if n <= 0x7ff then (
    byte buffer (0xc0 + n / 64);
    byte buffer (0x80 + n % 64))
  else if n <= 0xffff then (
    byte buffer (0xe0 + n / 4096);
    byte buffer (0x80 + (n / 64) % 64);
    byte buffer (0x80 + n % 64))
  else (
    byte buffer (0xf0 + n / 262144);
    byte buffer (0x80 + (n / 4096) % 64);
    byte buffer (0x80 + (n / 64) % 64);
    byte buffer (0x80 + n % 64))

let rec append (buffer:Buffer.t) (cs:Json2dir.Json.text) : ML unit =
  match cs with
  | [] -> ()
  | c::rest -> scalar buffer c; append buffer rest

let encode (cs:Json2dir.Json.text) : ML string =
  let buffer = Buffer.create (Z.to_int 256) in
  append buffer cs;
  Buffer.contents buffer
