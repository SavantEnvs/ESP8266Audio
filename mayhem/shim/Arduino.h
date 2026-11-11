// Arduino.h for the Helix MP3 decoder on a host build.
//
// Helix selects its portable C fixed-point math (libhelix-mp3/assembly.h, mp3dec.h) only when
// ARDUINO is defined, and that is the only configuration upstream builds for a non-x86-32 CPU.
// tests/host/Arduino.h refuses to compile with ARDUINO set, so this wrapper hides the macro while
// the host shim is included. Used only for libhelix-mp3 and AudioGeneratorMP3a.cpp.
#ifndef MAYHEM_ARDUINO_SHIM_H
#define MAYHEM_ARDUINO_SHIM_H
#pragma push_macro("ARDUINO")
#undef ARDUINO
#include "../../tests/host/Arduino.h"
#pragma pop_macro("ARDUINO")
#endif
