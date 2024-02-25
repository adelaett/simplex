# Simplex implementation

Create as an homework for https://pagesperso.g-scop.grenoble-inp.fr/~bousquen/OA/index.html.

I have implemented the simplex algorithm in OCaml. I use zarith, menhir and seq packages (avalable in opam) and standard library.

## How to run an instance

to run it on a file, you have to write

   ./adelaett-exec path_of_the_file


There are several options:
	* `-help` print help and exit.
	* `-v` Verbose mode, print the tableau after each pivot
	* `--rule [bland|max|myrule]`, rule for the simplex.
		* bland is the bland rule : always take the leftmost variable with positive coefficient, and take the topmost coeficient to do the pivot.
		* max is the maximum coef rule.
		* my rule is to take at random max or bland rule. this choice is explained in the discussion file.
	  if not specified, the bland rule will be used.
	* `-vv` debug mode. Print most of the execution of the program.
	* `-q` quiet mode. only print the result of the function.
	* `-t` timing mode. print the the size of the input, and the time taken to run the algorithm.
	* `-ez` easy printing. When printing the tableau, print + for positive number, - for negative number,  -1 for minus one, 1 for one and . for zero. It's a more readble output for the tableau as fractions grows.

When running the program with more than one file, it will execute all of them one after the other.


## Organization

The source code is located in the source directory. There is no `delaet-[filename]` for each file since ocaml throw a warning when naming one file with an `-`.

Each other file starts with `delaet-`.



### Simplex

The simplex algorithm is in the file tableau.ml. This include

 * the definition of the tableau type
 * functions to manipulate an tableau
 * functions to implement the simplex

The program is well-typed and contains many assertion tests. Thoses asserts add to the time to run an instance, but are necessary to check for errors. For example before each pivot, we check that the entering and leaving variables are indeed alive variables.


#### Tableau type

For speed, the use of array of arrays (matrices) started from the begining of the project. At first, the tableau was described as exaclty this. Then, to take care of degenerency, I separated the variable description part from the objective function part.

Indeed when using part one/two algorithm, if one of the initial $b_i$ is negative, then we add an artifical variable, and change the objective function for another one. Then we apply the simplex, but, when we change our basis, we need to change both objectives functions : the old one, and the new one. This is why I have choosen to separate the objective function from the rest of the tableau.

The main tableau is an $m$ row - $n+1$ columns matrix. The last column represents the bounds, and other columns represent the coeficient for each variables. If $x$ is a variable and $i$ is a constraint, then `t[i][x]` is the coeficient of $x$ in the $i$-th constraint.


The objectives functions are represented as an list of arrays. Each items of the list is an objective function (a $c$ vector) with this current objective value. The head of this list (first element) is the current function to optimize. All element of this list are updated during each pivots.


To keep the basis at each step, I keep an array of size $m$. The item $i$ of this array contains the basis' variable associated to the constraint `i`.


In phase two, we should not select artifical variables to get inside the basis. I keep a set of alive variables when passing from the phase one to the phase two.


All this gives the following implmentation for the tableau :


```ocaml
	type tableau = {
	    t : Q.t array array;
	    basis : var array;
	    mutable variables : var list list;
	    mutable var_set : var list;
	    mutable objectives : Q.t array list;
	}
```

Where `Q.t` is the type for rationals.

#### Phase one/two

The phase one/two is implemented. Artificial variables are added at the begining, when creating the tableau. They are then removed, but not from the tableau. Insteed, they are removed from the set of alive values.


#### Parsing

I use menhir for parsing.


#### Generators

Sevral generators (in python) are avalable in the test directory. They are not documented, and to change the position of the file for example, you need to change the source code.

Some of them just don't work.

### Tests

All tests requested by the subject are in the test directory.

  0. subject : test from the subject
  1. exercices : exercices asked
  2. degenerency : degenerancy test and phase one/two tests
  4. random-small : small random instances
  5. random-medium : medium random instances
  6. random-large :  large random instance

