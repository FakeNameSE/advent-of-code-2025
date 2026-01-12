open! Core
open! Hardcaml
open! Hardcaml_advent_of_code_day_5

module Top = Hardcaml_advent_of_code_day_5.Top.Make (struct
    let id_width = 64
    let id_mem_size_in_ids = 2000
    let id_range_mem_size_in_ranges = 500
    let num_execution_units = 8
  end)

let generate_top_rtl () =
  let module C = Circuit.With_interface (Top.I) (Top.O) in
  let scope = Scope.create ~auto_label_hierarchical_ports:true () in
  let circuit = C.create_exn ~name:"day_five_top" (Top.hierarchical scope) in
  let rtl_circuits =
    Rtl.create ~database:(Scope.circuit_database scope) Verilog [ circuit ]
  in
  let rtl = Rtl.full_hierarchy rtl_circuits |> Rope.to_string in
  print_endline rtl
;;

let top_rtl_command =
  Command.basic
    ~summary:""
    [%map_open.Command
      let () = return () in
      fun () -> generate_top_rtl ()]
;;

let () = Command_unix.run (Command.group ~summary:"" [ "top", top_rtl_command ])
