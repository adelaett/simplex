all: simplex

simplex: 
	ocamlbuild -use-ocamlfind -yaccflag -v -use-menhir delaet-simplex.native -r


.PHONY: all simplex clean

clean:
	ocamlbuild -clean
