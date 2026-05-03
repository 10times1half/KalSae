//
//  kswv2_taskbar.h
//  CKalsaeWV2
//
//  ITaskbarList3 래퍼 — C 전용 API 표면.
//  진행 상태 및 오버레이 아이콘 표시를 지원한다.
//

#ifndef KSWV2_TASKBAR_H
#define KSWV2_TASKBAR_H

#include <stdint.h>
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 작업 표시줄 진행 상태 타입.
/// Windows TBPFLAG 값과 직접 대응하지 않는다.
/// 값 0 = NOPROGRESS, 1 = INDETERMINATE, 2 = NORMAL, 3 = ERROR, 4 = PAUSED
typedef int32_t KSWV2_TaskbarState;

/// `hwnd` 윈도우의 작업 표시줄 진행 상태를 설정한다.
/// - `state`: KSWV2_TaskbarState 값.
/// - `value`: 진행률 (0 – 100). `state == 0 || state == 1`이면 무시된다.
/// 반환: S_OK(0) 성공, 그 외 HRESULT 오류 코드.
int32_t KSWV2_SetTaskbarProgress(HWND hwnd, KSWV2_TaskbarState state, uint32_t value);

/// `hwnd` 윈도우의 작업 표시줄 오버레이 아이콘을 설정/해제한다.
/// - `iconPath`: 아이콘 파일(.ico) 경로. NULL이면 기존 오버레이를 제거한다.
/// - `description`: 접근성 설명 문자열. NULL 가능.
/// 반환: S_OK(0) 성공, 그 외 HRESULT 오류 코드.
int32_t KSWV2_SetOverlayIcon(HWND hwnd, const wchar_t *iconPath, const wchar_t *description);

#ifdef __cplusplus
}
#endif

#endif // KSWV2_TASKBAR_H
