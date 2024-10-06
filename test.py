import pydelia

# sine = pydelia.sine_wave(freq=440, sr=44100, amp=0.5, dur=0.1)
# r = pydelia.fft(sine)
# r = pydelia.ifft(r)
# 
# print(r)
# 
# sine2 = pydelia.sine_wave(freq=1000, sr=44100, amp=0.5, dur=0.1)
# 
# c = pydelia.fft_convolve(sine, sine2)
# 
# print(c)
# 

l = [0.1, 0.2, 0.3, 0.4, 0.5]

r = pydelia.hanning(l)
print(r)
r = pydelia.blackman(l)
print(r)
