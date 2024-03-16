Julia's `Semaphore` is different from the one described in the book in that it has extra constraints:
    - Semaphore(sem_size > 0), i.e. you can't create a Semaphore(0).
    - The number of releases (signal) and acquires (wait) must match.

In Julia, most of the time you don't need to use a `Semaphore` directly. Instead, you can use a lock (`ReentrantLock`), which corresponds to a `Semaphore(1)`, and a `Threads.Condition` for what is done with "`Semaphore(0)`" in the book.