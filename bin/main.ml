open Simplex
open Tableau
open Macro

let parse_file filename =
  let lexbuf = Lexing.from_channel (open_in filename) in
  Parser.start Lexer.token lexbuf
;;

let vect_to_string x =
  "{ " ^ (String.concat ", " (List.map Q.to_string (Array.to_list x))) ^ " }"


let output_quiet res =
  match res with
    | Unbounded -> print_endline "UNBOUNDED"
    | Finished (x, v) -> print_endline ((vect_to_string x) ^ " : " ^ (Q.to_string v))
    | Unfeasible -> print_endline "UNFEASIBLE"
    | Paused -> assert false
;;

let output_normal res =
  print_string "The problem is ";
  begin match res with
    | Unbounded ->
      print_endline "FEASIBLE and UNBOUNDED"
  | Finished (x, v) ->
    print_endline "FEASIBLE and BOUNDED";

    print_string "One solution is x = ";
    print_endline (vect_to_string x);

    print_string "The objective value for this solution is: ";
    print_endline (Q.to_string v)

  | Unfeasible ->
    print_endline "UNFEASIBLE"

  | Paused -> assert false
  end;

  print_string "The number of pivots is: ";
  print_int !Params.nb_pivots;
  print_endline "";

  print_string "The rule used: ";
  print_endline !Params.rule
;;

let output_verbose = output_normal
;;

let output_debug = output_verbose
;;

let output res =
  if !Params.debug then
    output_debug res
  else if !Params.verbose then
    output_verbose res
  else if !Params.time then
    ()
  else if !Params.quiet then
    output_quiet res
  else
    output_normal res
;;


let solve_file file_name =
  Params.handle ();
  let tb = parse_file file_name in
  reset Params.nb_pivots;
  let st = Sys.time () in
  if not !Params.quiet then
    print_tableau tb;
  let res = do_simplex tb in
  let et = Sys.time () in
  output res;
  if !Params.time then
    let n = get_n tb in
    let m = get_m tb in
    print_endline ((string_of_int n) ^ " " ^ (string_of_int m) ^ " " ^ (string_of_float(et -. st)));
;;




let speclist =
  let open Arg in [
    "-v", Set Params.verbose, "verbose mode" ;
    "-vv", Set Params.debug, "debug mode";
    "-q", Set Params.quiet, "quiet mode";
    "--rule", Set_string Params.rule, "What rule is to be used";
    "-ez", Set Params.ez, "easy printing of tableau";
    "-t", Set Params.time, "Show timing insted of calcul result. Imply quiet"
  ]
;;

let usage_msg = "Simplex "
;;

let main () =
    Random.self_init ();
    Arg.parse speclist solve_file usage_msg


let () = main ();;
