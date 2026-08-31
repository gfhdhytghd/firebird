#ifndef OS_H
#define OS_H

#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef IS_IOS_BUILD
int iOS_is_debugger_attached();
#endif

#if (defined(_WIN32) || defined(WIN32)) && defined(__i386__)
#define OS_HAS_PAGEFAULT_HANDLER 1
#else
#define OS_HAS_PAGEFAULT_HANDLER 0
#endif
    
/* Some really crappy APIs don't use UTF-8 in fopen. */
FILE *fopen_utf8(const char *filename, const char *mode);

#if defined(__ANDROID__)
/* Returns an allocated string or NULL on failure. */
char *android_basename(const char *path);
/* KEYBOARD_TAP vibration for the current View. */
void androidVibrate();
#endif

void *os_reserve(size_t size);
void *os_alloc_executable(size_t size);
void os_free(void *ptr, size_t size);

/* W^X helpers used by the AArch64 translator. Implementations must never
 * leave a code range writable and executable at the same time. */
size_t os_page_size(void);
bool os_executable_set_writable(void *ptr, size_t size);
bool os_executable_set_executable(void *ptr, size_t size);
void os_flush_instruction_cache(void *start, void *end);

#if OS_HAS_PAGEFAULT_HANDLER
// The Win32 mechanism to handle pagefaults uses SEH, which requires a linked
// list of handlers on the stack. The frame has to stay alive on the stack and
// armed during all addr_cache accesses.

typedef struct { void *prev, *function; } os_exception_frame_t;
void os_faulthandler_arm(os_exception_frame_t *frame);
void os_faulthandler_unarm(os_exception_frame_t *frame);

void *os_commit(void *addr, size_t size);
void *os_sparse_commit(void *page, size_t size);
void os_sparse_decommit(void *page, size_t size);
#endif

void *os_map_cow(const char *filename, size_t size);
void os_unmap_cow(void *addr, size_t size);

void addr_cache_init();
void addr_cache_deinit();

#ifdef __cplusplus
}
#endif

#endif
