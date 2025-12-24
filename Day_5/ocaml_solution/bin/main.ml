let usage_msg = Printf.sprintf "%s <input file>" Sys.argv.(0)
let input_file = ref ""
let anon_fun filename = input_file := filename
let speclist = []

let () =
  Arg.parse speclist anon_fun usage_msg;

  let parsed_challenge_input =
    Ocaml_solution.Parse.parse_challenge_input !input_file
  in
  let solution_1 =
    Ocaml_solution.Naive_solution.solve_part_1 parsed_challenge_input
  and solution_2 =
    Ocaml_solution.Naive_solution.solve_part_2 parsed_challenge_input.bounds
  and solution_2_opt =
    Ocaml_solution.Optimal_solution.solve_part_2 parsed_challenge_input.bounds
  in
  Printf.printf "Answer 1: %d\nAnswer 2: %d\nAnswer 2 (opt): %d\n" solution_1 solution_2 solution_2_opt
