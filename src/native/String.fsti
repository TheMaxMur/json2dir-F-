[@@"no_prelude"]
module String
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
val is_valid_utf_8 : string -> Tot bool
val to_seq : string -> Tot (unit -> FStar.All.ML (Seq.node Char.t))
