open Simplex
open Tableau
open Util

let parse_file filename =
  let lexbuf = Lexing.from_channel (open_in filename) in
  Parser.start Lexer.token lexbuf

let vect_to_string x =
  "{ " ^ String.concat ", " (List.map Q.to_string (Array.to_list x)) ^ " }"

let output_quiet res =
  match res with
  | Unbounded -> print_endline "UNBOUNDED"
  | Finished (x, v) -> print_endline (vect_to_string x ^ " : " ^ Q.to_string v)
  | Unfeasible -> print_endline "UNFEASIBLE"
  | Paused -> assert false

let output_normal res =
  print_string "The problem is ";
  (match res with
  | Unbounded -> print_endline "FEASIBLE and UNBOUNDED"
  | Finished (x, v) ->
      print_endline "FEASIBLE and BOUNDED";

      print_string "One solution is x = ";
      print_endline (vect_to_string x);

      print_string "The objective value for this solution is: ";
      print_endline (Q.to_string v)
  | Unfeasible -> print_endline "UNFEASIBLE"
  | Paused -> assert false);

  print_string "The number of pivots is: ";
  print_int !Params.nb_pivots;
  print_endline "";

  print_string "The rule used: ";
  print_endline !Params.rule

let output_verbose = output_normal
let output_debug = output_verbose

let output res =
  if !Params.debug then output_debug res
  else if !Params.verbose then output_verbose res
  else if !Params.time then ()
  else if !Params.json then ()
  else if !Params.quiet then output_quiet res
  else output_normal res

(* JSON string escaping is trivial here since every value we emit is a number, a
   bare status word, or a rational like "51457/1485" -- none contain quotes or
   backslashes -- so a plain quote wrap is sufficient. *)
let json_status = function
  | Finished _ -> "optimal"
  | Unbounded -> "unbounded"
  | Unfeasible -> "infeasible"
  | Paused -> "paused"

(* OCaml's string_of_float renders e.g. 40. and 8e-06, both invalid JSON. Use a
   round-trippable %h-free format: %.17g gives full double precision, and we
   ensure a decimal point / exponent is always present so the token is a valid
   JSON number. *)
let json_float f = Printf.sprintf "%.17g" f

(* Emit the metrics as one JSON object on a single line. `times` are the
   per-iteration solve durations (seconds); we report their count, min and
   median so the consumer sees the distribution, not just a point. *)
let output_json ~n ~m ~res ~pivots ~times =
  let sorted = List.sort compare times in
  let arr = Array.of_list sorted in
  let k = Array.length arr in
  let tmin = if k = 0 then 0. else arr.(0) in
  let tmedian = if k = 0 then 0. else arr.(k / 2) in
  let status = json_status res in
  let value_fields =
    match res with
    | Finished (_, v) ->
        Printf.sprintf {|, "value_rat": "%s", "value": %s|}
          (Q.to_string v)
          (json_float (Q.to_float v))
    | _ -> ""
  in
  Printf.printf
    {|{"status": "%s", "rule": "%s", "n": %d, "m": %d, "pivots": %d, "trials": %d, "time_min": %s, "time_median": %s%s}|}
    status !Params.rule n m pivots k
    (json_float tmin) (json_float tmedian) value_fields;
  print_newline ()

let solve_file file_name =
  Params.handle ();
  if !Params.json then (
    (* Metrics mode: re-parse + solve `repeat` times, timing each solve in
       isolation (parse excluded), so the reported time is pure solve cost. *)
    let repeat = max 1 !Params.repeat in
    let times = ref [] in
    let last = ref None in
    let n = ref 0 and m = ref 0 and pivots = ref 0 in
    for _ = 1 to repeat do
      let tb = parse_file file_name in
      reset Params.nb_pivots;
      let st = Sys.time () in
      let res = do_simplex tb in
      let et = Sys.time () in
      times := (et -. st) :: !times;
      last := Some res;
      n := get_n tb;
      m := get_m tb;
      pivots := !Params.nb_pivots
    done;
    match !last with
    | Some res -> output_json ~n:!n ~m:!m ~res ~pivots:!pivots ~times:!times
    | None -> assert false)
  else begin
    let tb = parse_file file_name in
    reset Params.nb_pivots;
    let st = Sys.time () in
    if not !Params.quiet then print_tableau tb;
    let res = do_simplex tb in
    let et = Sys.time () in
    output res;
    if !Params.time then
      let n = get_n tb in
      let m = get_m tb in
      print_endline
        (string_of_int n ^ " " ^ string_of_int m ^ " "
        ^ string_of_float (et -. st))
  end

let speclist =
  let open Arg in
  [
    ("-v", Set Params.verbose, "verbose mode");
    ("-vv", Set Params.debug, "debug mode");
    ("-q", Set Params.quiet, "quiet mode");
    ("--rule", Set_string Params.rule, "What rule is to be used");
    ("-ez", Set Params.ez, "easy printing of tableau");
    ("-t", Set Params.time, "Show timing insted of calcul result. Imply quiet");
    ( "-json",
      Set Params.json,
      "Emit metrics (status, objective, pivots, timing) as JSON. Implies quiet."
    );
    ( "--repeat",
      Set_int Params.repeat,
      "In -json mode, re-solve this many times in-process for timing (default 1)"
    );
  ]

let usage_msg = "Simplex "

let main () =
  Random.self_init ();
  Arg.parse speclist solve_file usage_msg

let () = main ()
