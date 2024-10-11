import _pydelia
from typing import List

def sine_wave(**kwargs):
    freq = kwargs.get("freq", 440)
    amp = kwargs.get("amp", 1.0)
    sr = kwargs.get("sr", 44100)
    dur = kwargs.get("dur", 1.0)

    if not isinstance(freq, (int)):
        raise TypeError(f"freq must be integer but got: {type(freq).__name__}")

    if not isinstance(amp, (float)):
        raise TypeError(f"amp must be float but got: {type(amp).__name__}")

    if not isinstance(sr, (int)):
        raise TypeError(f"sr must be integer but got: {type(sr).__name__}")

    if not isinstance(dur, (float)):
        raise TypeError(f"dur must be float: but got: {type(dur).__name__}")

    return _pydelia.sine_wave(freq, amp, sr, dur)


def fft(vec: List[float]) -> List[complex]:
    return _pydelia.fft(vec)

def ifft(vec: List[complex]) -> List[float]:
    return _pydelia.ifft(vec)

def magnitude(vec: List[complex]) -> List[float]:
    return _pydelia.magnitude(vec)

def phase(vec: List[complex]) -> List[float]:
    return _pydelia.phase(vec)

def fft_convolve(vec1: List[float], vec2: List[float]) -> List[float]:
    return _pydelia.fft_convolve(vec1, vec2)


def fft_frequencies(n: int, sr: int) -> List[float]:
    return _pydelia.fft_frequencies(n, sr)

def decibels_from_magnitude(vec: List[float]) -> List[float]:
    return _pydelia.decibels_from_magnitude(vec)

def blackman(vec: List[float]) -> List[float]:
    return _pydelia.blackman(vec)

def hanning(vec: List[float]) -> List[float]:
    return _pydelia.hanning(vec)

def stft(vec: List[float]) -> List[List[float]]:
    return _pydelia.stft(vec)
