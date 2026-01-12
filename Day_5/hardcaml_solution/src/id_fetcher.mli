(** Control unit to fetch ids from memory with a single read port.

    Think of this a bit like the instruction fetching stage of a CPU, but where each
    instruction is just an ID to check. Much like x86, read_address will always point to
    the next ID to process.

    This module will store max_id_idx the first clock cycle enable is high and keep using
    this value until it clear is high (or possibly reset).

    For example, this module starts by pointing at the ID at index 0, which will be the
    next ID to check. When enable is high, this module advances to the next ID (idx 1 in
    this case). Note that because this assumes the memory we are controlling is
    synchronous, the read for that ID will produce an updated value on the next clock
    cycle. As a result, we also have an id_is_valid output signal which is low until a
    cycle after our first read. This signal being high only tells you that the memory has
    had a read_enable active long enough to be outputting a valid value. It is the user's
    responsibility to keep track of the fact that the value actually read from memory lags
    a cycle behind the last time you set enable on this module to increment the index. *)

open! Core
open! Hardcaml

module type Config = sig
  val id_address_size : int
end

module Make (_ : Config) : sig
  module I : sig
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; max_id_idx : 'a
      }
    [@@deriving hardcaml]
  end

  module O : sig
    type 'a t =
      { read_clock : 'a
      ; read_address : 'a
      ; read_enable : 'a
      ; id_is_valid : 'a
      ; all_ids_fetched : 'a
      }
    [@@deriving hardcaml]
  end

  val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
end
