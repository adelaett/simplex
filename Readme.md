# Simplex Algorithm Artifact Overview

## Introduction

This artifact is an implementation of the Simplex Algorithm in OCaml, developed as a homework assignment for a course. The artifact supports the claims made in the associated paper regarding the functionality and efficiency of the Simplex Algorithm. The artifact includes the implementation of the algorithm, various rules for pivot selection, and a number of tests and generators to evaluate its functionality and reusability.


## Hardware Dependencies

The artifact does not require any specific hardware and can be run on any machine that supports `OCaml` and the `opam` package manager. The required packages are `zarith`, `menhir`, and `seq`, which are available in `opam`.


## Getting Started Guide

To run the artifact on a file, use the following command:

```bash
dune build /bin/main.exe path_of_the_file
```

The artifact supports several options:

- `-help` : Print help and exit.
- `-v` : Verbose mode, print the tableau after each pivot.
- `--rule [bland|max|myrule]` : Rule for the simplex. The default is the bland rule.
- `-vv` : Debug mode. Print most of the execution of the program.
- `-q` : Quiet mode. Only print the result of the function.
- `-t` : Timing mode. Print the size of the input, and the time taken to run the algorithm.
- `-ez` : Easy printing. Print a more readable output for the tableau as fractions grow.

For more details on these options, please refer to the help text.


## Step-by-Step Instructions

To reproduce the experiments and evaluate the functionality of the artifact, follow these steps:

1. Run the artifact on the test instances provided in the `test` directory.
2. Compare the outputs with the expected results.
3. Experiment with different rules (`--rule`) and observe their impact on the algorithm's performance.

The expected outputs are the optimal solutions for the provided instances, printed in the console. If the `-t` option is used, the size of the input and the time taken to run the algorithm will also be printed.


## Reusability Guide

The core pieces of the artifact for evaluation of reusability are the Simplex Algorithm implementation and the parsing functionality.

To adapt the artifact to new inputs or use cases:

1. Modify the parser to accommodate new input formats, if necessary. The current parser is implemented using Menhir.
2. Adjust the Simplex Algorithm implementation to handle new types of constraints or objectives, if necessary.

Documentation about the core artifact can be found in the source code comments and in this README file. The main limitations to the artifact's reusability are the current lack of support for non-linear constraints and objectives, and the reliance on specific OCaml packages.
