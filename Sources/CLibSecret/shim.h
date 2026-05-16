#ifndef CLIBSECRET_SHIM_H
#define CLIBSECRET_SHIM_H

#include <libsecret/secret.h>

/*
 * Kalsae 자격증명 백엔드용 정적 스키마.
 *
 * `secret_schema_new`는 가변 인자 함수라 Swift에서 직접 호출하기 어렵다
 * (NULL 종결자를 CVarArg로 전달 불가). 대신 정적 `SecretSchema` 인스턴스를
 * inline 함수로 노출해 Swift에서 단순한 함수 호출 한 번으로 얻도록 한다.
 *
 * 스키마는 프로세스 수명 동안 단 하나, BSS에 배치되어 누수가 없고 잠금이
 * 필요 없다. `SECRET_SCHEMA_DONT_MATCH_NAME` 플래그로 이름 변경에 강건하다.
 *
 * Service 격리: `service` attribute는 IPC 계층에서 bundleId prefix가
 * 적용되므로 앱 간 충돌이 없다.
 */
static inline const SecretSchema *ks_libsecret_credential_schema(void) {
    static const SecretSchema schema = {
        .name = "dev.kalsae.Credential",
        .flags = SECRET_SCHEMA_DONT_MATCH_NAME,
        .attributes = {
            { "service", SECRET_SCHEMA_ATTRIBUTE_STRING },
            { "account", SECRET_SCHEMA_ATTRIBUTE_STRING },
            { NULL, 0 }
        }
    };
    return &schema;
}

#endif
