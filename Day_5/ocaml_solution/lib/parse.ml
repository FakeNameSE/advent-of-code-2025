(* TODO: Document exceptions *)
(* TODO Explain performance benefit of fold_lines, not materializing list of lines. *)
let parse_input_channel ic =
  let module Local = struct
    type mode = Id_range_list | Id_list
  end in
  let open Local in
  let parse_next_line ((parsed_input_acc : Types.parsed_input), (mode : mode))
      (line : string) : Types.parsed_input * mode =
    match mode with
    | Id_range_list -> (
        match line with
        | "" -> (parsed_input_acc, Id_list)
        | non_empty_line -> (
            match String.split_on_char '-' non_empty_line with
            | [ l; u ] ->
                let lower = Types.Id (int_of_string l)
                and upper = Types.Id (int_of_string u) in
                ( {
                    parsed_input_acc with
                    bounds =
                      { lower_bound = lower; upper_bound = upper }
                      :: parsed_input_acc.bounds;
                  },
                  Id_range_list )
            | _ -> failwith "Unexpected id range line."))
    | Id_list ->
        let new_id = int_of_string line in
        ( { parsed_input_acc with ids = Id new_id :: parsed_input_acc.ids },
          Id_list )
  in
  let init = ({ Types.bounds = []; Types.ids = [] }, Id_range_list) in
  let parsed_input, _ = In_channel.fold_lines parse_next_line init ic in
  parsed_input

let parse_challenge_input file_path =
  In_channel.with_open_text file_path parse_input_channel
