  $ ls
  test01.in
  test01.in.out
  test02.in
  test02.in.out
  test03.in
  test03.in.out

  $ simplex -v test01.in | diff - test01.in.out
  $ simplex -v test02.in | diff - test02.in.out
  $ simplex -v test03.in | diff - test03.in.out
