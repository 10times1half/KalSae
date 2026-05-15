//
//  kswv2_toast.cpp
//  CKalsaeWV2
//
//  WinRT 토스트 알림 (Toast Notifications).
//  Windows.UI.Notifications 네임스페이스를 통해 XAML 토스트를 표시한다.
//  WinRT COM 활성화를 사용하므로 C++/WinRT 헤더가 필요하지 않다.
//

#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <roapi.h>
#include <windows.ui.notifications.h>
#include <string>
#include "kswv2_internal.h"

using namespace Microsoft::WRL;
using namespace Microsoft::WRL::Wrappers;
using namespace ABI::Windows::UI::Notifications;
using namespace ABI::Windows::Data::Xml::Dom;

// Windows Runtime 문자열 헬퍼
// HSTRING을 생성/해제하는 WRL 헬퍼.
// WinRT API는 HSTRING을 인자로 받으므로 변환이 필요하다.

/// UTF-16 와이드 문자열에서 HSTRING을 생성한다.
/// 반환된 HSTRING은 WindowsDeleteString으로 해제해야 한다.
static HRESULT MakeHString(const wchar_t *str, HSTRING *hstr) {
    if (!str || !*str) {
        *hstr = nullptr;
        return S_OK;
    }
    return WindowsCreateString(str, (UINT32)wcslen(str), hstr);
}

/// AUMID(AppUserModelID)를 설정한다.
/// 토스트 알림이 시작 메뉴 바로 가기와 연결되려면 필요하다.
extern "C" int32_t KSWV2_SetAppUserModelID(const wchar_t *aumid) {
    if (!aumid) return E_POINTER;
    // 레지스트리나 프로세스 레벨 설정은 호출자가 직접 관리한다.
    // 여기서는 단순히 성공을 반환한다.
    (void)aumid;
    return 0;
}

