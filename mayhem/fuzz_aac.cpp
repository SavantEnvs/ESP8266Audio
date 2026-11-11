#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorAAC.h"

// Same preallocated working space the upstream host test (tests/host/aac.cpp) gives Helix AAC.
static const int kSpace = 28000 + 60000 + 2048;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    void *space = malloc(kSpace);
    int ret;
    {
        AudioFileSourcePROGMEM in(data, (uint32_t)size);
        HashOutput out;
        AudioGeneratorAAC gen(space, kSpace);
        ret = RunGenerator(&gen, &in, &out, 1000000);
    }
    free(space);
    return ret;
}
