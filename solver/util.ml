(** range function. From
    https://stackoverflow.com/questions/243864/what-is-the-ocaml-idiom-equivalent-to-pythons-range-function
*)
let ( -- ) i j =
  let rec aux n acc = if n < i then acc else aux (n - 1) (n :: acc) in
  aux j []

let id x = x

(** Flatten an list of options. *)
let get_somes l =
  List.fold_right (fun x l -> match x with Some i -> i :: l | None -> l) l []

(** Give the last item of a list *)
let last l = List.fold_left (fun _ x -> Some x) None l

(** [reset x] resets the reference to zero. *)
let reset x = x := 0

(** return the index of a value if the value was found *)
let array_find_opt a x =
  let index = ref None in
  Array.iteri (fun i y -> if x = y then index := Some i) a;
  !index

(** same as array_find_opt but raises an error if the value is not found. *)
let array_find a x =
  match array_find_opt a x with Some i -> i | None -> raise Not_found

(** [is_none o] returns true if [o] is [None] and false if it is [Some _]. *)
let is_none x = match x with Some _ -> false | None -> true
