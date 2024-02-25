(lang dune 3.12)

(using menhir 2.0)

(name simplex)

(generate_opam_files true)

(authors "Alain Dela\195\171t")

(maintainers "Alain Dela\195\171t")

(license GPL-3.0-or-later)

; (documentation https://url/to/documentation)

(package
 (name simplex)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends
  ocaml
  dune
  zarith
  menhirLib
  menhir
  (ocaml-lsp-server :dev))
 (tags
  (topics "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
