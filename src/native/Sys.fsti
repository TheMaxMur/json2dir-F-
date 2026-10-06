[@@"no_prelude"]
module Sys
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
val argv : Array.t string
val is_directory : string -> ML bool
