//
//  kswv2_internal.h
//  CKalsaeWV2
//
//  kswv2_*.cpp 파일들 사이에서 공유되는 비공개 헬퍼.
//  `include/`가 아닌 `src/` 아래에 두어 공개 헤더로 설치되지 않는다.
//  공개 API와 Swift 소비자는 `kswv2.h`만 보면 된다.
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
#include "kswv2_loader.h"

// 불투명 핸들 → 실제 COM 인터페이스 포인터로의 reinterpret_cast.
// typedef 변경 등이 발생해도 모든 사용 위치를 일괄 수정할 필요 없도록
// 이 헤더 한 곳에서 변환을 집중 관리한다.

/// KSWV2Env → ICoreWebView2Environment* 변환
static inline ICoreWebView2Environment *KSWV2_AsEnv(KSWV2Env p) {
    return reinterpret_cast<ICoreWebView2Environment *>(p);
}
/// KSWV2Controller → ICoreWebView2Controller* 변환
static inline ICoreWebView2Controller *KSWV2_AsController(KSWV2Controller p) {
    return reinterpret_cast<ICoreWebView2Controller *>(p);
}
/// KSWV2WebView → ICoreWebView2* 변환
static inline ICoreWebView2 *KSWV2_AsWebView(KSWV2WebView p) {
    return reinterpret_cast<ICoreWebView2 *>(p);
}

#endif // KSWV2_INTERNAL_H
