## The book

[The Little Book Of Semaphores](https://greenteapress.com/wp/semaphores/) is available for free in PDF form.

## General notes

Julia's `Semaphore` is different from the one described in the book in that it has extra constraints:
- `Semaphore(sem_size > 0)`, i.e. you can't create a `Semaphore(0)`.
- The number of releases (signal) and acquires (wait) must match.
For this reason, we cannot implement the examples with `Semaphore` without further ado.

In Julia, most of the time you don't use a `Semaphore` directly. Instead, you can use a lock (`ReentrantLock`), which corresponds to a `Semaphore(1)`, and a `Threads.Condition` for what is done with "`Semaphore(0)`" in the book.

## Files

- `barrier.jl`: A simple barrier at which all participating tasks wait for each other before moving on.
- `producer_consumer.jl`: Producer tasks produce elements (in parallel) and independent consumer tasks process them (in parallel). Can be used/generalized for pipelining.
- `readers_writers.jl`: "Critical" section with categorical mutual exclusion of reader tasks (non-exclusive access) and writer tasks (exclusive access). The simpler case of a purely exclusive critical section is not covered because it can simply be realized with a lock.
- `dining_philosophers.jl`: Avoid circular synchronization deadlock appearing in the [Dining philosophers problem](https://en.wikipedia.org/wiki/Dining_philosophers_problem) formulated by Dijkstra.
- `h2o.jl`: U.C. Berkeley exercise in which two kinds of tasks, hydrogen and oxygen, should pair up such that they can pass a barrier as complete H₂O molecules (2 H + 1 O → H₂O).