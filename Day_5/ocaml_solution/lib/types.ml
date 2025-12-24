type id = Id of int
type id_range = { lower_bound : id; upper_bound : id }
type bounds_list = id_range list
type parsed_input = { bounds : id_range list; ids : id list }

(* TODO: Figure out clean way to derive these without ppx_compare which relies on Base. *)
(* TODO: Figure out how to automatically define comparison operators which use this. *)
(** Manual comparison to avoid slower and more dangerous polymorphic default.  *)
let compare (Id a) (Id b) = Int.compare a b

(* TODO: Figure out clean way to derive these without ppx_compare which relies on Base. *)
(* TODO: Figure out how to automatically define comparison operators which use this. *)
(** Manual comparison to avoid slower and more dangerous polymorphic default.  *)
let compare a b =
  match compare a.lower_bound b.lower_bound with
  | 0 -> compare a.upper_bound b.upper_bound
  | n -> n

(** Slightly hacky, used to convert ids into ints for easy manipulation.  *)
let ints_of_id_range x =
  (* TOOD: Figure out a neater way to destructure these. *)
  let (Id l) = x.lower_bound and (Id u) = x.upper_bound in
  (l, u)

let get_id_range_size id_range =
  let l, u = ints_of_id_range id_range in
  (* Id range is inclusive on both ends, so add 1. *)
  u - l + 1
