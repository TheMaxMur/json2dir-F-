[@@"no_prelude"]
module Stdlib
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
new val in_channel : Type0
val stdin : in_channel
exception End_of_file
val input_line : in_channel -> ML string
