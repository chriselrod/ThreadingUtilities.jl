using ThreadingUtilities
using VectorizationBase, Aqua
using Test

@testset "THREADPOOL" begin
    @test isconst(ThreadingUtilities, :THREADPOOL) # test that ThreadingUtilities.THREADPOOL is a constant
    @test ThreadingUtilities.THREADPOOL isa Vector{UInt}
    @test eltype(ThreadingUtilities.THREADPOOL) === UInt
    @test length(ThreadingUtilities.THREADPOOL) == ThreadingUtilities.THREADBUFFERSIZE * (min(Threads.nthreads(),(Sys.CPU_THREADS)::Int) - 1) + (something(VectorizationBase.L₁CACHE.linesize,64) ÷ sizeof(UInt)) - 1
end

struct Copy{P} end
function (::Copy{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx,N) = ThreadingUtilities._atomic_load(p, P, 1)
    @simd ivdep for n ∈ 1:N
        vstore!(ptry, vload(ptrx, (n,)), (n,))
    end
end
@generated function copy_ptr(::A, ::B) where {A,B}
    c = Copy{Tuple{A,B,Int}}()
    quote
        @cfunction($c, Cvoid, (Ptr{UInt},))
    end
end
function setup_copy!(p, y, x)
    N = length(y)
    @assert length(x) == N
    py = stridedpointer(y)
    px = stridedpointer(x)
    fptr = copy_ptr(py, px)
    offset = ThreadingUtilities._atomic_store!(p, fptr, 0)
    ThreadingUtilities._atomic_store!(p, (py,px,N), offset)
end

@inline function launch_thread_copy!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    while true
        if ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.SPIN, ThreadingUtilities.STUP)
            setup_copy!(p, y, x)
            @assert ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.STUP, ThreadingUtilities.TASK)
            return
        elseif ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.WAIT, ThreadingUtilities.STUP)
            setup_copy!(p, y, x)
            @assert ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.STUP, ThreadingUtilities.LOCK)
            ThreadingUtilities.wake_thread!(tid % UInt)
            return
        end
        ThreadingUtilities.pause()
    end
end

function test_copy(tid)
    a = rand(100);
    b = rand(100);
    c = rand(100);
    x = similar(a) .= NaN;
    y = similar(b) .= NaN;
    z = similar(c) .= NaN;
    launch_thread_copy!(tid, x, a)
    sleep(1e-3)
    ThreadingUtilities.__wait(1)
    launch_thread_copy!(tid, y, b)
    sleep(1e-3)
    ThreadingUtilities.__wait(1)
    launch_thread_copy!(tid, z, c)
    sleep(1e-3)
    ThreadingUtilities.__wait(1)
    @test a == x
    @test b == y
    @test c == z
end

@testset "Internals" begin
    @test ThreadingUtilities._atomic_store!(pointer(UInt[]), (), 1) == 1
end

@time Aqua.test_all(ThreadingUtilities)

@testset "ThreadingUtilities.jl" begin
    foreach(test_copy, eachindex(ThreadingUtilities.TASKS))    
end
