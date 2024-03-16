/**
Copyright: Copyright Guillaume Piolat 2023-2024
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module simplelimiter;

import dplug.core.math;

// Stupid, simple, dual-mono, zero-latency, VCA-style forward, stereo limiter.
// This is just for when clipping doesn't really works, such as in a delay feedback.
// Used in Inner Pitch to avoid feedback
// You can easily transform that into a compressor instead, maybe more suited to feedback control.
// Note that this won't clip, peak will go through a bit so you may want a pre-clipper (and an actual
// good limiter) if you are after clip control. Which is out of scope of this RMS-ey limiter.
struct SimpleLimiter
{
public:
nothrow:
@nogc:

    enum int MAX_CHANNELS = 2;

    void initialize(float sampleRate, int numChans)
    {
        _sampleRate = sampleRate;
        _numChans = numChans;
        for (int chan = 0; chan < numChans; ++chan)
        {
            _lastGain[chan] = 1.0f;
            _lastAbs[chan] = 0.0f;
        }
    }

    void nextBuffer(const(float)** inSamples,
                    float** outSamples,
                    int frames,
                    float threshold) // 0 to 1
    {
        // Obviously those are tuning variables you may want to choose yourself
        float ATTACK_SECS  = 0.027f; 
        float RELEASE_SECS = 0.300f;

        // PERF: recompute only if changed
        float attackDF = expDecayFactor(ATTACK_SECS, _sampleRate);
        float releaseDF = expDecayFactor(RELEASE_SECS, _sampleRate);
        
        float[MAX_CHANNELS] lastAbs;
        for (int chan = 0; chan < _numChans; ++chan)
        {
            lastAbs[chan] = _lastAbs[chan];
        }

        // PERF: optimize
        for (int chan = 0; chan < _numChans; ++chan)
        {
            for (int n = 0; n < frames; ++n)
            {
                float sample  = inSamples[chan][n];
                float absL = fast_fabs(sample);

                // LP6 smoothing of gain estimation
                lastAbs[chan]  += (absL - lastAbs[chan]) * attackDF;
                float rat = threshold / (lastAbs[chan] + 1e-7f);

                // LP6 smoothing of GR (release)
                // GR tends towards returning to 1.0f exponentially
                float smoothedGain = _lastGain[chan] + (1.0f - _lastGain[chan]) * releaseDF;
                if (rat > smoothedGain)
                    rat = smoothedGain;
                _lastGain[chan] = rat;
                outSamples[chan][n] = sample * rat;
            }
        }

        for (int chan = 0; chan < _numChans; ++chan)
        {
            _lastAbs[chan] = lastAbs[chan];
        }
    }    

private:
    float[MAX_CHANNELS] _lastGain;
    float[MAX_CHANNELS] _lastAbs;
    float  _sampleRate;
    int _numChans;
}