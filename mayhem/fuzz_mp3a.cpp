#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#pragma push_macro("ARDUINO")
#define ARDUINO 1
#include "AudioGeneratorMP3a.h"
#pragma pop_macro("ARDUINO")

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorMP3a gen;
    return RunGenerator(&gen, &in, &out, 1000000);
}
