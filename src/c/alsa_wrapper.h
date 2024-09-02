#ifndef ALSA_WRAPPER_H
#define ALSA_WRAPPER_H

#ifdef USE_MOCK_ALSA
#include "mock_alsa.h"
#else
#include <alsa/asoundlib.h>

snd_pcm_state_t a;
#endif

#endif // ALSA_WRAPPER_H
