
class Expr():
    pass

class Op(Expr):
    def __init__(self, op, e1, e2):
        self.op = op
        self.e1 = e1
        self.e2 = e2

    def __add__(self, other):
        pass

    def __mul__(self, other):
        pass

class Const(Expr):
    def __init__(self, v):
        pass

class Variable(Expr):
    n = 0
    def __init__(self, name):
        self.name = name
        self.iden = self.n
        self.n = self.n+1

    def __repr__(self):
        return self.name + str(self.iden)

class Constraint():
    m = 0
    def __init__(self, ):
        pass