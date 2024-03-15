using Base.Threads: @sync, @spawn, nthreads, Condition
using Base: Semaphore, acquire, release

# Julia's Semaphore is different from the one described in the book in that it has extra
# constraints:
#     - Semaphore(sem_size > 0), i.e. you can't create a Semaphore(0).
#     - The number of releases (signal) and acquires (wait) must match.

"""
SimpleBarrier(n::Integer)

Simple reusable barrier for `n` parallel tasks.

Given `b = SimpleBarrier(n)` and `n` parallel tasks, each task that calls
`wait(b)` will block until the other `n-1` tasks have called `wait(b)` as well.

## Example
```
n = nthreads()
barrier = SimpleBarrier(n)
@sync for i in 1:n
    @spawn begin
        println("A")
        wait(barrier) # synchronize all tasks
        println("B")
        wait(barrier) # synchronize all tasks (reusable)
        println("C")
    end
end
```
"""
struct SimpleBarrier
    n::Int64
    c::Threads.Condition
    cnt::Base.RefValue{Int64}

    function SimpleBarrier(n::Integer)
        new(n, Threads.Condition(), Base.RefValue{Int64}(0))
    end
end

function Base.wait(b::SimpleBarrier)
    lock(b.c)
    try
        b.cnt[] += 1
        if b.cnt[] == b.n
            b.cnt[] = 0
            notify(b.c)
        else
            wait(b.c)
        end
    finally
        unlock(b.c)
    end
end

function simple_barrier_example()
    n = nthreads()
    barrier = SimpleBarrier(n)
    @sync for i in 1:n
        @spawn begin
            println("A")
            wait(barrier)
            println("B")
            wait(barrier)
            println("C")
        end
    end
end

simple_barrier_example()
