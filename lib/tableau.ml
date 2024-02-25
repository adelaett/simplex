open Macro;;
open Params;;

type prog = {
    (* max obj function subject to constraints *)
    n: int;
    obj: Q.t array;
    constr: (Q.t array * Q.t) list
}

let prog_make (n, m) a b c =
    (* checking dimentions in input *)
    let n = Z.to_int n in
    let m = Z.to_int m in

    assert (n > 0);
    assert (m > 0);
    assert (List.length a = m);
    (* the head exists since we veryfied m > 0*)
    assert (List.length (List.hd a) = n);
    assert (List.length b = m);
    assert (List.length c = n);

    (* checking the input is well formed (no inf or nan inside matrices) *)
    assert (List.for_all Q.is_real b);
    assert (List.for_all Q.is_real c);
    assert (List.for_all id (List.map (List.for_all Q.is_real) a));

    (* transforming to arrays *)
    let c = Array.of_list c in
    let constr = List.map2 (fun c v -> (Array.of_list c, v)) a b in

    {n=n; constr=constr; obj=c}
;;

type var = int;;

type tableau = {
    t : Q.t array array;
    basis : var array;
    mutable variables : var list list;
    mutable var_set : var list;
    mutable objectives : Q.t array list;
  }

let string_of_rat x =
  if !ez then
    if Q.equal Q.zero x then
      " ."
    else if Q.equal Q.one x then
      " 1"
    else if Q.equal Q.minus_one x then
      "-1"
    else if Q.lt x Q.zero then
      " -"
    else
      " +"
  else
    Q.to_string x
;;


let string_of_line a =
  let rec aux l =
    match l with
    | [] -> l
    | [_] -> "|" :: l
    | h :: t -> h :: (aux t)
  in
  Array.to_list a |>
  List.map string_of_rat |>
  aux |>
  String.concat "  "
;;

let print_tableau tb =
  begin match tb.objectives with
    | _::t ->
      List.iter begin fun x ->
        print_string "           ";
        print_endline (string_of_line x)
      end t;
        print_string "maximize   ";
        print_endline (string_of_line (List.hd tb.objectives));
        print_endline (String.make !width '-');
        for i = 0 to (Array.length tb.t) - 1 do
          if i = 0 then
            print_string "subject to "
          else
            print_string "           ";
          print_endline (string_of_line (tb.t.(i)))
        done
    | _ -> failwith "The current tableau seams to be without any objective function. This is not normal. Quitting."
  end
;;



let tableau_convert (p: prog) =
    let {n; obj; constr} = p in

    (* Basic assert to check we done nothing strange *)
    assert (Array.length obj = n);
    assert (List.for_all (fun (c, _) -> Array.length c = n) constr);

    (* number of constraints *)
    let m = List.length constr in

    (* all the unsound constraints. ie, the lhs is lesser than 0. We will
       create artifical variable for each one.*)
    let unsound_constr = constr |>
    List.mapi begin fun i (_, v) ->
        if Q.lt v Q.zero then
            Some i
        else
            None
    end in

    (* number of artificial variables *)

    let k = List.length (get_somes unsound_constr) in

    (* We add stacks variables, artificial variables and value for each
       constraint *)
    let t = Array.make_matrix m (n+m+k+1) Q.zero in

    let i = ref 0 in
    let l = ref 0 in
    if !debug then print_endline "début creation du tableau";
    List.iter2 begin fun (cnstr, v) s ->
        for j = 0 to n-1 do
            t.(!i).(j) <- cnstr.(j)
        done;
        t.(!i).(n + !i) <- Q.one;
        begin match s with
        | Some _ ->
            t.(!i).(n + m + !l) <- Q.minus_one;
            incr l
        | _ -> ()
        end;
        t.(!i).(n+m+k) <- v;
        incr i
    end constr unsound_constr;
    if !debug then
      print_endline "fin de la creation du tableau";


    (* We now create our objectives functions *)
    let ori_obj = Array.concat [obj; (Array.make (m+k) Q.zero); Array.make (1) Q.zero] in
    let new_obj = Array.concat [Array.make (n+m) Q.zero; Array.make (k) Q.minus_one; Array.make (1) Q.zero] in
    let objs = begin
        if k = 0 then
            (* No artifical variables *)
            [ori_obj]
        else
            [new_obj; ori_obj]
        end in

    let variables = ((n+m) -- (n+m+k-1)) :: (n -- (n+m-1)) :: (0 -- (n-1)) :: [] in

    let var_set = List.flatten variables in

    {   t = t;
        basis = Array.of_list (n -- (n+m-1));
        variables = variables;
        var_set = var_set;
        objectives = objs }
