(* TODO: Explain algorithm, complexity O(mn) *)
let solve_part_1 (parsed_input : Types.parsed_input) : int =
  let f acc (Types.Id id) =
    let is_in_range (id_range : Types.id_range) =
      let (l, u) = Types.ints_of_id_range id_range in
      if id >= l && id <= u then true
      else false
    in

    match List.find_opt is_in_range parsed_input.bounds with
    | None -> acc
    | Some _ -> acc + 1
  in
  List.fold_left f 0 parsed_input.ids

(* TODO Document why sorting works with this. *)
let rec shrink_range_against_ordered_bounds id_range bounds =
  let shrink_id_range id_range_1 id_range_2 =
    match
      (Types.ints_of_id_range id_range_1, Types.ints_of_id_range id_range_2)
    with
    | (_, u_1), (l_2, _) when u_1 < l_2 -> Some id_range_1
    | (l_1, _), (_, u_2) when l_1 > u_2 -> Some id_range_1
    | (l_1, u_1), (l_2, u_2) when l_1 >= l_2 && u_1 <= u_2 -> None
    | (l_1, u_1), (l_2, u_2) when l_1 >= l_2 && u_1 > u_2 ->
        Some { lower_bound = Id (u_2 + 1); upper_bound = Id u_1 }
    | (l_1, u_1), (l_2, u_2) when l_1 < l_2 && u_1 <= u_2 ->
        Some { lower_bound = Id l_1; upper_bound = Id (l_2 - 1) }
    | _ -> failwith "Should not happen because input is sorted"
  in
  match bounds with
  | [] -> Some id_range
  | x :: xs -> (
      match shrink_id_range id_range x with
      | None -> None
      | Some shrunken_id_range ->
          (shrink_range_against_ordered_bounds[@tailcall]) shrunken_id_range xs)

(* TODO: Prove complexity is O(n^2). *)
let[@tail_mod_cons] rec shrink_ranges bounds =
  match bounds with
  | [] -> []
  | x :: xs -> (
      match shrink_range_against_ordered_bounds x xs with
      | None -> shrink_ranges xs
      | Some shrunken_range -> shrunken_range :: shrink_ranges xs)

let solve_part_2 (bounds : Types.bounds_list) : int =
  let compare_by_interval_size (bound_1 : Types.id_range)
      (bound_2 : Types.id_range) : int =
    Int.compare
      (Types.get_id_range_size bound_1)
      (Types.get_id_range_size bound_2)
  in
  let sorted_bounds = List.fast_sort compare_by_interval_size bounds in

  let minimized_bounds = shrink_ranges sorted_bounds in
  let sum_id_range_sizes acc id_range =
    acc + Types.get_id_range_size id_range
  in
  (List.fold_left[@tailcall]) sum_id_range_sizes 0 minimized_bounds
