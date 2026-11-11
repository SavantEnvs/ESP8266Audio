#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorMIDI.h"

#include <libtinysoundfont/scratch2010.h>  // defines the built-in soundfont `_tsf`

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // AudioGeneratorMIDI::stop() runs tsf_close(), which frees voices/channels without clearing the
    // pointers, so every input gets its own copy of the const soundfont (voices == NULL).
    struct tsf font = _tsf;
    AudioFileSourcePROGMEM in(data, (uint32_t)size);
    HashOutput out;
    AudioGeneratorMIDI gen;
    gen.SetSoundFont(&font);
    gen.SetSampleRate(22050);
    // One loop() renders one sample; 50000 is ~2 s of audio, enough to reach every MIDI event path
    // while keeping the exec rate high (1000000 took ~100 ms per input).
    return RunGenerator(&gen, &in, &out, 50000);
}
