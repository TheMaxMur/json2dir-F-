[@@"no_prelude"]
module Seq
open Prims
open FStar.All
noeq type node (a:Type0) =
  | Nil : node a
  | Cons : a -> (unit -> ML (node a)) -> node a
