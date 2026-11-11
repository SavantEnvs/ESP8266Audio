#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioFileSourceID3.h"

static void OnMetadata(void *cbData, const char *type, bool isUnicode, const char *string) {
    (void)cbData;
    (void)type;
    (void)isUnicode;
    // The callback owns a NUL-terminated string for the duration of the call.
    volatile size_t n = strlen(string);
    (void)n;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    AudioFileSourceID3 id3(&in);
    id3.RegisterMetadataCB(OnMetadata, NULL);
    uint8_t buf[256];
    // The first read() parses the ID3v2 tag; the remaining reads pass the stream through.
    for (int i = 0; i < 100000 && id3.read(buf, sizeof(buf)) != 0; i++) {
    }
    return 0;
}
