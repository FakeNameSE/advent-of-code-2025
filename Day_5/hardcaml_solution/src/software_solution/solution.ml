(* TODO: Explain algorithm, complexity O(mn) *)
let solve_part_1 (parsed_input : Parse_input.Parse.Parsed_input.t) : int =
  let f acc id =
    match List.find_opt (Parse_input.Parse.is_id_in_range id) parsed_input.bounds with
    | None -> acc
    | Some _ -> acc + 1
  in
  List.fold_left f 0 parsed_input.ids
;;
