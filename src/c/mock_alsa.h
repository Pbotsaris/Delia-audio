#ifndef MOCK_ALSA_H
#define MOCK_ALSA_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Mock types and structs
typedef struct snd_pcm_t {
  int state;
  int avail;
  int buffer_size;
  int channels;
  int sample_rate;
} snd_pcm_t;

typedef struct snd_pcm_hw_params_t {
  int dummy;
} snd_pcm_hw_params_t;

typedef struct snd_pcm_sw_params_t {
  int dummy;
} snd_pcm_sw_params_t;

typedef struct snd_pcm_channel_area_t {
  void *addr;
  unsigned int first;
  unsigned int step;
} snd_pcm_channel_area_t;

typedef struct snd_ctl_t {
  int dummy;
} snd_ctl_t;

typedef struct snd_ctl_card_info_t {
  char id[32];
  char name[64];
} snd_ctl_card_info_t;

typedef struct snd_pcm_info_t {
  int device;
  char id[32];
  char name[64];
} snd_pcm_info_t;

typedef uint snd_pcm_state_t;
typedef int snd_pcm_sframes_t;
typedef uint64_t snd_pcm_uframes_t;
typedef int snd_pcm_format_t;
typedef  int snd_pcm_stream_t;
typedef unsigned int snd_ctl_card_info_malloc_t;

// Mock constants and macros
#define SND_PCM_STATE_RUNNING 0
#define SND_PCM_STATE_XRUN 1
#define SND_PCM_STATE_SUSPENDED 2
#define EPIPE 32
#define ESTRPIPE 86
#define EAGAIN 11

// Mock functions
inline int snd_pcm_open(snd_pcm_t **pcm, const char *name, int stream,
                        int mode) {
  *pcm = (snd_pcm_t *)malloc(sizeof(snd_pcm_t));
  (*pcm)->state = SND_PCM_STATE_RUNNING;
  (*pcm)->avail = 1024;
  (*pcm)->buffer_size = 4096;
  return 0; // Return success
}

inline int snd_pcm_close(snd_pcm_t *pcm) {
  free(pcm);
  return 0; // Return success
}

inline int snd_pcm_hw_params_malloc(snd_pcm_hw_params_t **params) {
  *params = (snd_pcm_hw_params_t *)malloc(sizeof(snd_pcm_hw_params_t));
  return 0; // Return success
}

inline void snd_pcm_hw_params_free(snd_pcm_hw_params_t *params) {
  free(params);
}

