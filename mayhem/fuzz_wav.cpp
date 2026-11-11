#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorWAV.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorWAV gen;
    return RunGenerator(&gen, &in, &out, 1000000);
}
