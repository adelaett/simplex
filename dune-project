(lang dune 3.12)

(using menhir 2.0)

(name simplex)

(generate_opam_files true)

(authors "Alain Delaët")

(maintainers "Alain Delaët")

(license GPL-3.0-or-later)

(package
 (name simplex)
 (synopsis "Simplex algorithm implementation using exact computations")
 (description "Simplex algorithm implementation using exact computations")
 (depends
  ocaml
  dune
  zarith
  menhirLib
  menhir
  (ocaml-lsp-server :dev))
 (tags
  (maths or-research linear-programming)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
