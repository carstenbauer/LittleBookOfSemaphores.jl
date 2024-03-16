using Base.Threads: @sync, @spawn, nthreads

"Produce `N` values and put them into `items`"
function produce!(items::Channel, N::Integer; verbose=true)
    for _ in 1:N
        item = rand(1:10)
        verbose && println("+ producer: creating item ", item)
        put!(items, item)
    end
end

"Consume values from `items`, process them, and put the result into `results`"
function consume!(results::Channel, items::Channel; verbose=true)
    for item in items # iterating over channel is parallel-safe
        verbose && println("- consumer: squaring item ", item^2)
        sleep(0.001) # fake processing time
        put!(results, item^2)
    end
end

function producer_consumer(;
    np=1,   # number of producers
    nc=3,   # number of consumers
    nel=10, # number of elements (total)
    verbose=true # toggle printing
)
    N = nel ÷ np
    # produce
    items = Channel{Int64}() do items
        @sync for _ in 1:np
            @spawn produce!(items, N; verbose)
        end
    end
    # consume
    results = Channel{Int64}(nel * np)
    @sync for _ in 1:nc
        @spawn begin
            consume!(results, items; verbose)
        end
    end
    # # Alternative (consume)
    # taskref = Ref{Task}()
    # results = Channel{Int64}(nel * np; taskref) do results
    #     @sync for c in 1:nc
    #         @spawn consume!(results, items, c; verbose)
    #     end
    # end
    # wait(taskref[])
    nothing
end

@time producer_consumer(; np=1, nc=1, nel=5, verbose=true)
@time producer_consumer(; np=2, nc=3, nel=20, verbose=true)

using BenchmarkTools
N = 100
@btime producer_consumer(; np=1, nc=1, nel=$N, verbose=false) samples = 10 evals = 3
@btime producer_consumer(; np=1, nc=nthreads(), nel=$N, verbose=false) samples = 10 evals = 3
