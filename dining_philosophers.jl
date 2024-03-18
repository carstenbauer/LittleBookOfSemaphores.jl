using Base.Threads: @spawn
using Base: Semaphore, acquire, release

# General functions (won't be modified below)
function println_prefixed(args...; p)
    # println(repeat("\t\t", p), p, ": ", args...)
    println(p, ": ", args...)
end

function think(p)
    println_prefixed("start thinking"; p)
    sleep(0.5)
    println_prefixed("done thinking"; p)
end

function eat(p)
    println_prefixed("start eating"; p)
    sleep(1)
    println_prefixed("done eating"; p)
end

right(i) = i
left(i) = mod1(i + 1, 5)





# Non-Solution: Deadlock
function try_use_forks(f; forks, p, delay=0.1)
    lock(forks[right(p)]) do
        sleep(delay) # without delay, we might avoid the deadlock out of "luck" (different speed of different philosophers)
        lock(forks[left(p)]) do
            f()
        end
    end
end

function dining_philosophers_deadlock()
    forks = [ReentrantLock() for _ in 1:5] # 5 forks

    @sync for p in 1:5
        @spawn begin
            for _ in 1:2
                think(p)
                try_use_forks(; forks, p) do
                    eat(p)
                end
            end
        end
    end
end

dining_philosophers_deadlock()





# Solution 1: Multiplex
function try_use_forks_multiplex(f; forks, p, delay=0.1, multiplex)
    acquire(multiplex) do # ensure that only 4 philosophers are trying to use forks simultaneously
        lock(forks[right(p)]) do
            sleep(delay) # without delay, we might avoid the deadlock out of "luck" (different speed of different philosophers)
            lock(forks[left(p)]) do
                f()
            end
        end
    end
end

function dining_philosophers_multiplex()
    forks = [ReentrantLock() for _ in 1:5] # 5 forks
    multiplex = Semaphore(4) # 4 permits = only 4 philosophers allowed at a time

    @sync for p in 1:5
        @spawn begin
            for _ in 1:2
                think(p)
                try_use_forks_multiplex(; forks, p, multiplex) do
                    eat(p)
                end
            end
        end
    end
end

dining_philosophers_multiplex()





# Solution 2: Asymmetry (lefties and righties)
function try_use_forks_asymmetric(f; forks, p, delay=0.1)
    if iseven(p)
        # leftie
        lock(forks[left(p)]) do
            sleep(delay) # without delay, we might avoid the deadlock out of "luck" (different speed of different philosophers)
            lock(forks[right(p)]) do
                f()
            end
        end
    else
        # rightie
        lock(forks[right(p)]) do
            sleep(delay) # without delay, we might avoid the deadlock out of "luck" (different speed of different philosophers)
            lock(forks[left(p)]) do
                f()
            end
        end
    end
end

function dining_philosophers_asymmetric()
    forks = [ReentrantLock() for _ in 1:5] # 5 forks

    @sync for p in 1:5
        @spawn begin
            for _ in 1:2
                think(p)
                try_use_forks_asymmetric(; forks, p) do
                    eat(p)
                end
            end
        end
    end
end

dining_philosophers_asymmetric()





# Solution 3: Tanenbaum's
abstract type State end
struct Hungry <: State end
struct Thinking <: State end
struct Eating <: State end

left_neigh(p) = mod1(p - 1, 5)
right_neigh(p) = mod1(p + 1, 5)

function get_fork(; p, state, state_lck, conds)
    lock(state_lck) do
        state[p] = Hungry()
        test_can_eat(; p, state, state_lck, conds)
    end
    lock(conds[p])
    try
        while state[p] != Eating()
            wait(conds[p])
        end
    finally
        unlock(conds[p])
    end
end

function put_fork(; p, state, state_lck, conds)
    lock(state_lck) do
        state[p] = Thinking()
        test_can_eat(; p=left_neigh(p), state, state_lck, conds)
        test_can_eat(; p=right_neigh(p), state, state_lck, conds)
    end
end

function test_can_eat(; p, state, state_lck, conds)
    if state[p] == Hungry() &&
       state[left_neigh(p)] != Eating() &&
       state[right_neigh(p)] != Eating()
        lock(state_lck) do # to be safe (but task should already be holding the lock)
            state[p] = Eating()
        end
        lock(conds[p]) do
            notify(conds[p])
        end
    end
end

function try_use_forks_tanenbaum(f; kwargs...)
    get_fork(; kwargs...)
    try
        f()
    finally
        put_fork(; kwargs...)
    end
end



function dining_philosophers_tanenbaum()
    state = State[Thinking() for _ in 1:5]
    state_lck = ReentrantLock()
    conds = [Threads.Condition() for _ in 1:5]

    @sync for p in 1:5
        @spawn begin
            for _ in 1:2
                think(p)
                try_use_forks_tanenbaum(; p, state, state_lck, conds) do
                    eat(p)
                end
            end
        end
    end
end

dining_philosophers_tanenbaum()
