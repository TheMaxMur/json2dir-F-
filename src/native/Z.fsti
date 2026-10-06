[@@"no_prelude"]
module Z
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
// F* mathematical integers are already represented by Zarith at runtime.
val to_int : int -> ML Int.t
val of_int : Int.t -> Tot int
