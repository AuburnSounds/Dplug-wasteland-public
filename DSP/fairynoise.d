/**
* Copyright 2019 Guillaume Piolat
* Copyright 2017 Ethan Reker
* License: MIT License
*/

module auburn.dsp.fairynoise;


nothrow:
@nogc:

/// Small multiplicative noise.
/// Noise from each channels is uncorrelated to make the output a bit larger.
struct FairyNoise
{
public:
nothrow:
@nogc:

    // Highly recommended to tune this for your particular context.
    // Your preference will perhaps be 8x smaller than that.
    // It sounds worse on single instruments, and in mastering applications.
    // I believe it works by masking more ugly FP artifacts.
    enum float DEFAULT_NOISE_AMOUNT = 0.00016f; // tuned twiced, used in Couture (-86dB RMS relative difference)
                                      

    void initialize(uint seed, 
                    int numChannels, 
                    float noiseAmount = DEFAULT_NOISE_AMOUNT) 
    {
        assert(numChannels <= MAX_CHANNELS);
        _channels = numChannels;
        _noiseAmount = noiseAmount;
        for(int chan = 0; chan < numChannels; ++chan)
        {
            _noise[chan].initialize(seed + SEED_OFFSET[chan]);
        }
    }

    void nextBuffer(float** inoutSamples, int frames)
    {
        // Small multiplicative noise
        const float regularAmount = 1.0f - _noiseAmount * 0.5f;

        for(int chan = 0; chan < _channels; ++chan)
        {
            float* inOutBuf = inoutSamples[chan];
            for(int n = 0; n < frames; ++n)
            {
                float noise = _noise[chan].nextSample(); // 0 to 1
                float factor = regularAmount + _noiseAmount * noise;
                inOutBuf[n] *= factor;
            }
        }
    }

    void nextBuffer(double** inoutSamples, int frames)
    {
        // Small multiplicative noise
        const double regularAmount = 1.0 - _noiseAmount * 0.5;

        for(int chan = 0; chan < _channels; ++chan)
        {
            double* inOutBuf = inoutSamples[chan];
            for(int n = 0; n < frames; ++n)
            {
                double noise = _noise[chan].nextSample(); // 0 to 1
                double factor = regularAmount + _noiseAmount * noise;
                inOutBuf[n] *= factor;
            }
        }
    }

private:
    enum MAX_CHANNELS = 2;
    int _channels; // 1 or 2
    float _noiseAmount;
    WhiteNoise[MAX_CHANNELS] _noise;
    static immutable uint[MAX_CHANNELS] SEED_OFFSET = [0, 0xDEADBEEF];   
}


struct WhiteNoise
{
public:
nothrow:
@nogc:
    void initialize(uint seed)
    {
        _seed = seed;
    }

    // returns a float in [0;1[
    float nextSample()
    {
        return nextUnsignedInt() * 2.32831e-10f;// 4294967296.0f;
    }

private:

    uint nextUnsignedInt()
    {
        return  (_seed = (_seed * 1664525) + 1013904223);
    }

    uint _seed;
}
