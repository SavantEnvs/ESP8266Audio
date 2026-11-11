// Shared by the fuzz harnesses and the known-answer probe (kat.cpp).
// Host builds use tests/host/Arduino.h (selected with -I tests/host -include Arduino.h).
#ifndef MAYHEM_HARNESS_COMMON_H
#define MAYHEM_HARNESS_COMMON_H

#include <Arduino.h>
#include <stdint.h>
#include <stdlib.h>

#include "AudioFileSource.h"
#include "AudioOutput.h"

// Consumes decoded samples and folds them into a count and an FNV-1a hash.
class HashOutput : public AudioOutput {
public:
    HashOutput() : samples(0), hash(2166136261u) {
        hertz = 0;
        channels = 2;
        gainF2P6 = 1 << 6;
    }
    virtual bool begin() override {
        return true;
    }
    virtual bool ConsumeSample(int16_t sample[2]) override {
        samples++;
        Mix(sample[0]);
        Mix(sample[1]);
        return true;
    }
    virtual bool stop() override {
        return true;
    }
    uint64_t samples;
    uint32_t hash;
    int GetRate() const {
        return hertz;
    }
    int GetChannels() const {
        return channels;
    }

private:
    void Mix(int16_t s) {
        hash = (hash ^ (uint8_t)(s & 0xff)) * 16777619u;
        hash = (hash ^ (uint8_t)((s >> 8) & 0xff)) * 16777619u;
    }
};

// Drives a generator to completion. Returns -1 when the generator refuses the stream in begin().
// maxLoops bounds generators that never end on their own (a MOD loops forever).
template <class Generator>
static int RunGenerator(Generator *gen, AudioFileSource *in, AudioOutput *out, int maxLoops) {
    if (!gen->begin(in, out)) {
        return -1;
    }
    for (int i = 0; i < maxLoops && gen->loop(); i++) {
    }
    if (gen->isRunning()) {
        gen->stop();
    }
    return 0;
}

#endif
