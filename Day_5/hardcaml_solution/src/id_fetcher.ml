(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

module type Config = sig
  val id_address_size : int
end

module Make (Config : Config) = struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; max_id_idx : 'a [@bits Config.id_address_size]
      }
    [@@deriving hardcaml]
  end

  (* TODO: Figure out how to nest Read_port here. *)
  module O = struct
    type 'a t =
      { read_clock : 'a
      ; read_address : 'a [@bits Config.id_address_size]
      ; read_enable : 'a
      ; id_is_valid : 'a
      ; all_ids_fetched : 'a
      }
    [@@deriving hardcaml]
  end

  let create scope (i : _ I.t) : _ O.t =
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    (* Our reads are synchronous, so we need to wait a cycle before the first valid data comes out. *)
    let%hw first_read_is_ready = pipeline ~n:1 spec vdd in
    let open Always in
    let%hw_var id_idx = Variable.reg spec ~width:Config.id_address_size in
    let%hw_var next_id_idx = Variable.wire ~default:id_idx.value () in
    let%hw_var all_ids_fetched = Variable.reg spec ~width:1 in
    let%hw_var next_all_ids_fetched = Variable.wire ~default:all_ids_fetched.value () in
    let%hw_var max_id_idx_reg = Variable.reg spec ~width:(width i.max_id_idx) in
    let%hw_var max_id_idx_reg_is_valid = Variable.reg spec ~width:1 in
    let%hw circuit_initialized = first_read_is_ready &: max_id_idx_reg_is_valid.value in
    compile
      [ (* Could consider moving this guard to shave some gate delay, 
    but ultimately we do not want to adjust our counter until the memory is outputting valid date. *)
        when_
          circuit_initialized
          [ if_
              all_ids_fetched.value
              (* Once set, stay set until reset. *)
              [ next_all_ids_fetched <-- vdd ]
              [ if_
                  (i.enable &: (id_idx.value ==: max_id_idx_reg.value))
                  [ next_all_ids_fetched <-- vdd ]
                  [ next_all_ids_fetched <-- gnd ]
              ]
          ; when_
              (* Note that we use next_all_ids_fetched. 
              It is a cleaner equivalent to nesting another if_ above, but sidesteps adding a cycle delay from using the register. *)
              (i.enable &: ~:(next_all_ids_fetched.value))
              [ next_id_idx <-- id_idx.value +:. 1 ]
            (* Set our registers now. Split like this to avoid combinational loop. *)
          ; id_idx <-- next_id_idx.value
          ; all_ids_fetched <-- next_all_ids_fetched.value
          ]
        (* Lock in the maximum index on the first enable. 
        We use the valid signal from this in part to determine when this module has been properly initialized.  *)
      ; when_
          (i.enable &: ~:(max_id_idx_reg_is_valid.value))
          [ max_id_idx_reg <-- i.max_id_idx; max_id_idx_reg_is_valid <-- vdd ]
      ];
    (* Plumb wires to output. 
    
    We use next_id_idx for the read address because because we do not want to delay the increment by a cycle, 
    as the memory read already has a cycle delay. However, all_ids_fetched uses the register because there is a 
    cycle delay between initiating the fetch of the last ID and that read completing. *)
    (* TODO: Change id_is_valid and read_enable to support turning off the memory for power savings when not in use. *)
    { O.read_clock = i.clock
    ; read_address = next_id_idx.value
    ; read_enable = vdd
    ; id_is_valid = circuit_initialized
    ; all_ids_fetched = all_ids_fetched.value
    }
  ;;

  (* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
  let hierarchical scope =
    let module Scoped = Hierarchy.In_scope (I) (O) in
    Scoped.hierarchical ~scope ~name:"id_fetcher" create
  ;;
end
