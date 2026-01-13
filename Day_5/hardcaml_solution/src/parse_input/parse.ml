(* TODO: Document exceptions *)
(* TODO Explain performance benefit of fold_lines, not materializing list of lines. *)

module Parsed_input = struct
  type id = Id of int

  type id_range =
    { lower_bound : id
    ; upper_bound : id
    }

  type t =
    { bounds : id_range list
    ; ids : id list
    }
end

let is_id_in_range (Parsed_input.Id id) id_range =
  let Parsed_input.{ lower_bound = Id l; upper_bound = Id u } = id_range in
  id >= l && id <= u
;;

(* TODO: Parser breaks for ints larger than what Ocaml int can fit. 
If we are serious about parameterizing the widths, should find a solution for that. *)
let parse_input_channel ic =
  let module Local = struct
    type mode =
      | Id_range_list
      | Id_list
  end
  in
  let open Local in
  let parse_next_line ((parsed_input_acc : Parsed_input.t), (mode : mode)) (line : string)
    : Parsed_input.t * mode
    =
    match mode with
    | Id_range_list ->
      (match line with
       | "" -> parsed_input_acc, Id_list
       | non_empty_line ->
         (match String.split_on_char '-' non_empty_line with
          | [ l; u ] ->
            let lower = Parsed_input.Id (int_of_string l)
            and upper = Parsed_input.Id (int_of_string u) in
            ( { parsed_input_acc with
                bounds =
                  { lower_bound = lower; upper_bound = upper } :: parsed_input_acc.bounds
              }
            , Id_range_list )
          | _ -> failwith "Unexpected id range line."))
    | Id_list ->
      let new_id = int_of_string line in
      { parsed_input_acc with ids = Id new_id :: parsed_input_acc.ids }, Id_list
  in
  let init = { Parsed_input.bounds = []; Parsed_input.ids = [] }, Id_range_list in
  let parsed_input, _ = In_channel.fold_lines parse_next_line init ic in
  parsed_input
;;

let parse_challenge_input file_path =
  In_channel.with_open_text file_path parse_input_channel
;;
