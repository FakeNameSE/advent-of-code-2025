module Parsed_input : sig
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

val is_id_in_range : Parsed_input.id -> Parsed_input.id_range -> bool 

val parse_input_channel : in_channel -> Parsed_input.t

(** Takes file path to input file as string. *)
val parse_challenge_input : string -> Parsed_input.t
