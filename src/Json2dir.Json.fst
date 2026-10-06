module Json2dir.Json

module L = FStar.List.Tot
module S = FStar.String

// Keep decoded strings as Unicode scalar values, including U+D7FF (which
// FStar.Char's current refinement accidentally excludes for construction).
type text = list nat
type json =
  | Object : list (text & json) -> json
  | Array : list json -> json
  | String : text -> json
  | Number : text -> json
  | Null : json
  | Bool : bool -> json

type result (a:Type0) =
  | Ok : a -> result a
  | Error : string -> result a

let rec whitespace (cs:text) : Tot text =
  match cs with
  | c::rest -> if c = 32 || c = 9 || c = 10 || c = 13 then whitespace rest else cs
  | [] -> cs

let digit (c:nat) : Tot bool = c >= 48 && c <= 57

let rec digits (cs:text) : Tot text =
  match cs with
  | c::rest -> if digit c then digits rest else cs
  | [] -> cs

let hex (c:nat) : Tot (option nat) =
  if c >= 48 && c <= 57 then Some (c - 48)
  else if c >= 65 && c <= 70 then Some (c - 55)
  else if c >= 97 && c <= 102 then Some (c - 87)
  else None

let hex4 (cs:text) : Tot (result (nat & text)) =
  match cs with
  | a::b::c::d::rest ->
    (match hex a, hex b, hex c, hex d with
     | Some x, Some y, Some z, Some w -> Ok (4096*x + 256*y + 16*z + w, rest)
     | _ -> Error "invalid Unicode escape")
  | _ -> Error "incomplete Unicode escape"

let unicode_escape (cs:text) : Tot (result (nat & text)) =
  match hex4 cs with
  | Error e -> Error e
  | Ok (n, rest) ->
    if n >= 0xd800 && n <= 0xdbff then
      (match rest with
       | 92::117::tail ->
         (match hex4 tail with
          | Ok (low, remaining) ->
            if low >= 0xdc00 && low <= 0xdfff
            then Ok (0x10000 + (n - 0xd800)*1024 + low - 0xdc00, remaining)
            else Error "expected low Unicode surrogate"
          | _ -> Error "expected low Unicode surrogate")
       | _ -> Error "expected low Unicode surrogate")
    else if n >= 0xdc00 && n <= 0xdfff then Error "unexpected low Unicode surrogate"
    else Ok (n, rest)

// Fuel makes termination explicit even when an escape consumes several chars.
let rec string_body (fuel:nat) (cs:text) (acc:text)
  : Tot (result (text & text)) (decreases fuel) =
  if fuel = 0 then Error "unterminated string"
  else match cs with
  | [] -> Error "unterminated string"
  | 34::rest -> Ok (L.rev acc, rest)
  | 92::e::rest ->
    let escaped =
      match e with
      | 34 | 92 | 47 -> Ok (e, rest)
      | 98 -> Ok (8, rest)
      | 102 -> Ok (12, rest)
      | 110 -> Ok (10, rest)
      | 114 -> Ok (13, rest)
      | 116 -> Ok (9, rest)
      | 117 -> unicode_escape rest
      | _ -> Error "invalid string escape"
    in
    (match escaped with
     | Error error -> Error error
     | Ok (c, remaining) -> string_body (fuel - 1) remaining (c::acc))
  | c::rest ->
    if c < 32 then Error "control character in string"
    else string_body (fuel - 1) rest (c::acc)

let parse_string (cs:text) : Tot (result (text & text)) =
  match cs with
  | 34::rest -> string_body (L.length rest + 1) rest []
  | _ -> Error "expected string"

let exponent (cs:text) : Tot (result text) =
  match cs with
  | e::rest ->
    if e = 101 || e = 69 then
      let tail : text = match rest with | s::xs -> if s = 43 || s = 45 then xs else rest | [] -> rest in
      (match tail with
       | c::_ -> if digit c then Ok (digits tail) else Error "expected exponent digits"
       | [] -> Error "expected exponent digits")
    else Ok cs
  | [] -> Ok cs

let fraction (cs:text) : Tot (result text) =
  match cs with
  | 46::rest ->
    (match rest with
     | c::_ -> if digit c then exponent (digits rest) else Error "expected fraction digits"
     | [] -> Error "expected fraction digits")
  | _ -> exponent cs

