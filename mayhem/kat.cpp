// Known-answer probe: decode one fixture with one generator and print what came out.
//   kat <wav|mp3|mp3a|aac|flac|mod|midi|opus|rtttl> <file>
// mayhem/test.sh compares the printed line with values recorded from the upstream decoders.
#include <vector>
#include "harness_common.h"
#include "AudioFileSourcePROGMEM.h"
#include "AudioGeneratorWAV.h"
#include "AudioGeneratorMP3.h"
#pragma push_macro("ARDUINO")
#define ARDUINO 1
#include "AudioGeneratorMP3a.h"
#pragma pop_macro("ARDUINO")
#include "AudioGeneratorAAC.h"
#include "AudioGeneratorFLAC.h"
#include "AudioGeneratorMOD.h"
#include "AudioGeneratorMIDI.h"
#include "AudioGeneratorOpus.h"
#include "AudioGeneratorRTTTL.h"

#include <libtinysoundfont/scratch2010.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: kat <codec> <file>\n");
        return 2;
    }
    const char *codec = argv[1];
    FILE *f = fopen(argv[2], "rb");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", argv[2]);
        return 2;
    }
    std::vector<uint8_t> bytes;
    uint8_t chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), f)) > 0) {
        bytes.insert(bytes.end(), chunk, chunk + n);
    }
    fclose(f);
    AudioFileSourcePROGMEM in(bytes.data(), (uint32_t)bytes.size());
    HashOutput out;
    int ret = 2;
    if (!strcmp(codec, "wav")) {
        AudioGeneratorWAV g;
        ret = RunGenerator(&g, &in, &out, 1000000);
    } else if (!strcmp(codec, "mp3")) {
        AudioGeneratorMP3 g;
        ret = RunGenerator(&g, &in, &out, 1000000);
    } else if (!strcmp(codec, "mp3a")) {
        AudioGeneratorMP3a g;
        ret = RunGenerator(&g, &in, &out, 1000000);
    } else if (!strcmp(codec, "aac")) {
        void *space = malloc(28000 + 60000 + 2048);
        {
            AudioGeneratorAAC g(space, 28000 + 60000 + 2048);
            ret = RunGenerator(&g, &in, &out, 1000000);
        }
        free(space);
    } else if (!strcmp(codec, "flac")) {
        AudioGeneratorFLAC g;
        ret = RunGenerator(&g, &in, &out, 10000000);
    } else if (!strcmp(codec, "mod")) {
        AudioGeneratorMOD g;
        ret = RunGenerator(&g, &in, &out, 10000);
    } else if (!strcmp(codec, "midi")) {
        struct tsf font = _tsf;
        AudioGeneratorMIDI g;
        g.SetSoundFont(&font);
        g.SetSampleRate(22050);
        ret = RunGenerator(&g, &in, &out, 10000000);
    } else if (!strcmp(codec, "opus")) {
        AudioGeneratorOpus g;
        ret = RunGenerator(&g, &in, &out, 10000000);
    } else if (!strcmp(codec, "rtttl")) {
        AudioGeneratorRTTTL g;
        ret = RunGenerator(&g, &in, &out, 10000000);
    } else {
        fprintf(stderr, "unknown codec %s\n", codec);
        return 2;
    }
    printf("kat %s ret=%d rate=%d channels=%d samples=%llu hash=%08x\n", codec, ret, out.GetRate(),
           out.GetChannels(), (unsigned long long)out.samples, out.hash);
    return ret == 0 ? 0 : 1;
}
