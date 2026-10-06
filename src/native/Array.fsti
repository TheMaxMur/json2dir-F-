[@@"no_prelude"]
module Array
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
new val t (a:Type0) : Type0
val to_list : #a:Type0 -> t a -> Tot (list a)