/// WinRT 토스트 알림을 표시한다.
/// title과 body는 선택 사항이다 (NULL 또는 빈 문자열이면 해당 <text> 요소 생략).
/// tag는 알림 취소(KSWV2_CancelToast)에 사용된다.
extern "C" int32_t KSWV2_ShowToast(
    const wchar_t *aumid,
    const wchar_t *title,
    const wchar_t *body,
    const wchar_t *tag)
{
    if (!aumid) return E_POINTER;

    // WinRT 초기화 (현재 스레드)
    HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        return static_cast<int32_t>(hr);
    }

    // XML 템플릿 생성: <toast><visual><binding template="ToastGeneric">...</binding></visual></toast>
    // Windows.UI.Notifications.ToastNotificationManager.GetTemplateContent 사용.
    // CreateToastNotifierWithId / GetTemplateContent는 base `IToastNotificationManagerStatics`
    // 의 메서드이다 (Statics2는 History/GetForUser 등이다).
    ComPtr<IToastNotificationManagerStatics> toastManager;
    hr = RoGetActivationFactory(
        HStringReference(L"Windows.UI.Notifications.ToastNotificationManager").Get(),
        IID_PPV_ARGS(&toastManager));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // ToastGeneric 템플릿 XML 가져오기.
    // 열거값 7 = ToastTemplateType::ToastGeneric (WinRT 스펙).
    // 일부 SDK 헤더버전은 `ToastTemplateType_ToastGeneric` 식별자를
    // 노출하지 않아 정수 캐스팅으로 폴백한다.
    ComPtr<IXmlDocument> xmlDoc;
    hr = toastManager->GetTemplateContent(
        static_cast<ToastTemplateType>(7), &xmlDoc);
    if (FAILED(hr) || !xmlDoc) return static_cast<int32_t>(hr);

    // XML 조작: title/body <text> 요소 추가
    ComPtr<IXmlDocumentIO> xmlIO;
    if (SUCCEEDED(xmlDoc.As(&xmlIO)) && xmlIO) {
        ComPtr<IXmlNodeSerializer> serializer;
        if (SUCCEEDED(xmlDoc.As(&serializer)) && serializer) {
            // XML 문자열 가져오기
            HSTRING xmlStr;
            if (SUCCEEDED(serializer->GetXml(&xmlStr))) {
                // 기존 XML에 <text> 요소를 추가
                // 간소화: title과 body를 <text> 요소로 추가
                std::wstring newXml = L"<toast><visual><binding template='ToastGeneric'>";
                if (title && *title) {
                    newXml += L"<text>";
                    newXml += title;
                    newXml += L"</text>";
                }
                if (body && *body) {
                    newXml += L"<text>";
                    newXml += body;
                    newXml += L"</text>";
                }
                newXml += L"</binding></visual></toast>";

                // 새 XML로 교체
                ComPtr<IXmlDocument> newDoc;
                if (SUCCEEDED(RoActivateInstance(
                        HStringReference(L"Windows.Data.Xml.Dom.XmlDocument").Get(),
                        &newDoc)) && newDoc)
                {
                    ComPtr<IXmlDocumentIO> newIO;
                    if (SUCCEEDED(newDoc.As(&newIO)) && newIO) {
                        HSTRING newXmlH;
                        if (SUCCEEDED(MakeHString(newXml.c_str(), &newXmlH))) {
                            newIO->LoadXml(newXmlH);
                            WindowsDeleteString(newXmlH);
                            xmlDoc = newDoc;
                        }
                    }
                }
                WindowsDeleteString(xmlStr);
            }
        }
    }

    // ToastNotification 생성
    ComPtr<IToastNotificationFactory> factory;
    hr = RoGetActivationFactory(
        HStringReference(L"Windows.UI.Notifications.ToastNotification").Get(),
        IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    ComPtr<IToastNotification> notification;
    hr = factory->CreateToastNotification(xmlDoc.Get(), &notification);
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 태그 설정 (선택적)
    if (tag && *tag) {
        ComPtr<IToastNotification2> notif2;
        if (SUCCEEDED(notification.As(&notif2)) && notif2) {
            HSTRING tagH;
            if (SUCCEEDED(MakeHString(tag, &tagH))) {
                notif2->put_Tag(tagH);
                WindowsDeleteString(tagH);
            }
        }
    }

    // AUMID 설정
    HSTRING aumidH;
    hr = MakeHString(aumid, &aumidH);
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // IToastNotifier 생성 (CreateToastNotifierWithId는 Statics 베이스의 메서드)
    ComPtr<IToastNotifier> notifier;
    hr = toastManager->CreateToastNotifierWithId(aumidH, &notifier);
    WindowsDeleteString(aumidH);
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    // 토스트 표시 (이 호출이 없으면 알림이 나타나지 않음)
    hr = notifier->Show(notification.Get());

    return static_cast<int32_t>(hr);
}

/// 태그로 식별되는 토스트 알림을 Action Center 기록에서 제거한다.
extern "C" int32_t KSWV2_CancelToast(
    const wchar_t *aumid,
    const wchar_t *tag)
{
    if (!aumid || !tag || !*tag) return E_INVALIDARG;

    HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        return static_cast<int32_t>(hr);
    }

    // ToastNotificationManager.history 속성 접근 (get_History는 Statics2에 있음)
    ComPtr<IToastNotificationManagerStatics2> toastManager;
    hr = RoGetActivationFactory(
        HStringReference(L"Windows.UI.Notifications.ToastNotificationManager").Get(),
        IID_PPV_ARGS(&toastManager));
    if (FAILED(hr)) return static_cast<int32_t>(hr);

    ComPtr<IToastNotificationHistory> history;
    hr = toastManager->get_History(&history);
    if (FAILED(hr) || !history) return static_cast<int32_t>(hr);

    // RemoveGroupedTagWithId (빈 그룹)
    HSTRING tagH, aumidH;
    hr = MakeHString(tag, &tagH);
    if (FAILED(hr)) return static_cast<int32_t>(hr);
    hr = MakeHString(aumid, &aumidH);
    if (FAILED(hr)) {
        WindowsDeleteString(tagH);
        return static_cast<int32_t>(hr);
    }

    // 빈 그룹 문자열
    HSTRING emptyGroup;
    WindowsCreateString(L"", 0, &emptyGroup);

    hr = history->RemoveGroupedTagWithId(tagH, emptyGroup, aumidH);

    WindowsDeleteString(emptyGroup);
    WindowsDeleteString(aumidH);
    WindowsDeleteString(tagH);

    return static_cast<int32_t>(hr);
}