let number (cs:text) : Tot (result text) =
  let tail : text = match cs with | 45::rest -> rest | _ -> cs in
  match tail with
  | 48::rest -> fraction rest
  | c::rest -> if c >= 49 && c <= 57 then fraction (digits rest) else Error "invalid number"
  | [] -> Error "invalid number"

let rec literal (expected:text) (cs:text) : Tot (result text) =
  match expected, cs with
  | [], _ -> Ok cs
  | a::xs, b::ys -> if a = b then literal xs ys else Error "invalid literal"
  | _ -> Error "invalid literal"

let rec take (n:nat) (cs:text) : Tot text (decreases n) =
  if n = 0 then [] else match cs with
  | [] -> []
  | c::rest -> c::take (n - 1) rest

let rec value (fuel:nat) (depth:nat) (cs:text)
  : Tot (result (json & text)) (decreases fuel) =
  if fuel = 0 then Error "parser limit exceeded"
  else match whitespace cs with
  | [] -> Error "expected JSON value"
  | 123::rest ->
    if depth >= 128 then Error "JSON nesting limit exceeded"
    else (match whitespace rest with
          | 125::tail -> Ok (Object [], tail)
          | xs -> object_entries (fuel - 1) (depth + 1) xs [])
  | 91::rest ->
    if depth >= 128 then Error "JSON nesting limit exceeded"
    else (match whitespace rest with
          | 93::tail -> Ok (Array [], tail)
          | xs -> array_entries (fuel - 1) (depth + 1) xs [])
  | 34::xs ->
    (match parse_string (34::xs) with
     | Ok (s, rest) -> Ok (String s, rest)
     | Error e -> Error e)
  | 116::rest -> scalar_literal (Bool true) [114;117;101] rest
  | 102::rest -> scalar_literal (Bool false) [97;108;115;101] rest
  | 110::rest -> scalar_literal Null [117;108;108] rest
  | c::xs ->
    if c = 45 || digit c then
      (match number (c::xs) with
       | Ok rest ->
         let consumed = L.length (c::xs) - L.length rest in
         if consumed >= 0 then Ok (Number (take consumed (c::xs)), rest)
         else Error "invalid number"
       | Error e -> Error e)
    else Error "unexpected character"

and scalar_literal (v:json) (expected:text) (cs:text)
  : Tot (result (json & text)) (decreases 0) =
  match literal expected cs with
  | Ok rest -> Ok (v, rest)
  | Error e -> Error e

and object_entries (fuel:nat) (depth:nat) (cs:text) (acc:list (text & json))
  : Tot (result (json & text)) (decreases fuel) =
  if fuel = 0 then Error "parser limit exceeded"
  else match parse_string (whitespace cs) with
  | Error e -> Error e
  | Ok (key, rest) ->
    (match whitespace rest with
     | 58::tail ->
       (match value (fuel - 1) depth tail with
        | Error e -> Error e
        | Ok (v, remaining) ->
          (match whitespace remaining with
           | 125::xs -> Ok (Object (L.rev ((key,v)::acc)), xs)
           | 44::xs -> object_entries (fuel - 1) depth xs ((key,v)::acc)
           | _ -> Error "expected comma or closing brace"))
     | _ -> Error "expected colon")

and array_entries (fuel:nat) (depth:nat) (cs:text) (acc:list json)
  : Tot (result (json & text)) (decreases fuel) =
  if fuel = 0 then Error "parser limit exceeded"
  else match value (fuel - 1) depth cs with
  | Error e -> Error e
  | Ok (v, rest) ->
    (match whitespace rest with
     | 93::xs -> Ok (Array (L.rev (v::acc)), xs)
     | 44::xs -> array_entries (fuel - 1) depth xs (v::acc)
     | _ -> Error "expected comma or closing bracket")

let parse (cs:text) : Tot (result json) =
  match value (2 * L.length cs + 1) 0 cs with
  | Error e -> Error e
  | Ok (v, rest) ->
    (match whitespace rest with
     | [] -> Ok v
     | _ -> Error "trailing input")
