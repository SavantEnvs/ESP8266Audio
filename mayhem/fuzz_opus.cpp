#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorOpus.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorOpus gen;
    return RunGenerator(&gen, &in, &out, 1000000);
}
