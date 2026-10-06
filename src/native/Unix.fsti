[@@"no_prelude"]
module Unix
open Prims
open FStar.Pervasives
open FStar.Pervasives.Native
open FStar.All
// Only the field we project is exposed. No stats record is constructed in F*.
type stats = { st_perm : Int.t }
type access_permission = | R_OK | W_OK | X_OK | F_OK
val mkdir : string -> Int.t -> ML unit
val stat : string -> ML stats
val chmod : string -> Int.t -> ML unit
val symlink : string -> string -> ML unit
val unlink : string -> ML unit
val access : string -> list access_permission -> ML unit
