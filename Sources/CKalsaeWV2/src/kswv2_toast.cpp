//
//  kswv2_toast.cpp
//  CKalsaeWV2
//
//  Windows.UI.Notifications XAML toasts via classic COM activation
//  (RoGetActivationFactory). C++/WinRT not required — works on every
//  Win10+ SDK. Successful display requires the calling process to have
//  registered an AppUserModelID and a Start-Menu shortcut.
//

#include <roapi.h>
#include <winstring.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.ui.notifications.h>
#include <windows.data.xml.dom.h>
#include <shobjidl.h>
#include <string>
#include "kswv2_internal.h"

namespace {

using namespace ABI::Windows::Foundation;
using namespace ABI::Windows::UI::Notifications;
using namespace ABI::Windows::Data::Xml::Dom;
using namespace Microsoft::WRL;
using namespace Microsoft::WRL::Wrappers;

// 텍스트 내용에 필요한 최소 범위의 XML 이스케이프.
std::wstring XmlEscape(const wchar_t *s) {
    std::wstring out;
    if (!s) return out;
    for (const wchar_t *p = s; *p; ++p) {
        switch (*p) {
        case L'<':  out += L"&lt;";   break;
        case L'>':  out += L"&gt;";   break;
        case L'&':  out += L"&amp;";  break;
        case L'"':  out += L"&quot;"; break;
        case L'\'': out += L"&apos;"; break;
        default:    out += *p;        break;
        }
    }
    return out;
}

} // namespace

