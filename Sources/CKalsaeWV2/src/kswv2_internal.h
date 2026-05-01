//
//  kswv2_internal.h
//  CKalsaeWV2
//
//  Private cross-TU helpers shared by `kswv2_*.cpp`. NOT installed as a
//  public header (lives under `src/`, not `include/`). Public API and
//  Swift consumers should only see `kswv2.h`.
//

#ifndef KSWV2_INTERNAL_H
#define KSWV2_INTERNAL_H

#ifndef UNICODE
#  define UNICODE
#endif
#ifndef _UNICODE
#  define _UNICODE
#endif

#include <windows.h>
#include <WebView2.h>
#include "kswv2.h"

// 불투명 핸들 reinterpret_cast. typedef 변경 등 한 곳만 수정하면
// 모든 사용 위치를 바꿀 필요가 없도록 여기에 집중 관리한다.

static inline ICoreWebView2Environment *KSWV2_AsEnv(KSWV2Env p) {
    return reinterpret_cast<ICoreWebView2Environment *>(p);
}
static inline ICoreWebView2Controller *KSWV2_AsController(KSWV2Controller p) {
    return reinterpret_cast<ICoreWebView2Controller *>(p);
}
static inline ICoreWebView2 *KSWV2_AsWebView(KSWV2WebView p) {
    return reinterpret_cast<ICoreWebView2 *>(p);
}

#endif // KSWV2_INTERNAL_H