;;

let tableau_is_phase_one tb =
    List.length tb.objectives = 2

let combi_lin a b c =
    assert (Array.length a = Array.length b);
    let n = Array.length a in

    for i = 0 to (n-1) do
        a.(i) <- Q.add a.(i) (Q.mul b.(i) c)
    done
;;


let mul_lin a c =
    let n = Array.length a in

    for i = 0 to (n-1) do
        a.(i) <- Q.mul a.(i) c
    done
;;

let do_pivot tb x y =
    if !debug then
    print_endline "début pivot";
    let {t; basis; var_set; objectives; _} = tb in
    (* number of constraints *)
    let m = Array.length t in
    if !verbose then
      print_endline ("entering : " ^ (string_of_int x));
    if !verbose then
      print_endline ("leaving :  " ^ (string_of_int (tb.basis.(y))));
    assert (List.mem x var_set);
    assert (0 <= y && y < m);
    assert (not (Q.equal t.(y).(x) Q.zero) );

    mul_lin t.(y) (Q.inv t.(y).(x));

    for i=0 to m-1 do
        if i <> y then
            let ratio = Q.neg t.(i).(x) in
            combi_lin t.(i) t.(y) ratio
    done;

    List.iter begin fun v ->
        let ratio = Q.neg v.(x) in
        combi_lin v t.(y) ratio
    end objectives;

    basis.(y) <- x;

    incr nb_pivots;
    if !verbose then
      print_tableau tb;
    if !verbose then
      print_endline "";
    if !debug then
      print_endline "fin pivot";
;;

let lex_compare c1 c2 (a1, a2) (b1, b2) =
     let v = c1 a1 b1 in
     if v = 0 then
        c2 a2 b2
    else
      v
;;

let choose_entering tb =
  if !debug then print_endline "début entering";
  let obj = List.hd tb.objectives in

  let rule_choosen =
    if !rule = "bland" then "bland"
    else if !rule = "max" then "max"
    else if !rule = "myrule" then
        if Random.bool () then
            "bland"
        else
            "max"
    else failwith "Unkown rule" in

  if rule_choosen = "bland" then begin
    let v = ref None in
    List.iter
    begin fun x ->
        if (Q.gt obj.(x) Q.zero) && (is_none !v) then
            v := Some x;
    end tb.var_set;

    if !debug then  print_endline "fin entering";
    !v
  end
  else if rule_choosen = "max" then begin
    let v = ref [] in
    List.iter
      begin fun x->
        if Q.gt obj.(x) Q.zero then
          v := (obj.(x), x) :: !v
      end tb.var_set;
    let v = List.fast_sort (lex_compare Q.compare compare) !v in
    apply_opt snd (List.nth_opt v 0)
  end else
    failwith "Unkown rule"
;;



let choose_leaving ?ignore_neg:(ignore_neg=false) tb x =
  if !debug then
    print_endline "début leaving";
  if !debug then
    print_tableau tb;
    let {t; _} = tb in
    let v = ref [] in
    let m = Array.length t in
    if not ignore_neg then
        assert (m > 0);
    let n = Array.length t.(0) - 1 in
    for i = 0 to m - 1 do
        (* b_i / a[i][j] *)
        let bound = t.(i).(n) in
        let pivot = t.(i).(x) in

        if not ignore_neg then
            assert (Q.geq bound Q.zero);

        if !debug then
          print_endline ("leaving look at " ^ (Q.to_string bound) ^ ", " ^ (Q.to_string pivot));

        if (Q.lt Q.zero pivot)  && (Q.leq Q.zero bound) then
          v := (Q.div bound pivot, i) :: !v
        else if ignore_neg && (not (Q.equal Q.zero pivot)) then begin
          v := (Q.div bound pivot, i) :: !v
        end
      done;

    let v = List.fast_sort (lex_compare Q.compare compare) !v in
    if !debug then print_endline (String.concat "; " (List.map (fun (a, b) -> (Q.to_string a) ^ ", " ^ (string_of_int b)) v));
    if !debug then print_endline "fin leaving";
    apply_opt snd (List.nth_opt v 0)