inline int snd_pcm_hw_params_any(snd_pcm_t *pcm, snd_pcm_hw_params_t *params) {
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_access(snd_pcm_t *pcm,
                                        snd_pcm_hw_params_t *params,
                                        int access) {
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_format(snd_pcm_t *pcm,
                                        snd_pcm_hw_params_t *params,
                                        int format) {
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_channels(snd_pcm_t *pcm,
                                          snd_pcm_hw_params_t *params,
                                          unsigned int channels) {
  pcm->channels = channels;
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_rate_near(snd_pcm_t *pcm,
                                           snd_pcm_hw_params_t *params,
                                           unsigned int *rate, int *dir) {
  pcm->sample_rate = *rate;
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_buffer_size_near(snd_pcm_t *pcm,
                                                  snd_pcm_hw_params_t *params,
                                                  snd_pcm_uframes_t *size) {
  pcm->buffer_size = *size;
  return 0; // Return success
}

inline int snd_pcm_hw_params_set_period_size_near(snd_pcm_t *pcm,
                                                  snd_pcm_hw_params_t *params,
                                                  snd_pcm_uframes_t *size,
                                                  int *dir) {
  return 0; // Return success
}

inline int snd_pcm_hw_params(snd_pcm_t *pcm, snd_pcm_hw_params_t *params) {
  return 0; // Return success
}

inline int snd_pcm_hw_params_get_buffer_size(snd_pcm_hw_params_t *params,
                                             snd_pcm_uframes_t *size) {
  *size = 4096; // Mock buffer size
  return 0;     // Return success
}

inline int snd_pcm_hw_params_get_period_size(snd_pcm_hw_params_t *params,
                                             snd_pcm_uframes_t *size,
                                             int *dir) {
  *size = 1024; // Mock period size
  return 0;     // Return success
}

inline int snd_pcm_sw_params_malloc(snd_pcm_sw_params_t **params) {
  *params = (snd_pcm_sw_params_t *)malloc(sizeof(snd_pcm_sw_params_t));
  return 0; // Return success
}

inline void snd_pcm_sw_params_free(snd_pcm_sw_params_t *params) {
  free(params);
}

inline int snd_pcm_sw_params_current(snd_pcm_t *pcm,
                                     snd_pcm_sw_params_t *params) {
  return 0; // Return success
}

inline int snd_pcm_sw_params_set_avail_min(snd_pcm_t *pcm,
                                           snd_pcm_sw_params_t *params,
                                           snd_pcm_uframes_t val) {
  return 0; // Return success
}

inline int snd_pcm_sw_params_set_start_threshold(snd_pcm_t *pcm,
                                                 snd_pcm_sw_params_t *params,
                                                 snd_pcm_uframes_t val) {
  return 0; // Return success
}

inline int snd_pcm_sw_params_set_period_event(snd_pcm_t *pcm,
                                              snd_pcm_sw_params_t *params,
                                              int val) {
  return 0; // Return success
}

inline int snd_pcm_sw_params(snd_pcm_t *pcm, snd_pcm_sw_params_t *params) {
  return 0; // Return success
}

inline int snd_pcm_prepare(snd_pcm_t *pcm) {
  return 0; // Return success
}

inline const char *snd_strerror(int errnum) { return "Mock ALSA error"; }

inline snd_pcm_state_t snd_pcm_state(snd_pcm_t *pcm) { return pcm->state; }

inline int snd_pcm_avail_update(snd_pcm_t *pcm) { return pcm->avail; }

inline int snd_pcm_start(snd_pcm_t *pcm) {
  // Mock starting the PCM device
  return 0;
}

inline int snd_pcm_resume(snd_pcm_t *pcm) {
  // Mock resuming the PCM device
  return 0;
}

inline int snd_pcm_wait(snd_pcm_t *pcm, int timeout) {
  // Mock waiting on the PCM device
  return 0;
}

inline int snd_pcm_mmap_begin(snd_pcm_t *pcm, snd_pcm_channel_area_t **areas,
                              snd_pcm_uframes_t *offset,
                              snd_pcm_uframes_t *frames) {
  static snd_pcm_channel_area_t area;
  static uint8_t buffer[1024];
  area.addr = buffer;
  *areas = &area;
  *offset = 0;
  *frames = pcm->buffer_size;
  return 0;
}

inline snd_pcm_sframes_t snd_pcm_mmap_commit(snd_pcm_t *pcm,
                                             snd_pcm_uframes_t offset,
                                             snd_pcm_uframes_t frames) {
  // Mock committing the mmap operation
  return frames;
}

// Additional functions for Hardware management

inline int snd_card_next(int *card) {
  static int current_card = -1;
  if (current_card == -1) {
    current_card = 0;
  } else if (current_card == 0) {
    current_card = -1;
    *card = -1;
    return 0;
  }
  *card = current_card;
  return 0;
}

inline int snd_ctl_open(snd_ctl_t **ctl, const char *name, int mode) {
  *ctl = (snd_ctl_t *)malloc(sizeof(snd_ctl_t));
  return 0;
}

inline int snd_ctl_close(snd_ctl_t *ctl) {
  free(ctl);
  return 0;
}

inline int snd_ctl_card_info_malloc(snd_ctl_card_info_t **info) {
  *info = (snd_ctl_card_info_t *)malloc(sizeof(snd_ctl_card_info_t));
  strcpy((*info)->id, "MockCard");
  strcpy((*info)->name, "Mock Sound Card");
  return 0;
}

inline void snd_ctl_card_info_free(snd_ctl_card_info_t *info) { free(info); }

inline int snd_ctl_card_info(snd_ctl_t *ctl, snd_ctl_card_info_t *info) {
  return 0;
}

inline const char *snd_ctl_card_info_get_id(const snd_ctl_card_info_t *info) {
  return info->id;
}

inline const char *snd_ctl_card_info_get_name(const snd_ctl_card_info_t *info) {
  return info->name;
}

inline int snd_ctl_pcm_next_device(snd_ctl_t *ctl, int *device) {
  static int current_device = -1;
  if (current_device == -1) {
    current_device = 0;
  } else if (current_device == 0) {
    current_device = -1;
    *device = -1;
    return 0;
  }
  *device = current_device;
  return 0;
}

inline int snd_pcm_info_malloc(snd_pcm_info_t **info) {
  *info = (snd_pcm_info_t *)malloc(sizeof(snd_pcm_info_t));
  (*info)->device = 0;
  strcpy((*info)->id, "PCM0");
  strcpy((*info)->name, "Mock PCM Device");
  return 0;
}

inline void snd_pcm_info_free(snd_pcm_info_t *info) { free(info); }

inline int snd_ctl_pcm_info(snd_ctl_t *ctl, snd_pcm_info_t *info) { return 0; }

inline void snd_pcm_info_set_device(snd_pcm_info_t *info, unsigned int device) {
  info->device = device;
}

inline void snd_pcm_info_set_subdevice(snd_pcm_info_t *info,
                                       unsigned int subdevice) {
  // Mock implementation does nothing
}

inline void snd_pcm_info_set_stream(snd_pcm_info_t *info,
                                    snd_pcm_stream_t stream) {
  // Mock implementation does nothing
}

inline const char *snd_pcm_info_get_id(const snd_pcm_info_t *info) {
  return info->id;
}

inline const char *snd_pcm_info_get_name(const snd_pcm_info_t *info) {
  return info->name;
}

inline int snd_pcm_hw_params_test_format(snd_pcm_t *pcm,
                                         snd_pcm_hw_params_t *params,
                                         snd_pcm_format_t val) {
  return 0; // Assume all formats are supported
}

inline int snd_pcm_hw_params_test_rate(snd_pcm_t *pcm,
                                       snd_pcm_hw_params_t *params,
                                       unsigned int val, int dir) {
  return 0; // Assume all rates are supported
}

inline int snd_pcm_hw_params_test_channels(snd_pcm_t *pcm,
                                           snd_pcm_hw_params_t *params,
                                           unsigned int val) {
  return 0; // Assume all channel configurations are supported
}

#endif // MOCK_ASOUND_H
