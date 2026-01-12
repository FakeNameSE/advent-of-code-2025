(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

module type Config = sig
  val id_width : int
  val id_range_address_size : int
end

module Make (Config : Config) = struct
  module Id_range = struct
    type 'a t =
      { lower : 'a [@bits Config.id_width]
      ; upper : 'a [@bits Config.id_width]
      ; idx : 'a [@bits Config.id_range_address_size]
      }
    [@@deriving hardcaml]
  end

  module Id_range_with_valid = With_valid.Wrap.Make (Id_range)

  module I = struct
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; enable : 'a
      ; id : 'a With_valid.t [@bits Config.id_width]
      ; id_range : 'a Id_range_with_valid.t
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t =
      { is_in_range : 'a With_valid.t [@bits 1]
      ; ready : 'a [@bits 1]
      }
    [@@deriving hardcaml]
  end

  module States = struct
    type t =
      | Idle
      | FirstIteration
        (* Needed to make terminating the second time we see our range idx work. *)
      | Executing
    [@@deriving sexp_of, compare ~localize, enumerate]
  end

  let create scope (i : _ I.t) : _ O.t =
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    let open Always in
    let sm =
      (* Note that the state machine defaults to initializing to the first state *)
      State_machine.create (module States) spec
    in
    (* let%hw[_var] is a shorthand that automatically applies a name to the signal, which
     will show up in waveforms. The [_var] version is used when working with the Always
     DSL. *)
    let%hw_var id = Variable.reg spec ~width:(width i.id.value) in
    let%hw_var init_range_idx = Variable.reg spec ~width:(width i.id_range.value.idx) in
    let%hw_var is_in_range = Variable.wire ~default:gnd () in
    let%hw_var is_in_range_valid = Variable.wire ~default:gnd () in
    let ready = Variable.wire ~default:gnd () in
    (* TODO: It would be great to verify formally or with property testing that ready and is_in_range_valid are never high at the same time. *)
    compile
      [ is_in_range
        <-- (id.value >=: i.id_range.value.lower &: (id.value <=: i.id_range.value.upper))
      ; sm.switch
          [ ( Idle
            , [ when_
                  (i.enable &: i.id.valid)
                  [ sm.set_next FirstIteration; id <-- i.id.value ]
              ; ready <-- vdd
              ] )
          ; ( FirstIteration (* Assumes we have at least one range to check. *)
            , [ when_
                  i.id_range.valid
                  [ init_range_idx <-- i.id_range.value.idx
                  ; if_
                      is_in_range.value
                      [ sm.set_next Idle; is_in_range_valid <-- vdd ]
                      [ sm.set_next Executing ]
                  ]
              ] )
          ; ( Executing
            , [ when_
                  i.id_range.valid
                  [ when_
                      (i.id_range.valid
                       &: (is_in_range.value
                           |: (i.id_range.value.idx ==: init_range_idx.value)))
                      [ sm.set_next Idle; is_in_range_valid <-- vdd ]
                  ]
              ] )
          ]
      ];
    (* Plumb wires to output. *)
    { is_in_range = { value = is_in_range.value; valid = is_in_range_valid.value }
    ; ready = ready.value
    }
  ;;

  (* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
  let hierarchical scope =
    let module Scoped = Hierarchy.In_scope (I) (O) in
    Scoped.hierarchical ~scope ~name:"execution_unit" create
  ;;
end
