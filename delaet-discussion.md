# choice of third pivot rule

The maximum coeficient rule was said during the course to be quite effective, but with this rule the simplex algorithm migth not always terminate.

With the Bland rule, we are sure that the algorithm always terminate.

So by combining the two rules, we optain an rule that is better than Bland rule in most cases, while having the propriety that it always terminates : when the number of step tends to infinity, the number of consecutive bland choice tends toward 1. This means that there is probability one to have arbitrary long consecutive blands choices, and thus the algorithm terminate with probability one.


# Differences between the different rules

The different rules don't gives the same number of pivots.

Bland rule always terminates.

Myrule always terminates.

# Choices for interesting

I have choosen some degenerancy cases to check that my algorithm works.

# To what my algorithm is more sensitive ?

## Number of pivot complexity

It is most sensitive to the number of constraints. Indeed, each constraint add one more variable. It also add faces to the polyherdon. since we move on thoses faces, if there is more, then there is higher chances that the algorithm takes more time.


## Step complexity

We can study the complexity for one step : there is n*m operations to do the pivot. Plus n+m to chose the entering and leaving variables. So it's an O(n*m).

When running test, I observed an huge difference when runing big instances compared to small instance in the time required to do one step when the algorithm is advancing toward it's solution. This is most likely due to the implementation of rationnals : when rationnals are big, there is a additional cost to run basic operations : it is not longer done in O(1). After some threshold, the overhead cost is even bigger. This might be due to operations on bigger integers.

