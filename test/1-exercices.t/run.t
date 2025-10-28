  $ ls
  fractional.in
  fractional.in.out
  lumberjack.dat
  lumberjack.dat.out
  molder.in
  molder.in.out
  student.in
  student.in.out

  $ simplex -v fractional.in | diff - fractional.in.out
  $ simplex -v lumberjack.dat | diff - lumberjack.dat.out
  $ simplex -v molder.in | diff - molder.in.out
  $ simplex -v student.in | diff - student.in.out
