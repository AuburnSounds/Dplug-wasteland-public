/**
Smoothed biquad processing.

Copyright: Copyright Guillaume Piolat 2015-2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 
*/
module auburn.dsp.interpbiquad;

import dplug.core;
import dplug.dsp;


/// Interpolates a biquad by small sections of identical coefficients values
/// TODO tune ChunkSize, decayTimeSecs
// Problem: for Panagement, best ChunkSize is 1... which means different coefficients everytime
struct InterpBiquadDelay(int ChunkSize = 1)
{
public:
nothrow: 
@nogc:

    void initialize(float sampleRate, float decayTimeSecs) 
    {
        static assert(isPowerOfTwo(ChunkSize));
        _chunkingShift = iFloorLog2(ChunkSize);
        _biquadDelay.initialize();

        int chunking = 1 << _chunkingShift;

        // fill an array with correct decay factors
        foreach (int i, ref factor; _decayFactors)
        {
            int sampleDuration = i + 1;
            factor = cast(float)(expDecayFactor(decayTimeSecs, sampleRate / sampleDuration));
        }
        _current = biquadBypass();
    }

    void nextBuffer(const(float)* input, float* output, int frames, BiquadCoeff target)
    {
        int chunking = 1 << _chunkingShift;
        int chunks = frames >>  _chunkingShift;
        int remaining = frames - (chunks << _chunkingShift);

        float decayFactorForChunk = _decayFactors[ChunkSize - 1];

        for (int i = 0; i < chunks; ++i)
        {
            BiquadCoeff diff = void;
            for(int k = 0; k < 5; ++k)
            {
                _current[k] += (target[k] - _current[k]) * decayFactorForChunk;
            }

            _biquadDelay.nextBuffer(input, output, chunking, _current);

            input += chunking;
            output += chunking;
        }

        if (remaining > 0)
        {
            BiquadCoeff diff = void;
            for(int k = 0; k < 5; ++k)
            {
                _current[k] += (target[k] - _current[k]) * _decayFactors[remaining - 1];
            }
            _biquadDelay.nextBuffer(input, output, remaining, _current);
        }
    }
private:
    int _chunkingShift;
    BiquadDelay _biquadDelay;
    BiquadCoeff _current;

    float[ChunkSize] _decayFactors;
}


/// New version, that interpolates coefficients first in a buffer and then pass it to a special routine.
struct InterpolatedBiquad
{
public:
nothrow: 
@nogc:

    void initialize(float sampleRate, float decayTimeSecs) 
    {
        _biquadDelay.initialize();
        _decayFactor = expDecayFactor(decayTimeSecs, sampleRate);
        _current = biquadBypass();
    }

    ~this()
    {
    }

    // Note: pre-computing coefficients in buffers did not worked out at all, was much slower
    void nextBuffer(const(float)* input, float* output, int frames, BiquadCoeff target)
    {
        // Note: this naive version performs better than an intel-intrinsics one
        double x0 = _biquadDelay._x0,
               x1 = _biquadDelay._x1,
               y0 = _biquadDelay._y0,
               y1 = _biquadDelay._y1;

        BiquadCoeff currentCoeff = _current;
        double decayFactor = _decayFactor;
        for(int i = 0; i < frames; ++i)
        {
            currentCoeff[0] += (target[0] - currentCoeff[0]) * decayFactor;
            currentCoeff[1] += (target[1] - currentCoeff[1]) * decayFactor;
            currentCoeff[2] += (target[2] - currentCoeff[2]) * decayFactor;
            currentCoeff[3] += (target[3] - currentCoeff[3]) * decayFactor;
            currentCoeff[4] += (target[4] - currentCoeff[4]) * decayFactor;

            double a0 = currentCoeff[0],
                   a1 = currentCoeff[1],
                   a2 = currentCoeff[2],
                   a3 = currentCoeff[3],
                   a4 = currentCoeff[4];

            double current = a0 * input[i] + a1 * x0 + a2 * x1 - a3 * y0 - a4 * y1;

            // kill denormals,and double values that would be converted
            // to float denormals
            version(killDenormals)
            {
                current += 1e-18f;
                current -= 1e-18f;
            }

            x1 = x0;
            x0 = input[i];
            y1 = y0;
            y0 = current;
            output[i] = current;
        }

        _biquadDelay._x0 = x0;
        _biquadDelay._x1 = x1;
        _biquadDelay._y0 = y0;
        _biquadDelay._y1 = y1;
        _current = currentCoeff;
    }

private:
    BiquadDelay _biquadDelay;
    BiquadCoeff _current;
    double _decayFactor;
}