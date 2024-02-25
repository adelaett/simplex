import random
def gen_binary_graph(n, m):
    # generate a graph g where there is 2n nodes and m edges.

    G = dict()
    V = []
    E = []

    for i in range(2*n):
        V.append(i)
        G[i] = []

    for _ in range(m):
        while True:
            u = 2*random.randrange(n)
            v = 2*random.randrange(n)+1

            if v in G[u] or u in G[v]:
                continue

            G[u].append(v)
            G[v].append(u)
            E.append((u, v))

            break

    return V, E

def print_bipartie_graph(V, E):
    n = len(V)
    m = len(E)

    A = [[0 for _ in range(n)] for _ in range(m)]
    B = [1 for _ in range(n)]
    C = [1 for _ in range(n)]

    for i, (u, v) in enumerate(E):
        A[i][u] = 1
        A[i][v] = 1

