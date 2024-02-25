%{
	open Tableau
%}

%token EOF
%token DIV
%token MINUS
%token <Z.t> NAT
%token NEWLINE


%start start
%type <Tableau.tableau> start

%%
start:
	| n=nat NEWLINE
	  m=nat NEWLINE
	  c=vector NEWLINE
	  b=vector NEWLINE
	  a=matrix ending
	  { let p = prog_make (n, m) (List.rev a) b c in
	  	tableau_convert p
	  }
;
ending:
	| EOF {}
	| NEWLINE ending {}
;

nat:
	| i=NAT { i }
;

vector:
	| x=rat          { [x] }
	| x=rat v=vector { x :: v}
;

matrix:
	| v=vector          { [v] }
	| m=matrix NEWLINE
	  v=vector          { v :: m }
;

rat:
	| p=int           { Q.of_bigint p }
	| p=int DIV q=int { Q.make p q }
;

int:
	| n=nat           { n }
	| MINUS n=nat     { Z.neg n }
;
