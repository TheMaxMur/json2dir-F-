[@@"no_prelude"]
module Buffer
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
new val t : Type0
val create : Int.t -> ML t
val add_char : t -> Char.t -> ML unit
val add_string : t -> string -> ML unit
val contents : t -> ML string
