# Return complexity


import matplotlib
import numpy as np
import matplotlib.cm as cm
import matplotlib.mlab as mlab
import matplotlib.pyplot as plt

def excute(options, filename):
    delta = 1
    X = np.arange(1, 100, delta)
    Y = np.arange(1, 300, delta)
    X, Y = np.meshgrid(X, Y)

    for x,in X:
        for y in Y:
            pass

    plt.figure()
    CS = plt.contour(X, Y, Z)
    plt.clabel(CS, inline)
