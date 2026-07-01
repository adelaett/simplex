let verbose = ref false
let quiet = ref false
let debug = ref false
let rule = ref "bland"
let width = ref 80
let time = ref false
let ez = ref false
let nb_pivots = ref 0

(* Machine-readable metrics mode: emit a single JSON object at the end and
   suppress all human-facing output. `repeat` re-runs the solve in-process so the
   reported time excludes process startup + parsing overhead. *)
let json = ref false
let repeat = ref 1

let handle () =
  verbose := !verbose || !debug;
  quiet := !quiet || !time || !json;
  rule := String.lowercase_ascii !rule
