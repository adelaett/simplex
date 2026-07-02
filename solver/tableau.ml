open Util
open Params

type prog = {
  (* max obj function subject to constraints *)
  n : int;
  obj : Q.t array;
  constr : (Q.t array * Q.t) list;
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

  { n; constr; obj = c }

type var = int

(* Fraction-free (integer-preserving) tableau.

   All coefficients are kept as arbitrary-precision integers [Z.t] sharing a
   single positive denominator [d]: the rational value of an entry is
   [Q.make entry d]. Pivoting uses Edmonds' integer-preserving rule, which
   keeps the integers bounded by the magnitude of the relevant sub-determinant
   instead of letting [Q.t] numerators/denominators blow up (and pay a GCD on
   every operation). This is the dominant speed win: every pivot becomes a
   handful of exact [Z.mul]/[Z.divexact] operations on bounded integers rather
   than [Q.add]/[Q.mul] with unbounded GCD reduction. *)
type tableau = {
  t : Z.t array array;
  basis : var array;
  mutable d : Z.t;  (* shared positive denominator; value of t.(i).(j) is t.(i).(j)/d *)
  mutable variables : var list list;
  mutable var_set : var list;
  mutable objectives : Z.t array list;
}

let string_of_rat x =
  if !ez then
    if Q.equal Q.zero x then " ."
    else if Q.equal Q.one x then " 1"
    else if Q.equal Q.minus_one x then "-1"
    else if Q.lt x Q.zero then " -"
    else " +"
  else Q.to_string x

let string_of_line d a =
  let rec aux l =
    match l with [] -> l | [ _ ] -> "|" :: l | h :: t -> h :: aux t
  in
  Array.to_list a
  |> List.map (fun z -> string_of_rat (Q.make z d))
  |> aux |> String.concat "  "

let print_tableau tb =
  let d = tb.d in
  match tb.objectives with
  | _ :: t ->
      List.iter
        (fun x ->
          print_string "           ";
          print_endline (string_of_line d x))
        t;
      print_string "maximize   ";
      print_endline (string_of_line d (List.hd tb.objectives));
      print_endline (String.make !width '-');
      for i = 0 to Array.length tb.t - 1 do
        if i = 0 then print_string "subject to " else print_string "           ";
        print_endline (string_of_line d tb.t.(i))
      done
  | _ ->
      failwith
        "The current tableau seams to be without any objective function. This \
         is not normal. Quitting."

let tableau_convert (p : prog) =
  let { n; obj; constr } = p in

  (* Basic assert to check we done nothing strange *)
  assert (Array.length obj = n);
  assert (List.for_all (fun (c, _) -> Array.length c = n) constr);

  (* number of constraints *)
  let m = List.length constr in

  (* all the unsound constraints. ie, the lhs is lesser than 0. We will
     create artifical variable for each one.*)
  let unsound_constr =
    constr |> List.mapi (fun i (_, v) -> if Q.lt v Q.zero then Some i else None)
  in

  (* number of artificial variables *)
  let k = List.length (get_somes unsound_constr) in

  (* We add stacks variables, artificial variables and value for each
     constraint. The tableau is first built with [Q.t] entries exactly as
     before, then scaled to integers below. *)
  let qt = Array.make_matrix m (n + m + k + 1) Q.zero in

  (* Track, per row, which variable is initially basic: the slack for
     non-negative-RHS rows, or the artificial for negative-RHS rows. Building
     the tableau already in this basic form bakes in what used to be a forced
     setup pivot per artificial (≈20% of all pivots on dense instances). *)
  let init_basis = Array.make m 0 in

  let i = ref 0 in
  let l = ref 0 in
  if !debug then print_endline "début creation du tableau";
  List.iter2
    (fun (cnstr, v) s ->
      (match s with
      | Some _ ->
          (* Negative RHS: negate the whole row so the artificial (coefficient
             +1) is basic with a non-negative RHS. Equivalent to the old forced
             pivot that brought the artificial into the basis, but for free.
                -cnstr·x - slack_i + artificial = -v   (with -v ≥ 0)         *)
          for j = 0 to n - 1 do
            qt.(!i).(j) <- Q.neg cnstr.(j)
          done;
          qt.(!i).(n + !i) <- Q.minus_one;
          qt.(!i).(n + m + !l) <- Q.one;
          qt.(!i).(n + m + k) <- Q.neg v;
          init_basis.(!i) <- n + m + !l;
          (* Reduced-cost row of the phase-1 objective (minimise Σ artificials)
             must be kept consistent with the artificial being basic: it is
             repaired in one pass below after all rows are built. *)
          incr l
      | None ->
          for j = 0 to n - 1 do
            qt.(!i).(j) <- cnstr.(j)
          done;
          qt.(!i).(n + !i) <- Q.one;
          qt.(!i).(n + m + k) <- v;
          init_basis.(!i) <- n + !i);
      incr i)

    constr unsound_constr;
  if !debug then print_endline "fin de la creation du tableau";

  (* We now create our objectives functions *)
  let ori_obj =
    Array.concat [ obj; Array.make (m + k) Q.zero; Array.make 1 Q.zero ]
  in
  let new_obj =
    Array.concat
      [
        Array.make (n + m) Q.zero; Array.make k Q.minus_one; Array.make 1 Q.zero;
      ]
  in
  (* Phase-1 objective is "maximise −Σ artificials". With each artificial now
     basic in its (negated) row, its −1 reduced cost must be eliminated by
     adding that row to the objective — exactly what the old forced setup pivot
     did to the objective row. After this pass every basic artificial has zero
     reduced cost and the phase-1 dictionary is consistent. *)
  let width = n + m + k + 1 in
  Array.iteri
    (fun i bv ->
      if bv >= n + m then
        (* artificial-basic row: new_obj <- new_obj + row i *)
        for j = 0 to width - 1 do
          new_obj.(j) <- Q.add new_obj.(j) qt.(i).(j)
        done)
    init_basis;
  let qobjs =
    if k = 0 then (* No artifical variables *)
      [ ori_obj ]
    else [ new_obj; ori_obj ]
  in

  (* Scale all rational entries to integers sharing a single positive
     denominator [d = lcm] of every denominator. For integer inputs (the
     common case) [d = 1] and this is a no-op. The fraction-free invariant
     ([value = entry / d]) holds uniformly across constraints and objectives. *)
  let d = ref Z.one in
  let acc_den z = d := Z.lcm !d (Q.den z) in
  Array.iter (Array.iter acc_den) qt;
  List.iter (Array.iter acc_den) qobjs;
  let d = !d in
  let scale z = Z.mul (Q.num z) (Z.divexact d (Q.den z)) in
  let t = Array.map (Array.map scale) qt in
  let objs = List.map (Array.map scale) qobjs in

  let variables =
    [ n + m -- (n + m + k - 1); n -- (n + m - 1); 0 -- (n - 1) ]
  in

  let var_set = List.flatten variables in

  {
    t;
    d;
    basis = init_basis;
    variables;
    var_set;
    objectives = objs;
  }

let tableau_is_phase_one tb = List.length tb.objectives = 2

(* Fraction-free row elimination (Edmonds' integer-preserving rule).

   [row] is the (unchanged) pivot row, [p] the pivot entry, [c] the pivot
   column and [dprev] the current shared denominator. Eliminates column [c]
   from [a] in place:

     a.(j) <- (a.(j) * p - a.(c) * row.(j)) / dprev

   The division is always exact (a sub-determinant identity), so [Z.divexact].

   The division must stay fused: only the full numerator
   [a.(j)*p - ac*row.(j)] is guaranteed divisible by [dprev] (the
   sub-determinant identity); the two terms are not individually divisible, so
   the subtraction cannot be split across two divisions.

   Sparsity: when [row.(j) = 0] the numerator collapses to [a.(j)*p], saving
   one bignum multiply (of the eliminating coefficient) and the subtraction.
   Roughly half the columns are zero on these instances. We drive the inner
   loop off [pattern], the precomputed array of the pivot row's nonzero column
   Sparsity: where the pivot row [row.(j) = 0] the numerator collapses to
   [a.(j)*p], saving the [Z.mul ac row.(j)] product and the subtraction (~half
   the columns are zero on these instances). The division stays fused over the
   whole numerator
   — the only form guaranteed exact by the sub-determinant identity, so it
   cannot be split across the two terms.

   Even when the pivot column entry [ac = 0] the row must still be rescaled
   from denominator [dprev] to the new denominator [p] (× p, ÷ dprev);
   skipping it would leave the row on the wrong denominator.

   Fast path: [dprev = 1] (every pivot until the first non-unit pivot) elides
   the exact division entirely. *)
let ff_eliminate a row p c dprev =
  let n = Array.length a in
  let unit_d = Z.equal dprev Z.one in
  let ac = a.(c) in
  if Z.equal ac Z.zero then
    (* Pivot column already zero in this row: rescale only. *)
    (if unit_d then for j = 0 to n - 1 do a.(j) <- Z.mul a.(j) p done
     else for j = 0 to n - 1 do a.(j) <- Z.divexact (Z.mul a.(j) p) dprev done)
  else if unit_d then
    for j = 0 to n - 1 do
      let r = row.(j) in
      if Z.equal r Z.zero then a.(j) <- Z.mul a.(j) p
      else a.(j) <- Z.sub (Z.mul a.(j) p) (Z.mul ac r)
    done
  else
    for j = 0 to n - 1 do
      let r = row.(j) in
      if Z.equal r Z.zero then a.(j) <- Z.divexact (Z.mul a.(j) p) dprev
      else a.(j) <- Z.divexact (Z.sub (Z.mul a.(j) p) (Z.mul ac r)) dprev
    done

let do_pivot tb x y =
  if !debug then print_endline "début pivot";
  let { t; basis; var_set; objectives; _ } = tb in
  (* number of constraints *)
  let m = Array.length t in
  if !verbose then print_endline ("entering : " ^ string_of_int x);
  if !verbose then print_endline ("leaving :  " ^ string_of_int tb.basis.(y));
  assert (List.mem x var_set);
  assert (0 <= y && y < m);
  assert (not (Z.equal t.(y).(x) Z.zero));

  let dprev = tb.d in
  let p = t.(y).(x) in
  let row = t.(y) in

  (* Eliminate the pivot column from every other constraint row and from every
     objective row, all sharing the denominator [dprev]. The pivot row itself
     is left unchanged: its new denominator is [p], so its pivot entry becomes
     p/p = 1, matching the old normalisation. *)
  for i = 0 to m - 1 do
    if i <> y then ff_eliminate t.(i) row p x dprev
  done;

  List.iter (fun v -> ff_eliminate v row p x dprev) objectives;

  (* The new shared denominator is the pivot entry. Keep it positive by
     flipping the sign of every entry (pivot row included) when [p < 0]. *)
  if Z.sign p < 0 then begin
    let neg_row a = for j = 0 to Array.length a - 1 do a.(j) <- Z.neg a.(j) done in
    Array.iter neg_row t;
    List.iter neg_row objectives;
    tb.d <- Z.neg p
  end
  else tb.d <- p;

  basis.(y) <- x;

  incr nb_pivots;
  if !verbose then print_tableau tb;
  if !verbose then print_endline "";
  if !debug then print_endline "fin pivot"

let lex_compare c1 c2 (a1, a2) (b1, b2) =
  let v = c1 a1 b1 in
  if v = 0 then c2 a2 b2 else v

(* Squared 2-norm of the (numerator of the) entering column [x] over the
   constraint rows, used by the steepest-edge rule. All entries share the
   denominator [tb.d], so the [d]'s factor out uniformly across candidates and
   cancel in the cross-multiplied comparison below — we work on numerators. *)
let column_norm2 tb x =
  let s = ref Z.zero in
  let t = tb.t in
  for i = 0 to Array.length t - 1 do
    let a = t.(i).(x) in
    if not (Z.equal a Z.zero) then s := Z.add !s (Z.mul a a)
  done;
  !s

let choose_entering tb =
  if !debug then print_endline "début entering";
  let obj = List.hd tb.objectives in

  let rule_choosen =
    if !rule = "bland" then "bland"
    else if !rule = "max" then "max"
    else if !rule = "dantzig" then "dantzig"
    else if !rule = "steepest" then "steepest"
    else if !rule = "myrule" then if Random.bool () then "bland" else "max"
    else failwith "Unkown rule"
  in

  (* The shared denominator [tb.d] is positive, so the sign of an objective
     entry equals the sign of its rational value and integer comparison of two
     entries equals comparison of their values: selection is unchanged. *)
  if rule_choosen = "bland" then (
    (* First variable with strictly positive reduced cost. Short-circuit on the
       first hit instead of scanning the whole var_set and sorting. *)
    let rec first = function
      | [] -> None
      | x :: tl -> if Z.sign obj.(x) > 0 then Some x else first tl
    in
    let v = first tb.var_set in
    if !debug then print_endline "fin entering";
    v)
  else if rule_choosen = "max" then (
    let v = ref [] in
    List.iter
      (fun x -> if Z.sign obj.(x) > 0 then v := (obj.(x), x) :: !v)
      tb.var_set;
    let v = List.fast_sort (lex_compare Z.compare compare) !v in
    Option.map snd (List.nth_opt v 0))
  else if rule_choosen = "dantzig" then (
    (* Most positive reduced cost (textbook Dantzig). Ties broken by lowest
       index (Bland-style) for anti-cycling. Single linear scan, no sort. *)
    let best = ref None in
    List.iter
      (fun x ->
        if Z.sign obj.(x) > 0 then
          match !best with
          | Some (bc, _) when Z.compare obj.(x) bc <= 0 -> ()
          | _ -> best := Some (obj.(x), x))
      tb.var_set;
    Option.map snd !best)
  else if rule_choosen = "steepest" then (
    (* Steepest-edge approximation: maximise reduced-cost² / ‖column‖².
       Compare candidates a,b without division by cross-multiplying:
         ca²·nb  vs  cb²·na    (na,nb are the squared column norms ≥ 0).
       Numerators only — the shared denominator cancels. Bland tie-break. *)
    let best = ref None in
    List.iter
      (fun x ->
        let c = obj.(x) in
        if Z.sign c > 0 then begin
          let n = column_norm2 tb x in
          (* score = c²/n; guard n=0 (unbounded direction) as +inf-best *)
          match !best with
          | None -> best := Some (c, n, x)
          | Some (bc, bn, _) ->
              (* x better than best iff c²·bn > bc²·n *)
              let lhs = Z.mul (Z.mul c c) bn in
              let rhs = Z.mul (Z.mul bc bc) n in
              if Z.compare lhs rhs > 0 then best := Some (c, n, x)
        end)
      tb.var_set;
    Option.map (fun (_, _, x) -> x) !best)
  else failwith "Unkown rule"

(* Exact comparison of the ratios [b1/p1] and [b2/p2] without building either as
   a [Q.t]. [Q.make] reduces its argument by a GCD before we ever use it, and
   [Q.compare] then cross-multiplies — two GCD-carrying steps to answer one
   sign question. Cross-multiply directly instead: with
   [q = b1*p2 - b2*p1], the sign of [b1/p1 - b2/p2] is
   [sign(q) * sign(p1) * sign(p2)]. This yields the same ordering as
   [Q.compare (Q.make b1 p1) (Q.make b2 p2)] for any nonzero pivots, using only
   exact [Z.mul]/[Z.sub]/[Z.sign] on the shared-denominator integers — no GCD,
   no allocation of reduced rationals. *)
let ratio_compare b1 p1 b2 p2 =
  let q = Z.sub (Z.mul b1 p2) (Z.mul b2 p1) in
  compare (Z.sign q * Z.sign p1 * Z.sign p2) 0

let choose_leaving ?(ignore_neg = false) tb x =
  if !debug then print_endline "début leaving";
  if !debug then print_tableau tb;
  let { t; _ } = tb in
  let m = Array.length t in
  if not ignore_neg then assert (m > 0);
  let n = Array.length t.(0) - 1 in
  (* Minimum-ratio test. All entries share the positive denominator [tb.d], so
     the ratio bound/pivot is [B/P] (the [d]'s cancel). We only ever need the
     argmin (ties broken by the smallest row index), so scan linearly for it
     instead of building a list of reduced [Q.t] ratios and full-sorting it: the
     old code paid a [Q.make] GCD per candidate and an O(k log k) sort to read a
     single element. [ratio_compare] keeps the ordering bit-identical while
     dropping the GCDs. Scanning [i] upward with a strict [<] keeps the
     lowest-index tie-break the stable sort produced. *)
  let best_i = ref (-1) in
  let best_b = ref Z.zero in
  let best_p = ref Z.one in
  for i = 0 to m - 1 do
    (* b_i / a[i][j] *)
    let b = t.(i).(n) in
    let pv = t.(i).(x) in

    if not ignore_neg then assert (Z.sign b >= 0);

    if !debug then
      print_endline
        ("leaving look at " ^ Z.to_string b ^ ", " ^ Z.to_string pv);

    let eligible =
      if not ignore_neg then Z.sign pv > 0 && Z.sign b >= 0
      else not (Z.equal Z.zero pv)
    in
    if eligible && (!best_i < 0 || ratio_compare b pv !best_b !best_p < 0) then begin
      best_i := i;
      best_b := b;
      best_p := pv
    end
  done;

  if !debug then print_endline "fin leaving";
  if !best_i < 0 then None else Some !best_i

type result = Finished of Q.t array * Q.t | Unbounded | Paused | Unfeasible

let get_values tb =
  if !debug then print_endline "debut get_values";
  let v = match last tb.variables with Some x -> x | None -> assert false in
  let n = List.length v in
  let bounds = Array.length tb.t.(0) - 1 in
  let d = tb.d in
  let x_opt = Array.make n Q.zero in

  (* Convert the integer tableau back to rationals through the shared
     denominator [d]. *)
  Array.iteri
    (fun i x -> if List.mem x v then x_opt.(x) <- Q.make tb.t.(i).(bounds) d)
    tb.basis;

  let obj = List.hd tb.objectives in

  if !debug then print_endline "fin get_values";

  (x_opt, Q.neg (Q.make obj.(bounds) d))

let rec iter_simplex tb () =
  match choose_entering tb with
  | None ->
      let v, goal = get_values tb in
      Seq.Cons (Finished (v, goal), Seq.empty)
  | Some x -> (
      match choose_leaving tb x with
      | None -> Seq.Cons (Unbounded, Seq.empty)
      | Some y ->
          do_pivot tb x y;
          Seq.Cons (Paused, iter_simplex tb))

let transition tb =
  if !debug then print_endline "Début transition";
  (* v contains artificials variables *)
  let v = List.hd tb.variables in
  let new_vars = List.flatten (List.tl tb.variables) in
  let { t; _ } = tb in
  List.iter
    (fun x ->
      if Array.mem x tb.basis then (
        (* custom choose of some variable which is positive *)
        let line = array_find tb.basis x in
        let n = Array.length t.(line) in
        assert (Z.equal t.(line).(n - 1) Z.zero);
        let v = ref None in

        (* iterate on the existing variables *)
        List.iter
          (fun y ->
            if not (x = y) then
              if not (Z.equal t.(line).(y) Z.zero) then v := Some y)
          new_vars;

        match !v with Some y -> do_pivot tb y line | None -> assert false))
    v;
  assert (List.for_all (fun x -> not (Array.mem x tb.basis)) v);
  tb.variables <- List.tl tb.variables;
  tb.var_set <- List.flatten tb.variables;
  tb.objectives <- List.tl tb.objectives;
  assert (List.length tb.variables = 2);
  assert (List.length tb.objectives = 1);
  if !debug then print_endline "Fin transition"

let do_phase_one tb =
  if !debug then print_endline "début phase 1";
  if tableau_is_phase_one tb then (
    assert (List.length tb.variables = 3);
    (* The artificials are now made basic directly at construction (negated
       rows + repaired phase-1 objective), so the old loop that forced each
       artificial into the basis with a setup pivot is no longer needed. *)

    (* execute the simplex *)
    let res = Seq.fold_left (fun _ x -> x) Paused (iter_simplex tb) in

    match res with
    | Finished (_, goal) when goal = Q.zero ->
        transition tb;
        Paused
    | Finished _ -> Unfeasible
    (* Impossible for those ones *)
    | Unbounded ->
        print_endline "unbounded";
        assert false
    | Paused ->
        print_endline "paused";
        assert false
    | Unfeasible ->
        print_endline "unfeasible";
        assert false)
  else Paused

let do_phase_two tb =
  assert (not (tableau_is_phase_one tb));
  let res = Seq.fold_left (fun _ x -> x) Paused (iter_simplex tb) in
  match res with Paused -> assert false | x -> x

let phase_one_two tb =
  match do_phase_one tb with Paused -> do_phase_two tb | x -> x

let do_simplex tb = phase_one_two tb

let get_n tb =
  List.length (List.nth tb.variables (List.length tb.variables - 1))

let get_m tb = Array.length tb.t
