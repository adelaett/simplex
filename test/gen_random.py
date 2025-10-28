import math
import os
import random
from fractions import Fraction as F

def gen_matrix(n, m, gen):
    return [[gen() for i in range(n)] for i in range(m)]

def gen_vec(n, gen):
    return [gen() for i in range(n)]

def gen_lin(n, m, gen):
    a = gen_matrix(n, m, gen)
    c = gen_vec(n, gen)
    b = gen_vec(m, gen)

    return a, b, c

def print_lin(n, m, a, b, c, f):
    print(n, file=f)
    print(m, file=f)
    print(" ".join(map(str, c)), file=f)
    print(" ".join(map(str, b)), file=f)
    print("\n".join(" ".join(map(str, a[i])) for i in range(len(a))), file=f)

def test(direc, k, n, m, gen):
    # Generate k tests of size n * m in the directory direc.

    for i in range(k):
        with open(os.path.join(direc, f"test{i:02}.txt"), "w+") as f:
            m = int(1 + (3*n - 2))
            print(m)
            a, b, c = gen_lin(n, m, gen)
            print_lin(n, m, a, b, c, f)

def mapping(direc, gen):
    for n in range(5, 100, 5):
        for m in range(int(n/5), 5*n, 10):
            with open(os.path.join(direc, f"test{n:02}-{m:03}.txt"), "w+") as f:
                a, b, c = gen_lin(n, m, gen)
                print_lin(n, m, a, b, c, f)



def main():
    gen = lambda: F(random.randrange(-1000, 1000), 100)

    # test("4-random-small.t", 100, 5, 5, gen)
    # test("5-random-medium.t", 100, 20, 60, gen)
    # test("6-random-large.t", 100, 100, 300, gen)
    mapping("7-map", gen)


if __name__ == '__main__':
    main()
