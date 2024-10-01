
import _pydelia 

def sine_wave(**kwargs):
    freq = kwargs.get('freq', 100.0)
    amp = kwargs.get('amp', 1.0)
    sr = kwargs.get('sr', 44100.0)
    dur = kwargs.get('dur', 1.0)
    
    return _pydelia.sine_wave(freq, amp, sr, dur)
