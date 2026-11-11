#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorMP3.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorMP3 gen;
    return RunGenerator(&gen, &in, &out, 1000000);
}
