{
    open Z;;
    open Parser;;
    let comment_depth = ref 0;;
    let line = ref 0;;
}


rule token = parse
    | [' ' '\t']        { token lexbuf }
    | '\n'              { incr line; NEWLINE }
    | eof               { EOF }
    | '/'               { DIV }
    | '-'               { MINUS }
    | ['0' - '9']+ as s { NAT(Z.of_string s) }
    | "(*"              { incr comment_depth ; comment lexbuf}

and comment = parse
    | "(*"              { incr comment_depth; comment lexbuf}
    | "*)"              { decr comment_depth;
                          if !comment_depth = 0 then
                          token lexbuf
                          else
                          comment lexbuf }
    | _                 { comment lexbuf}
