(** An execution unit that checks if a given ID falls within any ID ranges. This design
    assumes that it is being fed a new range to check every cycle *)

open! Core
open! Hardcaml

module type Config = sig
  val id_width : int
  val id_range_address_size : int
end

module Make (_ : Config) : sig
  module Id_range : sig
    type 'a t =
      { lower : 'a [@bits Config.id_width]
      ; upper : 'a [@bits Config.id_width]
      ; idx : 'a [@bits Config.id_range_address_size]
      }
    [@@deriving hardcaml]
  end

  (* TODO: Figure out the type magic that makes this produce the right type signature. *)
  module Id_range_with_valid : With_valid.Wrap.M(Id_range).S

  module I : sig
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; id : 'a With_valid.t
      ; id_range : 'a Id_range_with_valid.t
      }
    [@@deriving hardcaml]
  end

  module O : sig
    type 'a t =
      { is_in_range : 'a With_valid.t
      ; ready : 'a
      }
    [@@deriving hardcaml]
  end

  (* val create : ~id_bit_width:int -> ~num_id_ranges:int -> Scope.t -> Signal.t I.t -> Signal.t O.t *)

  val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
end
