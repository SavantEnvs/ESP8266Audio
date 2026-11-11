#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorRTTTL.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorRTTTL gen;
    return RunGenerator(&gen, &in, &out, 1000000);
}
