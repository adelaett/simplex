let verbose = ref false
let quiet = ref false
let debug = ref false
let rule = ref "bland"
let width = ref 80
let time = ref false
let ez = ref false
let nb_pivots = ref 0

let handle () =
  verbose := !verbose || !debug;
  quiet := !quiet || !time;
  rule := String.lowercase_ascii !rule
