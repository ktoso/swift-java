#ifndef __LIBENVMAP_H
#define __LIBENVMAP_H

#include <graal_isolate_dynamic.h>


#if defined(__cplusplus)
extern "C" {
#endif

typedef int (*filter_env_fn_t)(graal_isolatethread_t*, char*);

#if defined(__cplusplus)
}
#endif
#endif