;;


type result =
    | Finished of (Q.t array) * Q.t
    | Unbounded
    | Paused
    | Unfeasible


let get_values tb =
  if !debug then print_endline "debut get_values";
    let v = match last tb.variables with
        |Some x -> x
        | None -> assert false in
    let n = List.length v in
    let bounds = Array.length tb.t.(0) - 1 in
    let x_opt = Array.make n Q.zero in

    Array.iteri begin fun i x ->
        if List.mem x v then
            x_opt.(x) <- tb.t.(i).(bounds)
    end tb.basis;

    let obj = List.hd tb.objectives in

    if !debug then
      print_endline "fin get_values";

    (x_opt, Q.neg obj.(bounds))


let rec iter_simplex tb = fun () ->
    match choose_entering tb with
    | None ->
        let v, goal = get_values tb in
        Seq.Cons (Finished (v, goal), Seq.empty)
    | Some x ->
    match choose_leaving tb x with
    | None -> Seq.Cons (Unbounded, Seq.empty)
    | Some y ->
        do_pivot tb x y;
        Seq.Cons (Paused, (iter_simplex tb))
;;

let transition tb =
    if !debug then
        print_endline "Début transition";
    (* v contains artificials variables *)
    let v = List.hd tb.variables in
    let new_vars = List.flatten (List.tl tb.variables) in
    let {t; _} = tb in
    List.iter begin fun x ->
        if Array.mem x tb.basis then begin
            (* custom choose of some variable which is positive *)
            let line = array_find tb.basis x in
            let n = Array.length t.(line) in
            assert (t.(line).(n-1) = Q.zero);
            let v = ref None in

            (* iterate on the existing variables *)
            List.iter begin fun y ->
                if not (x = y) then
                    if t.(line).(y) <> Q.zero then
                        v := Some y
            end new_vars;

            match !v with
            | Some y ->
                do_pivot tb y line
            | None -> assert false
        end
    end v;
    assert (List.for_all (fun x -> not (Array.mem x tb.basis)) v);
    tb.variables <- List.tl tb.variables;
    tb.var_set <- List.flatten tb.variables;
    tb.objectives <- List.tl tb.objectives;
    assert (List.length tb.variables = 2);
    assert (List.length tb.objectives = 1);
    if !debug then print_endline "Fin transition"
;;

let do_phase_one tb =
  if !debug then print_endline "début phase 1";
    if tableau_is_phase_one tb then begin
        assert (List.length tb.variables = 3);
        let v = List.hd tb.variables in
        List.iter begin fun x ->
            match choose_leaving ~ignore_neg:true tb x with
            | Some y -> do_pivot tb x y
            | None -> assert false
        end v;

        (* execute the simplex *)
        let res = Seq.fold_left (fun _ x -> x) Paused (iter_simplex tb) in

        match res with
        | Finished (_, goal) when (goal = Q.zero)->
                transition tb;
                Paused
        | Finished _ ->
                Unfeasible
        (* Impossible for those ones *)
        | Unbounded -> print_endline "unbounded" ; assert false
        | Paused -> print_endline "paused" ; assert false
        | Unfeasible -> print_endline "unfeasible" ; assert false
    end
    else
        Paused
;;

let do_phase_two tb =
    assert (not (tableau_is_phase_one tb));
    let res = Seq.fold_left (fun _ x -> x) Paused (iter_simplex tb) in
    match res with
    | Paused ->
        assert false
    | x -> x
;;

let phase_one_two tb =
    match do_phase_one tb with
    | Paused ->
        do_phase_two tb
    | x -> x
;;

let do_simplex tb =
    phase_one_two tb
;;

let get_n tb =
  List.length (List.nth tb.variables ((List.length tb.variables )-1))
;;

let get_m tb =
  Array.length tb.t
;;
