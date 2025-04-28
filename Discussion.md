# Choice of third pivot rule

The maximum coefficient rule was said during the course to be quite effective, but with this rule the simplex algorithm might not always terminate.

With Bland's rule, we are sure that the algorithm always terminate.

So by combining the two rules, we obtain a rule that is better than Bland rule in most cases, while having the propriety that it always terminates : when the number of step tends to infinity, the number of consecutive bland choice tends toward $1$. This means that there is probability one to have arbitrary long consecutive Bland's choices, and thus the algorithm terminate with probability 1.


# Differences between the different rules

The different rules don't give the same number of pivots.

Bland rule always terminates.

My rule always terminates.

# Choices for interesting

I have chosen some degeneracy cases to check that my algorithm works.

# To what my algorithm is more sensitive ?

## Number of pivot complexity

It is most sensitive to the number of constraints. Indeed, each constraint adds one more variable. It also adds faces to the polyhedron. Since we move on these faces, if there is more, then there are higher chances that the algorithm takes more time.


## Step complexity

We can study the complexity for one step : there is $n*m$ operations to do the pivot. Plus $n+m$ to choose the entering and leaving variables. Hence, the complexity is $O(n*m)$.

When running test, I observed a huge difference when running big instances compared to small instance in the time required to do one step when the algorithm is advancing toward its solution. This is most likely due to the implementation of rationals : when rationals are big, there is an additional cost to run basic operations : it is no longer done in $O(1)$. After some threshold, the overhead cost is even bigger. This might be due to operations on bigger integers.

