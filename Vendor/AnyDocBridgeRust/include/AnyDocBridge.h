#ifndef FAMILIAR_ANYDOC_BRIDGE_H
#define FAMILIAR_ANYDOC_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FamiliarAnyDocResult FamiliarAnyDocResult;

FamiliarAnyDocResult *familiar_anydoc_convert(
    const uint8_t *bytes,
    size_t length,
    const char *extension
);

const uint8_t *familiar_anydoc_markdown_bytes(const FamiliarAnyDocResult *result);
size_t familiar_anydoc_markdown_length(const FamiliarAnyDocResult *result);
const char *familiar_anydoc_format(const FamiliarAnyDocResult *result);
const char *familiar_anydoc_error_code(const FamiliarAnyDocResult *result);
const char *familiar_anydoc_error_message(const FamiliarAnyDocResult *result);
void familiar_anydoc_result_free(FamiliarAnyDocResult *result);
const char *familiar_anydoc_version(void);

#ifdef __cplusplus
}
#endif

#endif
