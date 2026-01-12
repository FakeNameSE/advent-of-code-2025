(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

module type Config = sig
  val id_range_address_size : int
end

module Make (Config : Config) = struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; enable : 'a
      ; clear : 'a
      ; max_id_range_idx : 'a [@bits Config.id_range_address_size]
      }
    [@@deriving hardcaml]
  end

  (* TODO: Figure out how to nest Read_port here. *)
  module O = struct
    type 'a t =
      { read_clock : 'a
      ; read_address : 'a [@bits Config.id_range_address_size]
      ; read_enable : 'a
      ; id_range_is_valid : 'a
      ; curr_id_range_idx : 'a [@bits Config.id_range_address_size]
      }
    [@@deriving hardcaml]
  end

  let create scope (i : _ I.t) : _ O.t =
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    (* Our reads are synchronous, so we need to wait a cycle before the first valid data comes out. *)
    let%hw first_read_is_ready = pipeline ~n:1 spec vdd in
    (* Doing this in the Always DSL is a little gross, but the nested if seems cleaner than messing with muxes. *)
    let open Always in
    let%hw_var id_range_idx = Variable.reg spec ~width:Config.id_range_address_size in
    let%hw_var max_id_range_idx_reg =
      Variable.reg spec ~width:Config.id_range_address_size
    in
    let%hw_var max_id_range_idx_reg_is_valid = Variable.reg spec ~width:1 in
    let%hw module_initialized =
      first_read_is_ready &: max_id_range_idx_reg_is_valid.value
    in
    compile
      [ id_range_idx <--. 0
      ; when_
          module_initialized
          [ if_
              (id_range_idx.value ==: max_id_range_idx_reg.value)
              [ id_range_idx <--. 0 ]
              [ id_range_idx <-- id_range_idx.value +:. 1 ]
          ]
      ; when_
          (i.enable &: ~:(max_id_range_idx_reg_is_valid.value))
          [ max_id_range_idx_reg <-- i.max_id_range_idx
          ; max_id_range_idx_reg_is_valid <-- vdd
          ]
      ];
    let%hw delayed_idx = pipeline ~n:1 spec id_range_idx.value in
    (* Plumb wires to output. *)
    { O.read_clock = i.clock
    ; read_address = id_range_idx.value
    ; read_enable = vdd
    ; id_range_is_valid = module_initialized
    ; curr_id_range_idx = delayed_idx
    }
  ;;

  (* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
  let hierarchical scope =
    let module Scoped = Hierarchy.In_scope (I) (O) in
    Scoped.hierarchical ~scope ~name:"id_range_fetcher" create
  ;;
end
