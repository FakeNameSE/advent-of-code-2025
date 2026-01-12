(** Control unit to fetch id ranges from memory with a single read port.

    Somewhat similar to the id_fetcher circuit, but distinct enough to be its own for now
    because this one does not need to deal with the start/stop of an enable signal and
    needs to roll over when it hits the maximum index rather than signaling that it is
    done.

    This circuit will store the max_id_range_idx when enable is first set, and use it
    until it is cleared or possibly reset. This is all the enable does.

    Note that because this assumes the memory we are controlling is synchronous, the read
    for an ID range will produce an updated value on the next clock cycle. For simplicity,
    this circuit outputs the index of the current range read out of memory in addition to
    the address of the pending read. As a result, we also have an id_is_valid output
    signal which is low until a cycle after our first read. *)

open! Core
open! Hardcaml

module type Config = sig
  val id_range_address_size : int
end

module Make (_ : Config) : sig
  module I : sig
    type 'a t =
      { clock : 'a
      ; enable : 'a
      ; clear : 'a
      ; max_id_range_idx : 'a
      }
    [@@deriving hardcaml]
  end

  module O : sig
    type 'a t =
      { read_clock : 'a
      ; read_address : 'a
      ; read_enable : 'a
      ; id_range_is_valid : 'a
      ; curr_id_range_idx : 'a
      }
    [@@deriving hardcaml]
  end

  val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
end
