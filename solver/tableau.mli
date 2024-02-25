type var
type prog

val prog_make : Z.t * Z.t -> Q.t list list -> Q.t list -> Q.t list -> prog

type tableau

val tableau_convert : prog -> tableau
val print_tableau : tableau -> unit

type result = Finished of Q.t array * Q.t | Unbounded | Paused | Unfeasible

val do_simplex : tableau -> result
val get_n : tableau -> int
val get_m : tableau -> int
