[@@"no_prelude"]
module Float
open Prims
open FStar.All
new val t : Type0
val of_string : string -> ML t
val is_finite : t -> Tot bool
