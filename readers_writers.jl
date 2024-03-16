using Base.Threads: @sync, @spawn, nthreads, Condition

function readers_writers(;
    nr=1, # number of readers
    nw=1  # number of writers
)
    readers = 0 # how many readers are currently in the critical section ("room")
    readers_lck = ReentrantLock()
    room_empty = true
    room_empty_cond = Condition() # is the room empty?

    @sync begin
        # readers
        println("spawning readers")
        for _ in 1:nr
            @spawn begin
                lock(readers_lck) do
                    readers += 1
                    if readers == 1
                        # first reader marks room as non-empty or waits (and blocks all
                        # other readers)
                        lock(room_empty_cond) do
                            if room_empty
                                room_empty = false
                            else
                                try
                                    while !room_empty
                                        wait(room_empty_cond)
                                    end
                                finally
                                    unlock(room_empty_cond)
                                end
                            end
                        end
                    end
                end

                # critical section for readers
                println("reading (current readers: $readers)")
                sleep(1)

                lock(readers_lck) do
                    readers -= 1
                    if readers == 0
                        # last reader marks room as empty
                        lock(room_empty_cond) do
                            room_empty = true
                            notify(room_empty_cond)
                        end
                    end
                end
            end
        end
        # writers
        println("spawning writers")
        for _ in 1:nw
            @spawn begin
                lock(room_empty_cond)
                try
                    while !room_empty
                        wait(room_empty_cond)
                    end
                    room_empty = false
                finally
                    unlock(room_empty_cond)
                end

                # critical section for writers
                println("writing (current readers: $readers)")
                sleep(0.01)

                lock(room_empty_cond) do
                    room_empty = true
                    notify(room_empty_cond)
                end
            end
        end
    end
    nothing
end

readers_writers(; nr=1, nw=1)
readers_writers(; nr=10, nw=2)
readers_writers(; nr=10, nw=10)

# ------------ Outsource logic to a new type

mutable struct CriticalSection
    free::Bool # no one in critical section?
    const free_cond::Threads.Condition
    cnt::Int64 # number of tasks in the room
    const cnt_lck::ReentrantLock

    CriticalSection() = new(true, Threads.Condition(), 0, ReentrantLock())
end

function getcount(ls::CriticalSection)
    lock(ls.cnt_lck) do
        ls.cnt
    end
end

function enter_critical!(ls::CriticalSection)
    lock(ls.cnt_lck) do
        ls.cnt += 1
        if ls.cnt == 1
            # first person marks the critical section as occupied
            lock(ls.free_cond)
            try
                while !ls.free
                    wait(ls.free_cond)
                end
                ls.free = false
            finally
                unlock(ls.free_cond)
            end
        end
        ls.cnt
    end
end

function leave_critical!(ls::CriticalSection)
    lock(ls.cnt_lck) do
        ls.cnt -= 1
        if ls.cnt == 0
            # last person marks the critical section as free
            lock(ls.free_cond) do
                ls.free = true
                notify(ls.free_cond)
            end
        end
        ls.cnt
    end
end

function enter_critical_exclusive!(ls::CriticalSection)
    lock(ls.free_cond)
    try
        while !ls.free
            wait(ls.free_cond)
        end
        ls.free = false
    finally
        unlock(ls.free_cond)
    end
    ls.cnt
end

function leave_critical_exclusive!(ls::CriticalSection)
    lock(ls.free_cond) do
        ls.free = true
        c = ls.cnt
        notify(ls.free_cond)
        c
    end
end


function readers_writers_compact(;
    nr, # number of readers
    nw, # number of writers
)
    ls = CriticalSection()
    @sync begin
        # readers
        for _ in 1:nr
            @spawn begin
                cnt = enter_critical!(ls)
                # critical section for readers
                println("reading (num. tasks in critical: $(cnt))")
                sleep(1)
                leave_critical!(ls)
            end
        end
        # writers
        for _ in 1:nw
            @spawn begin
                cnt = enter_critical_exclusive!(ls)
                # critical section for writers
                println("writing (num. tasks in critical: $(cnt))")
                sleep(0.01)
                leave_critical_exclusive!(ls)
            end
        end
    end
    nothing
end

readers_writers_compact(; nr=1, nw=1)
readers_writers_compact(; nr=10, nw=2)
readers_writers_compact(; nr=10, nw=10)
