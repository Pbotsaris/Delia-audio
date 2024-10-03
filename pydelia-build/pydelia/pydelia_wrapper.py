
import _pydelia 
from typing import List

def sine_wave(**kwargs):
    freq = kwargs.get('freq', 100.0)
    amp = kwargs.get('amp', 1.0)
    sr = kwargs.get('sr', 44100.0)
    dur = kwargs.get('dur', 1.0)
    
    return _pydelia.sine_wave(freq, amp, sr, dur)

def fft(vec: List[float]) -> List[complex]:
    return _pydelia.fft(vec)

def ifft(vec: List[complex]) -> List[float]:
    return _pydelia.ifft(vec)
