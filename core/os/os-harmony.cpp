#include "os.h"

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../mmu.h"

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

extern "C" FILE *fopen_utf8(const char *filename, const char *mode)
{
    return fopen(filename, mode);
}

extern "C" size_t os_page_size(void)
{
    long value = sysconf(_SC_PAGE_SIZE);
    return value > 0 ? static_cast<size_t>(value) : 4096u;
}

static bool protect_code(void *ptr, size_t size, int protection)
{
    if (!ptr || size == 0)
        return false;
    const size_t page = os_page_size();
    const uintptr_t begin = reinterpret_cast<uintptr_t>(ptr) & ~(page - 1u);
    const uintptr_t end = (reinterpret_cast<uintptr_t>(ptr) + size + page - 1u) & ~(page - 1u);
    return mprotect(reinterpret_cast<void *>(begin), end - begin, protection) == 0;
}

extern "C" void *os_reserve(size_t size)
{
    void *result = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return result == MAP_FAILED ? nullptr : result;
}

extern "C" void *os_alloc_executable(size_t size)
{
    // Allocate writable only. The translator must explicitly seal it RX.
    void *result = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return result == MAP_FAILED ? nullptr : result;
}

extern "C" bool os_executable_set_writable(void *ptr, size_t size)
{
    return protect_code(ptr, size, PROT_READ | PROT_WRITE);
}

extern "C" bool os_executable_set_executable(void *ptr, size_t size)
{
    return protect_code(ptr, size, PROT_READ | PROT_EXEC);
}

extern "C" void os_flush_instruction_cache(void *start, void *end)
{
    __builtin___clear_cache(static_cast<char *>(start), static_cast<char *>(end));
}

extern "C" void os_free(void *ptr, size_t size)
{
    if (ptr)
        munmap(ptr, size);
}

extern "C" void *os_map_cow(const char *filename, size_t size)
{
    int fd = open(filename, O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return nullptr;
    void *result = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    close(fd);
    return result == MAP_FAILED ? nullptr : result;
}

extern "C" void os_unmap_cow(void *addr, size_t size)
{
    if (addr)
        munmap(addr, size);
}

extern "C" void addr_cache_init(void)
{
    if (addr_cache)
        return;
    const size_t bytes = AC_NUM_ENTRIES * sizeof(ac_entry);
    addr_cache = static_cast<ac_entry *>(mmap(nullptr, bytes, PROT_READ | PROT_WRITE,
                                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
    if (addr_cache == MAP_FAILED) {
        addr_cache = nullptr;
        std::fprintf(stderr, "Firebird: failed to allocate address cache: %s\n", std::strerror(errno));
        return;
    }
#if !defined(AC_FLAGS)
    for (unsigned int i = 0; i < AC_NUM_ENTRIES; ++i) {
        AC_SET_ENTRY_INVALID(addr_cache[i], (i >> 1) << 10)
    }
#else
    memset(addr_cache, 0xFF, bytes);
#endif
}

extern "C" void addr_cache_deinit(void)
{
    if (addr_cache)
        munmap(addr_cache, AC_NUM_ENTRIES * sizeof(ac_entry));
    addr_cache = nullptr;
}
