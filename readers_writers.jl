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
function readers_writers(;
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

readers_writers(; nr=0, nw=10)
readers_writers(; nr=10, nw=0)
readers_writers(; nr=1, nw=1)
readers_writers(; nr=10, nw=1)
readers_writers(; nr=1, nw=10)
readers_writers(; nr=10, nw=10)

# Note that despite the (randomly) intermingled spawn order, readers always execute as a
# block. The reason is that there is no way for a writer task to (exclusively) access the
# critical region while there are readers present while more readers can enter any time.
# This could potentially lead to "starvation": If there is a infinite influx of readers,
# writing will never happen again.





# To solve the potential starvation issue above we want to add a prioritization for writers
# to the critical section mechanism: When a writer attempts to enter the critical region,
# only the readers that are already in the section may finish execution (all
# following readers have to wait). If there is currently another writer in the critical
# section, the writer trying to get access should be able to enqueue (with priority over
# potentially enqueued readers).

"""
Implements the idea of categorical mutual exclusion with prioritization. May be used to
realize a critical section that may be entered either exlusively (with priority) or
non-exclusively (i.e. by two categories of tasks). Priority means that enqueuement happens
with priority over tasks that want to access non-exclusively.

A typical example is a "readers and writers" scenario in which it is fine for multiple
readers to concurrently access the critical section but writers must have exclusive access
to the critical section (no other readers or writers may be present at the same time).
Writing would be prioritized over reading (to, e.g., avoid reading of outdated data).
"""
mutable struct CategoricalCriticalSection
    rs_allowed::Bool # readers allowed?
    const rs_allowed_cond::Threads.Condition
    ws_allowed::Bool # writers allowed?
    const ws_allowed_cond::Threads.Condition
    rcount::Int64 # reader (queue) count
    const rcount_lck::ReentrantLock
    wcount::Int64 # writer (queue) count
    const wcount_lck::ReentrantLock

    CategoricalCriticalSection() = new(true, Threads.Condition(), true, Threads.Condition(), 0, ReentrantLock(), 0, ReentrantLock())
end

# reader (i.e. non-exclusive)
function enter!(cs::CategoricalCriticalSection)
    lock(cs.rs_allowed_cond)
    try
        while !cs.rs_allowed
            wait(cs.rs_allowed_cond)
        end
        # first reader disallows writers
        lock(cs.rcount_lck) do
            cs.rcount += 1
            if cs.rcount == 1
                lock(cs.ws_allowed_cond) do
                    cs.ws_allowed = false
                end
            end
        end
    finally
        unlock(cs.rs_allowed_cond)
    end
end

# reader (i.e. non-exclusive)
function leave!(cs::CategoricalCriticalSection)
    # last reader allows writers
    lock(cs.rcount_lck) do
        cs.rcount -= 1
        if cs.rcount == 0
            lock(cs.ws_allowed_cond) do
                cs.ws_allowed = true
                notify(cs.ws_allowed_cond)
            end
        end
    end
end

# writer (i.e. exclusive)
function enter_exclusive!(cs::CategoricalCriticalSection)
    # first enqueued writer disallows readers
    lock(cs.wcount_lck) do
        cs.wcount += 1
        if cs.wcount == 1
            lock(cs.rs_allowed_cond) do
                cs.rs_allowed = false
            end
        end
    end

    lock(cs.ws_allowed_cond)
    try
        while !cs.ws_allowed
            wait(cs.ws_allowed_cond)
        end
        cs.ws_allowed = false # let only one writer pass at a time
    finally
        unlock(cs.ws_allowed_cond)
    end
end

function leave_exclusive!(cs::CategoricalCriticalSection)
    lock(cs.ws_allowed_cond) do
        cs.ws_allowed = true
        notify(cs.ws_allowed_cond)
    end
    # last writer allows readers
    lock(cs.wcount_lck) do
        cs.wcount -= 1
        if cs.wcount == 0
            lock(cs.rs_allowed_cond) do
                cs.rs_allowed = true
                notify(cs.rs_allowed_cond)
            end
        end
    end
end

function enter!(f, cs::CategoricalCriticalSection)
    enter!(cs)
    try
        f()
    finally
        leave!(cs)
    end
end

function enter_exclusive!(f, cs::CategoricalCriticalSection)
    enter_exclusive!(cs)
    try
        f()
    finally
        leave_exclusive!(cs)
    end
end





# ------ Example
function readers_writers_priority(;
    nr, # number of readers
    nw, # number of writers
)
    spawn_order = shuffle!(vcat(fill(:reader, nr), fill(:writer, nw)))
    @show spawn_order
    cs = CategoricalCriticalSection()
    @sync begin
        for s in spawn_order
            sleep(0.005) # delay spawning to "ensure" spawn/run order
            if s == :reader
                @spawn begin
                    println("reader: queuing")
                    enter!(cs) do
                        # critical section for readers
                        println("reading")
                        sleep(0.1)
                        println("reader: leaving")
                    end
                end
            else
                @spawn begin
                    println("writer: queuing")
                    enter_exclusive!(cs) do
                        # critical section for writers
                        println("writing")
                        sleep(0.1)
                        println("writer: leaving")
                    end
                end
            end
        end
    end
    nothing
end

readers_writers_priority(; nr=10, nw=0) # readers should be reading in parallel
readers_writers_priority(; nr=0, nw=10) # writers go one after another
readers_writers_priority(; nr=1, nw=1)
readers_writers_priority(; nr=10, nw=1) # readers before the writer can finish reading, then the writer gets (priority) access, finally the remaining reads can happen concurrently
readers_writers_priority(; nr=1, nw=10) # reader should be either first (if first in spawn order) or else last to enter the critical region, because writers take priority
readers_writers_priority(; nr=10, nw=10) # readers before the first writer can read (in parallel), then (most likely) all remaing reads will happen after all the writes (because writers can queue up and take priority over readers)
