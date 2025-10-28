In this file, we can compare the output 

  $ ls
  lecture.in
  lecture.in.out
  test.in
  test.in.out

  $ simplex -v test.in | diff - test.in.out
  $ simplex -v lecture.in | diff - lecture.in.out

Detailed output of the different examples. This will not be present in the more complex programs.

  $ simplex lecture.in
  maximize   3  2  0  0  0  0  |  0
  --------------------------------------------------------------------------------
  subject to 3  1  1  0  0  0  |  18
             1  1  0  1  0  0  |  9
             1  0  0  0  1  0  |  7
             0  1  0  0  0  1  |  6
  The problem is FEASIBLE and BOUNDED
  One solution is x = { 9/2, 9/2 }
  The objective value for this solution is: 45/2
  The number of pivots is: 2
  The rule used: bland

  $ simplex test.in
  maximize   5  4  3  0  0  0  |  0
  --------------------------------------------------------------------------------
  subject to 2  3  1  1  0  0  |  5
             4  1  2  0  1  0  |  11
             3  4  2  0  0  1  |  8
  The problem is FEASIBLE and BOUNDED
  One solution is x = { 2, 0, 1 }
  The objective value for this solution is: 13
  The number of pivots is: 2
  The rule used: bland
