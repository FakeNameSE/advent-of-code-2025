(* After solving this part in O(n^2), cheated and skimmed someone else's more optimal O(nlog(n)) Python solution before rederiving it and implementing it here. *)
(* TODO: Describe trick of sorting ranges to  *)
let solve_part_2 (bounds : Types.bounds_list) : int =
  let[@tail_mod_cons] rec compute_minimized_bounds minimized_bounds bounds =
    match bounds with
    | [] -> minimized_bounds
    | x :: xs -> (
        let l_x, u_x = Types.ints_of_id_range x in
        match xs with
        | [] -> x :: minimized_bounds
        | y :: ys ->
            let l_y, u_y = Types.ints_of_id_range y in
            if l_y > u_x then
              compute_minimized_bounds (x :: minimized_bounds) xs
            else
              let lower_bound = Types.Id (Int.min l_x l_y)
              and upper_bound = Types.Id (Int.max u_x u_y) in
              let minimized_range : Types.id_range =
                { lower_bound; upper_bound }
              in
              compute_minimized_bounds minimized_bounds (minimized_range :: ys))
  in
  let sorted_bounds = List.fast_sort Types.compare bounds in
  let minimized_bounds = compute_minimized_bounds [] sorted_bounds in
  let sum_id_range_sizes acc id_range =
    acc + Types.get_id_range_size id_range
  in
  (List.fold_left[@tailcall]) sum_id_range_sizes 0 minimized_bounds
