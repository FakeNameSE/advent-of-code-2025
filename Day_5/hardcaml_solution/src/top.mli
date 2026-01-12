(** Top level module that plumbs between the various control units, execution units, and
    memories. *)

open! Core
open! Hardcaml

module type Config = sig
  val id_width : int
  val id_mem_size_in_ids : int
  val id_range_mem_size_in_ranges : int
end

module Make (_ : Config) : sig
  module I : sig
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; max_id_idx : 'a
      ; max_id_range_idx : 'a
      }
    [@@deriving hardcaml]
  end

  module O : sig
    type 'a t = { num_ids_in_range : 'a With_valid.t } [@@deriving hardcaml]
  end

  val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
end
