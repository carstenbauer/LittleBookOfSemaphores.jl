using Base.Threads: @spawn
using Random: shuffle!

# -------------- taken from barrier.jl
mutable struct SimpleBarrier
    const n::Int64
    const c::Threads.Condition
    cnt::Int64

    function SimpleBarrier(n::Integer)
        new(n, Threads.Condition(), 0)
    end
end

function Base.wait(b::SimpleBarrier)
    lock(b.c)
    try
        b.cnt += 1
        if b.cnt == b.n
            b.cnt = 0
            notify(b.c)
        else
            wait(b.c)
        end
    finally
        unlock(b.c)
    end
end
# --------------





function oxygen(; verbose=true, l, barrier, oxygen_cnt, hydrogen_cnt, two_hydrogen_cond, oxygen_cond, h2o_cnt)
    done = lock(l) do
        oxygen_cnt[] += 1
        verbose && println("O: Hi all! (Hs: ", hydrogen_cnt[], " Os: ", oxygen_cnt[], ")")

        # see if we can bond right away
        if hydrogen_cnt[] >= 2
            verbose && println("O: there are 2 H → notifying them bond")
            lock(oxygen_cond) do
                notify(oxygen_cond; all=false) # wake up a hydrogen task
                notify(oxygen_cond; all=false) # wake up another hydrogen task
            end
            # update our counters
            oxygen_cnt[] -= 1
            hydrogen_cnt[] -= 2

            # bonding
            wait(barrier)
            bond("O"; h2o_cnt)
            return true
        else
            return false
        end
    end
    if !done
        # we couldn't bond immediately
        lock(two_hydrogen_cond)
        try
            verbose && println("O: waiting for 2 H to be available")
            wait(two_hydrogen_cond)
            # bonding
            wait(barrier)
            bond("O"; h2o_cnt)
        finally
            unlock(two_hydrogen_cond)
        end
    end
end

function hydrogen(; verbose=true, l, barrier, oxygen_cnt, hydrogen_cnt, two_hydrogen_cond, oxygen_cond, h2o_cnt)
    done = lock(l) do
        hydrogen_cnt[] += 1
        verbose && println("H: Hi all! (Hs: ", hydrogen_cnt[], " Os: ", oxygen_cnt[], ")")

        # see if we can bond right away
        if hydrogen_cnt[] >= 2 && oxygen_cnt[] >= 1
            verbose && println("H: there is an O and another H → notifying them bond")
            lock(two_hydrogen_cond) do
                notify(two_hydrogen_cond; all=false) # wake up an oxygen task
            end
            lock(oxygen_cond) do
                notify(oxygen_cond; all=false) # wake up another hydrogen task
            end
            # updating counters
            hydrogen_cnt[] -= 2
            oxygen_cnt[] -= 1
            # bonding
            wait(barrier)
            bond("H"; h2o_cnt)
            return true
        else
            return false
        end
    end
    if !done
        # we couldn't bond right away
        lock(oxygen_cond)
        try
            verbose && println("H: waiting for O")
            wait(oxygen_cond)
        finally
            unlock(oxygen_cond)
        end
        wait(barrier)
        bond("H"; h2o_cnt)
    end
end

function bond(p; h2o_cnt)
    # println("$p: 2H + O → H₂O 🎉")
    if p == "O"
        h2o_cnt[] += 1
        println("2H + O → H₂O 🎉 (total count: $(h2o_cnt[]))")
    end
end

function h2o()
    # nO = 1
    # nO = 3
    nO = 10
    # nO = 100
    # nO = 500

    nH = 2 * nO # otherwise we would have hanging tasks

    # verbose = true
    verbose = false

    # spawn_order = vcat(fill(:H, nH), fill(:O, nO)) # H first
    # spawn_order = vcat(fill(:O, nO), fill(:H, nH)) # O first
    spawn_order = shuffle!(vcat(fill(:H, nH), fill(:O, nO))) # random

    barrier = SimpleBarrier(3) # bonding barrier (2 H + 1 O tasks)
    oxygen_cond = Threads.Condition() # condition that 1 O is available for bonding
    two_hydrogen_cond = Threads.Condition() # condition that 2 H are available for bonding
    l = ReentrantLock() # lock for accessing counters below
    oxygen_cnt = Ref(0) # current number of unbonded O atoms
    hydrogen_cnt = Ref(0) # current number of unbonded H atoms
    h2o_cnt = Ref(0) # total number of formed H2O molecules

    @sync begin
        println("spawning $nH hydrogen and $nO oxygen tasks")
        @show spawn_order
        for i in 1:(nH+nO)
            if spawn_order[i] == :H
                @spawn hydrogen(; verbose, l, barrier, oxygen_cnt, hydrogen_cnt, two_hydrogen_cond, oxygen_cond, h2o_cnt)
            else
                @spawn oxygen(; verbose, l, barrier, oxygen_cnt, hydrogen_cnt, two_hydrogen_cond, oxygen_cond, h2o_cnt)
            end
            sleep(0.01)
        end
    end
    nothing
end

h2o()