extern "C" int32_t KSWV2_ShowToast(
    const wchar_t *aumid,
    const wchar_t *title,
    const wchar_t *body,
    const wchar_t *tag)
{
    if (!aumid || !aumid[0]) return E_INVALIDARG;

    // 토스트 XML 구성.
    std::wstring xml = L"<toast><visual><binding template=\"ToastGeneric\">";
    if (title && title[0]) {
        xml += L"<text>";
        xml += XmlEscape(title);
        xml += L"</text>";
    }
    if (body && body[0]) {
        xml += L"<text>";
        xml += XmlEscape(body);
        xml += L"</text>";
    }
    xml += L"</binding></visual></toast>";

    // XmlDocument 활성화 및 로드.
    ComPtr<IInspectable> xmlInspectable;
    HSTRING xmlClassName = nullptr;
    HRESULT hr = WindowsCreateString(
        RuntimeClass_Windows_Data_Xml_Dom_XmlDocument,
        (UINT32)wcslen(RuntimeClass_Windows_Data_Xml_Dom_XmlDocument),
        &xmlClassName);
    if (FAILED(hr)) return (int32_t)hr;
    hr = RoActivateInstance(xmlClassName, &xmlInspectable);
    WindowsDeleteString(xmlClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IXmlDocumentIO> xmlIO;
    hr = xmlInspectable.As(&xmlIO);
    if (FAILED(hr)) return (int32_t)hr;

    HSTRING xmlContent = nullptr;
    hr = WindowsCreateString(xml.c_str(), (UINT32)xml.length(), &xmlContent);
    if (FAILED(hr)) return (int32_t)hr;
    hr = xmlIO->LoadXml(xmlContent);
    WindowsDeleteString(xmlContent);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IXmlDocument> xmlDoc;
    hr = xmlInspectable.As(&xmlDoc);
    if (FAILED(hr)) return (int32_t)hr;

    // ToastNotificationManager statics 획득.
    HSTRING managerClassName = nullptr;
    hr = WindowsCreateString(
        RuntimeClass_Windows_UI_Notifications_ToastNotificationManager,
        (UINT32)wcslen(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager),
        &managerClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotificationManagerStatics> toastStatics;
    hr = RoGetActivationFactory(
        managerClassName, IID_PPV_ARGS(&toastStatics));
    WindowsDeleteString(managerClassName);
    if (FAILED(hr)) return (int32_t)hr;

    // CreateToastNotifier(aumid).
    HSTRING aumidHS = nullptr;
    hr = WindowsCreateString(aumid, (UINT32)wcslen(aumid), &aumidHS);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotifier> notifier;
    hr = toastStatics->CreateToastNotifierWithId(aumidHS, &notifier);
    WindowsDeleteString(aumidHS);
    if (FAILED(hr)) return (int32_t)hr;

    // XML로 ToastNotification 활성화.
    HSTRING notificationClassName = nullptr;
    hr = WindowsCreateString(
        RuntimeClass_Windows_UI_Notifications_ToastNotification,
        (UINT32)wcslen(RuntimeClass_Windows_UI_Notifications_ToastNotification),
        &notificationClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotificationFactory> toastFactory;
    hr = RoGetActivationFactory(
        notificationClassName, IID_PPV_ARGS(&toastFactory));
    WindowsDeleteString(notificationClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotification> toast;
    hr = toastFactory->CreateToastNotification(xmlDoc.Get(), &toast);
    if (FAILED(hr)) return (int32_t)hr;

    // tag가 있으면 IToastNotification2::put_Tag로 설정한다.
    // tag는 이후 KSWV2_CancelToast로 알림을 취소하는 데 사용된다.
    if (tag && tag[0]) {
        ComPtr<IToastNotification2> toast2;
        if (SUCCEEDED(toast.As(&toast2))) {
            HSTRING tagHS = nullptr;
            if (SUCCEEDED(WindowsCreateString(tag, (UINT32)wcslen(tag), &tagHS))) {
                toast2->put_Tag(tagHS);
                WindowsDeleteString(tagHS);
            }
        }
    }

    hr = notifier->Show(toast.Get());
    return (int32_t)hr;
}

/// 현재 프로세스의 AppUserModelID를 설정한다.
/// 토스트 알림이 올바른 바로 가기/ID에 바인딩되려면 필요하다.
extern "C" int32_t KSWV2_SetAppUserModelID(const wchar_t *aumid) {
    if (!aumid || !aumid[0]) return E_INVALIDARG;
    return (int32_t)SetCurrentProcessExplicitAppUserModelID(aumid);
}

/// Action Center에서 tag/aumid로 식별되는 토스트를 제거한다.
/// `KSWV2_ShowToast`에 전달한 tag와 aumid를 그대로 사용한다.
/// tag나 aumid가 비어있으면 E_INVALIDARG. 알림이 없으면 S_OK를 반환한다.
extern "C" int32_t KSWV2_CancelToast(
    const wchar_t *aumid,
    const wchar_t *tag)
{
    if (!aumid || !aumid[0]) return E_INVALIDARG;
    if (!tag || !tag[0]) return E_INVALIDARG;

    // IToastNotificationManagerStatics2를 통해 History 객체를 가져온다.
    HSTRING managerClassName = nullptr;
    HRESULT hr = WindowsCreateString(
        RuntimeClass_Windows_UI_Notifications_ToastNotificationManager,
        (UINT32)wcslen(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager),
        &managerClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotificationManagerStatics2> toastStatics2;
    hr = RoGetActivationFactory(managerClassName, IID_PPV_ARGS(&toastStatics2));
    WindowsDeleteString(managerClassName);
    if (FAILED(hr)) return (int32_t)hr;

    ComPtr<IToastNotificationHistory> history;
    hr = toastStatics2->get_History(&history);
    if (FAILED(hr)) return (int32_t)hr;

    // RemoveGroupedTagWithId(tag, group="", applicationId=aumid) で削除.
    HSTRING tagHS = nullptr;
    HSTRING groupHS = nullptr;
    HSTRING aumidHS = nullptr;
    hr = WindowsCreateString(tag, (UINT32)wcslen(tag), &tagHS);
    if (SUCCEEDED(hr)) hr = WindowsCreateString(L"", 0, &groupHS);
    if (SUCCEEDED(hr)) hr = WindowsCreateString(aumid, (UINT32)wcslen(aumid), &aumidHS);

    HRESULT removeHr = E_FAIL;
    if (SUCCEEDED(hr)) {
        removeHr = history->RemoveGroupedTagWithId(tagHS, groupHS, aumidHS);
        // S_OK, S_FALSE, 또는 "해당 알림 없음"도 S_OK이므로 성공으로 처리.
    }

    WindowsDeleteString(tagHS);
    WindowsDeleteString(groupHS);
    WindowsDeleteString(aumidHS);

    return (int32_t)removeHr;
}
