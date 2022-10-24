/**
Silence detection, allows not to process silence in plug-ins.

Copyright: Copyright Guillaume Piolat 2015-2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.dsp.silencedetect;


import core.stdc.string;

struct SilenceDetector
{
public:

    /// Params:
    ///     tailInSamples the number of samples of silence needed so that the output is silent too
    ///     startSilent si true when the input being zero at the srart immediately means the output can be silent too.
    /// 
    void initialize(int tailInSamples, bool startSilent = false) nothrow @nogc
    {
        _silenceDuration = startSilent ? tailInSamples : 0;
        _tailInSamples = tailInSamples;
    }

    /// Returns: true if the input has been silent since more than a tail duration (conservative estimate).
    bool isSilenceDetected(const(float)* inputR, const(float)* inputL, int frames) nothrow @nogc
    {
        bool allZeroes = isBufferSilent(inputR, frames) && isBufferSilent(inputL, frames);

        if (allZeroes)
        {
            // not considering the current buffer for tail length,
            // since last buffer could have been non-zero
            bool result = _silenceDuration >= _tailInSamples;
            _silenceDuration += frames;
            return result;
        }
        else
        {
            _silenceDuration = 0;  // PERF: this could be made more aggressive, scanning zeroes in reverse fashion
            return false;
        }
    }

private:
    long _silenceDuration;
    long _tailInSamples;

    /// Returns: true if the whole buffer is filled with 0.0f (or -0.0f) 
    static bool isBufferSilent(const(float)* buffer, int frames) nothrow @nogc
    {
        // should be all zeroes
        for (int i = 0; i < frames; ++i)
        {
            if (buffer[i] != 0)
                return false;
        }
        return true;
    }

}

