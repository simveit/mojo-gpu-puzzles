from memory import UnsafePointer, stack_allocation
from gpu import thread_idx, block_idx, block_dim, barrier
from gpu.host import DeviceContext
from gpu.memory import AddressSpace
from sys import sizeof
from testing import assert_equal

# ANCHOR: dot_product
alias TPB = 8
alias SIZE = 8
alias BLOCKS_PER_GRID = (1, 1)
alias THREADS_PER_BLOCK = (SIZE, 1)
alias dtype = DType.float32


fn dot_product(
    out: UnsafePointer[Scalar[dtype]],
    a: UnsafePointer[Scalar[dtype]],
    b: UnsafePointer[Scalar[dtype]],
    size: Int,
):
    dot = stack_allocation[
        TPB, Scalar[dtype], address_space = AddressSpace.SHARED
    ]()

    global_i = block_idx.x * block_dim.x + thread_idx.x
    local_i = thread_idx.x

    if global_i < size:
        dot[local_i] = a[global_i] * b[global_i]
    barrier()

    # Reduction
    active_threads = TPB // 2
    while active_threads > 0:
        if local_i < active_threads:
            dot[local_i] += dot[local_i + active_threads]
        barrier()
        active_threads = active_threads // 2

    if local_i == 0:
        out[0] = dot[0]


# ANCHOR_END: dot_product


def main():
    with DeviceContext() as ctx:
        out = ctx.enqueue_create_buffer[dtype](1).enqueue_fill(0)
        a = ctx.enqueue_create_buffer[dtype](SIZE).enqueue_fill(0)
        b = ctx.enqueue_create_buffer[dtype](SIZE).enqueue_fill(0)
        with a.map_to_host() as a_host, b.map_to_host() as b_host:
            for i in range(SIZE):
                a_host[i] = i
                b_host[i] = i

        ctx.enqueue_function[dot_product](
            out.unsafe_ptr(),
            a.unsafe_ptr(),
            b.unsafe_ptr(),
            SIZE,
            grid_dim=BLOCKS_PER_GRID,
            block_dim=THREADS_PER_BLOCK,
        )

        expected = ctx.enqueue_create_host_buffer[dtype](1).enqueue_fill(0)

        ctx.synchronize()

        with a.map_to_host() as a_host, b.map_to_host() as b_host:
            for i in range(SIZE):
                expected[0] += a_host[i] * b_host[i]

        with out.map_to_host() as out_host:
            print("out:", out_host)
            print("expected:", expected)
            assert_equal(out_host[0], expected[0])
