import pydelia
r = pydelia.sine_wave(freq=440.0, amp=0.5, sr=44100.0, dur=50.0)
r = pydelia.fft(r);
r = pydelia.ifft(r)

print(r)
