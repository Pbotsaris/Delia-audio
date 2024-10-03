import numpy as np
import pydelia
import timeit

# Generate a sine wave using pydelia
r = []

for i in range(1025):
    r.append(0.5);

np_wave = np.array(r)

# Define a function to run pydelia FFT
def run_pydelia_fft():
    pydelia_fft = pydelia.fft(r)
    return pydelia_fft

def run_numpy_fft():
    numpy_fft = np.fft.fft(np_wave)
    return numpy_fft

# Run timeit to measure pydelia's FFT
pydelia_time = timeit.timeit(run_pydelia_fft, number=1000)

# Run timeit to measure NumPy's FFT
numpy_time = timeit.timeit(run_numpy_fft, number=1000)

# Print the results
print(f"pydelia FFT time: {pydelia_time:.6f} seconds")
print(f"NumPy FFT time: {numpy_time:.6f} seconds")
