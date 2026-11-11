#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorMOD.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorMOD gen;
    return RunGenerator(&gen, &in, &out, 10000);
}
