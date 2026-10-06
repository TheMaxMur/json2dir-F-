[@@"no_prelude"]
module Char
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
new val t : eqtype
val chr : Int.t -> ML t
val code : t -> Tot Int.t
