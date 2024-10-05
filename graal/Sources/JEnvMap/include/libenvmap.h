#ifndef __LIBENVMAP_H
#define __LIBENVMAP_H

#include <graal_isolate.h>


#if defined(__cplusplus)
extern "C" {
#endif

int filter_env(graal_isolatethread_t*, char*);

#if defined(__cplusplus)
}
#endif
#endif
