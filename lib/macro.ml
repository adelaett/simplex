(* range function. From https://stackoverflow.com/questions/243864/what-is-the-ocaml-idiom-equivalent-to-pythons-range-function *)
let (--) i j =
    let rec aux n acc =
      if n < i then acc else aux (n-1) (n :: acc)
    in aux j []
;;

let id x = x;;

let get_somes l =
    List.fold_right begin fun x l ->
        match x with
        | Some i -> i :: l
        | None -> l
    end l []

let last l =
    List.fold_left (fun _ x -> Some x) None l
;;

let apply_opt f o =
    match o with
    | Some x -> Some (f x)
    | None -> None
;;


let reset x =
  x := 0
;;


let array_find_opt a x =
    let index = ref None in
    Array.iteri begin fun i y ->
        if x = y then
            index := Some i
    end a;
    !index
;;

let array_find a x =
    match array_find_opt a x with
    | Some i -> i
    | None ->  raise Not_found
;;


let is_none x =
  match x with
  | Some _ -> false
  | None -> true
;;
