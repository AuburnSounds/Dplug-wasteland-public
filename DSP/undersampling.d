/**
Everything undersampling.
Everything here is coupled with oversampling.d

Copyright: Guillaume Piolat 2015-2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.dsp.undersampling;

//import std.math;

import dplug.core.nogc;
import dplug.core.vec;

import auburn.dsp.iir;


nothrow: 
@nogc:


/// Downsample a signal using tuned IIR filters, using changeable-at-will oversampling.
/// This is meant for audio signals, but can also happen for control signals.
/// `IIRDownsamplerNx` should be used with the corresponding `IIRUpsamplerNx`, 
/// because their latency numbers only makes sense when added.
struct IIRDownsamplerNx
{
public:
nothrow:
@nogc:

    // Is this a currently implmented oversampling rate?
    static bool isValidOversampling(int oversampling)
    {
        return (oversampling == 1) 
            || (oversampling == 2) 
            || (oversampling == 4)
            || (oversampling == 8);
    }

    void initialize(int maxFramesInOriginalRate)
    {
        // Note: downsamplers are lazily initialized on first use
        _lastOversampling = 0;    
        _maxFramesInOriginalRate = maxFramesInOriginalRate;
    }

    static int latencySamples(float sampleRate)
    {
        // Downsamplers report latency for the whole up+down combination
        assert(IIRDownsampler2x.latencySamples(sampleRate) == 1);
        assert(IIRDownsampler4x.latencySamples(sampleRate) == 2);
        return 2;
    }

    /// Process samples.
    /// Takes one buffer of `oversampling`*`frames` samples, and output downsampled buffers of `frames` samples.
    /// Changing the oversampling live will reset internal state.
    void nextBuffer(const(float)* input, float* output, int frames, int oversampling)
    {
        assert(isValidOversampling(oversampling));

        // lazily initialized oversampling engine to be used
        if (oversampling != _lastOversampling)
        {
            if (oversampling == 1)
            {
                _delay0 = 0;
                _delay1 = 0;
            }
            else if (oversampling == 2)
            {
                _delay0 = 0;
                _downsampler2x.initialize();
            }
            else if (oversampling == 4)
            {
                _delay0 = 0;
                _downsampler4x.initialize(_maxFramesInOriginalRate);
            }
            else if (oversampling == 8)
            {
                _downsampler8x.initialize(_maxFramesInOriginalRate);  
            }
            _lastOversampling = oversampling;
        }

        switch(oversampling)
        {
        case 1:
            for (int n = 0; n < frames; ++n)
            {
                output[n] = _delay0;
                _delay0 = _delay1;
                _delay1 = input[n];
            }
            break;
        case 2:
            _downsampler2x.nextBuffer(input, output, frames);
            // Delay by 1 samples to match others delay
            for (int n = 0; n < frames; ++n)
            {
                float last = output[n];
                output[n] = _delay0;
                _delay0 = last;
            }
            break;
        case 4:
            _downsampler4x.nextBuffer(input, output, frames);
            // Delay by 1 samples to match others delay
            for (int n = 0; n < frames; ++n)
            {
                float last = output[n];
                output[n] = _delay0;
                _delay0 = last;
            }
            break;
        case 8:
            _downsampler8x.nextBuffer(input, output, frames);
            break;
        default:
            assert(false);
        }
    }

    int _lastOversampling;
    int _maxFramesInOriginalRate;
    float _delay0, _delay1;
    IIRDownsampler2x _downsampler2x;
    IIRDownsampler4x _downsampler4x;
    IIRDownsampler8x _downsampler8x;
}


/// Just a stereo wrapper for the same thing.
struct StereoDownsamplerNx
{
public:
nothrow:
@nogc:
    void initialize(int maxFramesInOriginalRate)
    {
        _downsamplerLeft.initialize(maxFramesInOriginalRate);
        _downsamplerRight.initialize(maxFramesInOriginalRate);
    }

    /// Takes a buffers of oversampling*`frames` samples, and output downsampled buffers of `frames` samples.
    /// Changing the oversampling live will reset things to zero.
    /// outL and outR can be the same memory.
    /// inL and inR can be the same memory.    
    void nextBuffer(const(float)* inL, float* outL, 
                    const(float)* inR, float* outR, int frames, int oversampling)
    {
        _downsamplerLeft.nextBuffer(inL, outL, frames, oversampling);
        _downsamplerRight.nextBuffer(inR, outR, frames, oversampling);
    }

    static int latencySamples(float sampleRate)
    {
        return IIRDownsamplerNx.latencySamples(sampleRate);
    }

private:
    IIRDownsamplerNx _downsamplerLeft;
    IIRDownsamplerNx _downsamplerRight;
}



/// Mystery downsampler from GFM distort, unknown origin
/// Sounds pretty much like a sinc downsampling, except min-phase.
/// Clearly second order...
struct IIRDownsampler2x
{
public:
nothrow:
@nogc:

    void initialize()
    {    
        _a0 = 0;
        _a1 = 0;
        _a2 = 0;
        _b0 = 0;
        _b1 = 0;
        _b2 = 0;
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Downsamplers report latency for the whole up+down combination
        return 1; // Note: actually it's 0.5, and account for the 0.5 in IIRUpsampler2x => warning coupling
    }

    /// Downsample a buffer by 2.
    /// `input` and `output` may point to the same buffer.
    void nextBuffer(const(float)* input, float* output, int frames)
    {
        double a0 = _a0;
        double a1 = _a1;
        double a2 = _a2;
        double b0 = _b0;
        double b1 = _b1;
        double b2 = _b2;

        for (int i = 0; i < frames; ++i)
        {
            a0 = a1;
            a1 = a2;
            a2 = input[i*2] * 0.3445081380659771;
            b0 = b1;
            b1 = b2;
            b2 = a0 + 2 * a1 + a2 - 0.3139684953 * b0 - 0.0640640570f * b1;
            output[i] = b2;
            a0 = a1;
            a1 = a2;
            a2 = input[i*2+1] * 0.3445081380659771;
            b0 = b1;
            b1 = b2;
        }

        _a0 = a0;
        _a1 = a1;
        _a2 = a2;
        _b0 = b0;
        _b1 = b1;
        _b2 = b2;
    }

private:
    double _a0, _a1, _a2;
    double _b0, _b1, _b2;
}

// Not tuned at all
struct IIRDownsampler4x
{
public:
nothrow:
@nogc:

    void initialize(int maxFramesInOriginalRate)
    {
        // Base proposal
        _iir.initialize( IIRDescriptor(IIRType.lowPass, 
                                       IIRDesign.butterworth)
                        .withOrder(3)
                        .withCutoffHz(0.125f * 1.0f), 1.0f);
        _filtered.reallocBuffer(maxFramesInOriginalRate * 4);
    }

    ~this()
    {
        _filtered.reallocBuffer(0);
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Downsamplers report latency for the whole up+down combination
        return 2;
    }

    // Input is frames*4 samples, output is frames samples
    void nextBuffer(const(float)* input, float* output, int frames)
    {
        _iir.nextBuffer(input, _filtered.ptr, frames*4);
        for(int i = 0; i < frames; ++i)
            output[i] = 0.25f * (_filtered[i * 4 + 0] + _filtered[i * 4 + 1] 
                               + _filtered[i * 4 + 2] + _filtered[i * 4 + 3]);
    }

private:
    IIRFilter!4 _iir;
    float[] _filtered;
}



// Not tuned at all
struct IIRDownsampler8x
{
public:
nothrow:
@nogc:

    void initialize(int maxFramesInOriginalRate)
    {
        // Base proposal
        _iir.initialize( IIRDescriptor(IIRType.lowPass, 
                                       IIRDesign.butterworth)
                         .withOrder(4)
                         .withCutoffHz(0.0625f * 1.0f), 1.0f); // 0.625 = 0.5 / 8
        _filtered.reallocBuffer(maxFramesInOriginalRate * 8);
    }

    ~this()
    {
        _filtered.reallocBuffer(0);
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Downsamplers report latency for the whole up+down combination.
        return 2;
    }

    // Input is `frames*8` samples, output is `frames` samples
    void nextBuffer(const(float)* input, float* output, int frames)
    {
        _iir.nextBuffer(input, _filtered.ptr, frames*8);
        for(int i = 0; i < frames; ++i)
        {
            output[i] = 0.125f * 
            (_filtered[i * 8 + 0] + _filtered[i * 8 + 1] + _filtered[i * 8 + 2] + _filtered[i * 8 + 3]
             + _filtered[i * 8 + 4] + _filtered[i * 8 + 5] + _filtered[i * 8 + 6] + _filtered[i * 8 + 7]);
        }
    }

private:
    IIRFilter!4 _iir;
    float[] _filtered;
}
