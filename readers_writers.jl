using Base.Threads: @sync, @spawn
using Random: shuffle!


"""
Implements the idea of categorical mutual exclusion. May be used to realize a critical
section that may be entered either exlusively or non-exclusively
(i.e. by two categories of tasks).

A typical example is a "readers and writers" scenario
in which it is fine for multiple readers to concurrently access the critical section but
writers must have exclusive access to the critical section (no other readers or writers
may be present at the same time).
"""
mutable struct SimpleCategoricalCriticalSection
    free::Bool # no one in critical section?
    const free_cond::Threads.Condition
    cnt::Int64 # number of non-exclusive tasks attempting to enter or already in the critical section
    const cnt_lck::ReentrantLock

    SimpleCategoricalCriticalSection() = new(true, Threads.Condition(), 0, ReentrantLock())
end


function enter!(cs::SimpleCategoricalCriticalSection)
    lock(cs.cnt_lck) do
        cs.cnt += 1
        if cs.cnt == 1
            # first person marks the critical section as occupied
            lock(cs.free_cond)
            try
                while !cs.free
                    wait(cs.free_cond)
                end
                cs.free = false
            finally
                unlock(cs.free_cond)
            end
        end
    end
end

function leave!(cs::SimpleCategoricalCriticalSection)
    lock(cs.cnt_lck) do
        cs.cnt -= 1
        if cs.cnt == 0
            # last person marks the critical section as free
            lock(cs.free_cond) do
                cs.free = true
                notify(cs.free_cond)
            end
        end
    end
end

function enter!(f, cs::SimpleCategoricalCriticalSection)
    enter!(cs)
    try
        f()
    finally
        leave!(cs)
    end
end

function enter_exclusive!(cs::SimpleCategoricalCriticalSection)
    lock(cs.free_cond)
    try
        while !cs.free
            wait(cs.free_cond)
        end
        cs.free = false
    finally
        unlock(cs.free_cond)
    end
end

function leave_exclusive!(cs::SimpleCategoricalCriticalSection)
    lock(cs.free_cond) do
        cs.free = true
        notify(cs.free_cond)
    end
end

function enter_exclusive!(f, cs::SimpleCategoricalCriticalSection)
    enter_exclusive!(cs)
    try
        f()
    finally
        leave_exclusive!(cs)
    end
end





# ------ Example

function readers_writers_compact(;
    nr, # number of readers
    nw, # number of writers
)
    spawn_order = shuffle!(vcat(fill(:reader, nr), fill(:writer, nw)))
    cs = SimpleCategoricalCriticalSection()
    @sync begin
        for s in spawn_order
            if s == :reader
                @spawn enter!(cs) do
                    # critical section for readers
                    println("reading")
                    sleep(0.01)
                end
            else
                @spawn enter_exclusive!(cs) do
                    # critical section for writers
                    println("writing")
                    sleep(0.02)
                end
            end
        end
    end
    nothing
end

readers_writers_compact(; nr=0, nw=10)
readers_writers_compact(; nr=10, nw=0)
readers_writers_compact(; nr=1, nw=1)
readers_writers_compact(; nr=10, nw=1)
readers_writers_compact(; nr=1, nw=10)
readers_writers_compact(; nr=10, nw=10)

# Note that despite the (randomly) intermingled spawn order, readers always execute as a
# block. The reason is that there is no way for a writer task to (exclusively) access the
# critical region while there are readers present while more readers can enter any time.
# This could potentially lead to "starvation": If there is a infinite influx of readers,
# writing will never happen again.





# To solve the potential starvation issue above we want to add a prioritization for writers
# to the critical section mechanism: When a writer attempts to enter the critical region,
# only the readers that are already in the section may finish execution (all
# following readers have to wait).
#
#
# TODO
