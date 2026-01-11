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

  (* TODO: Parameterize with a functor instead of hardcoding. *)
  let max_id_idx = 999

  let create scope (i : _ I.t) : _ O.t =
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    (* Our reads are synchronous, so we need to wait a cycle before the first valid data comes out. *)
    let%hw first_read_is_ready = pipeline ~n:1 spec vdd in
    let open Always in
    (* TODO: Parameterize number of bits for number of ids. *)
    let%hw_var id_idx = Variable.reg spec ~width:Config.id_address_size in
    let%hw_var next_id_idx = Variable.wire ~default:id_idx.value () in
    let%hw_var all_ids_fetched = Variable.reg spec ~width:1 in
    let%hw_var next_all_ids_fetched = Variable.wire ~default:all_ids_fetched.value () in
    compile
      [ (* Could consider moving this guard to shave some gate delay, 
    but ultimately we do not want to adjust our counter until the memory is outputting valid date. *)
        when_
          first_read_is_ready
          [ if_
              all_ids_fetched.value
              (* Once set, stay set until reset. *)
              [ next_all_ids_fetched <-- vdd ]
              [ if_
                  (i.enable &: (id_idx.value ==:. max_id_idx))
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
      ];
    (* Plumb wires to output. 
    
    We use next_id_idx for the read address because because we do not want to delay the increment by a cycle, 
    as the memory read already has a cycle delay. However, all_ids_fetched uses the register because there is a 
    cycle delay between initiating the fetch of the last ID and that read completing. *)
    (* TODO: Change id_is_valid and read_enable to support turning off the memory for power savings when not in use. *)
    { O.read_clock = i.clock
    ; read_address = next_id_idx.value
    ; read_enable = vdd
    ; id_is_valid = first_read_is_ready
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
