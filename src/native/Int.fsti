[@@"no_prelude"]
module Int
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
// Native machine integers, used only at the operating system boundary.
new val t : eqtype
val logor : t -> t -> Tot t
