/**
Everything oversampling.
Everything here is coupled with undersampling.d

Copyright: Guillaume Piolat 2015-2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.dsp.oversampling;

import std.math;

import dplug.core.nogc;
import dplug.core.vec;

import auburn.dsp.iir;

nothrow: 
@nogc:

/// Upsample a signal using tuned IIR filters, using changeable-at-will oversampling.
/// This is meant for audio signals, but can also happen for control signals.
/// `IIRUpsamplerNx` should be used with the corresponding `IIRDownsamplerNx`, 
/// because their latency numbers only makes sense when added.
struct IIRUpsamplerNx
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

    void initialize()
    {
        // Note: upsamplers are lazily initialized on first use
        _lastOversampling = 0;
    }

    static int latencySamples(float sampleRate)
    {
        // Upsamplers report wrong latency, but corresponding downsamplers report the correct one for both
        return 0;
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
            if (oversampling == 2)
                _upsampler2x.initialize();
            else if (oversampling == 4)
                _upsampler4x.initialize();
            else if (oversampling == 8)
                _upsampler8x.initialize();
            _lastOversampling = oversampling;
        }

        switch(oversampling)
        {
            case 1:
            {
                output[0..frames] = input[0..frames];
                break;
            }
            case 2:
            {
                _upsampler2x.nextBuffer(input, output, frames);
                break;
            }
            case 4:
            {
                _upsampler4x.nextBuffer(input, output, frames);
                break;
            }
            case 8:
            {
                _upsampler8x.nextBuffer(input, output, frames);
                break;
            }
            default:
                assert(false);
        }
    }

    int _lastOversampling;
    IIRUpsampler2x _upsampler2x;
    IIRUpsampler4x _upsampler4x;
    IIRUpsampler8x _upsampler8x;
}



/// Just a stereo wrapper for the same thing.
struct StereoUpsamplerNx
{
public:
nothrow:
@nogc:
    void initialize()
    {
        _upsamplerLeft.initialize();
        _upsamplerRight.initialize();
    }

    /// Takes a buffer of `frames` samples, outputs a buffer of `oversampling`*`frames` samples.
    /// Changing the oversampling live will reset things to zero.
    /// `outL` and `outR` can be the same memory.
    /// `inL` and `inR` can be the same memory.    
    void nextBuffer(const(float)* inL, float* outL, 
                    const(float)* inR, float* outR, int frames, int oversampling)
    {
        _upsamplerLeft.nextBuffer(inL, outL, frames, oversampling);
        _upsamplerRight.nextBuffer(inR, outR, frames, oversampling);
    }

    static int latencySamples(float sampleRate)
    {
        return IIRUpsamplerNx.latencySamples(sampleRate);
    }

private:
    IIRUpsamplerNx _upsamplerLeft;
    IIRUpsamplerNx _upsamplerRight;
}


// Would be interesting to explore elliptic design for further improvement
struct IIRUpsampler2x
{
nothrow:
@nogc:

    void initialize()
    {
        // Proposal A
        // Note: we offset the cutoff to sounds more digital vs better filter behaviour
        // this allow to have a larger ripple for chebyshev I designs
        _iir.initialize( IIRDescriptor(IIRType.lowPass, 
                                       IIRDesign.chebyshevI)  // I just like how they sound in general
                         .withOrder(2)                        // because it seems an upsampling filter don't need to reject that much?
                         .withPassBandRippleDb(1.0f)          // this is a tradeoff of rejection vs ripple, tuned roughly
                         .withCutoffHz(0.25f * 1.05f), 1.0f); // move problematic high-shelf higher

        // PERF: turn this into a regular BiquadDelay because this is just a LP6, nothing "chebyshev" in it
        _iir2.initialize( IIRDescriptor(IIRType.lowPass, 
                                        IIRDesign.chebyshevI)
                          .withOrder(1)
                          .withPassBandRippleDb(2.0f) // unused since order 1
                          .withCutoffHz(0.25f * 1.6f), 1.0f);  // tuned twice, introduce some phase change
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Upsamplers report wrong latency, but corresponding downsamplers report the correct one for both
        // Here, it is really 0.5
        return 0; 
    }

    void nextBuffer(const(float)* input, float* output, int frames)
    {
        // sample and hold
        foreach(i; 0..frames)
        {
            output[2*i]= input[i];
            output[2*i+1] = input[i];
        }

        _iir.nextBuffer(output, output, frames*2);
        _iir2.nextBuffer(output, output, frames*2);
    }

    IIRFilter!2 _iir;

    // More filtering to improve on aliasing
    IIRFilter!2 _iir2;
}



// Idea: 3P cheb I + 2P butterworth
/// Tuned around our best effort `IIRUpsampler2x` and to be tuned for 4x.
/// Could probably be made more efficient.
struct IIRUpsampler4x
{
nothrow:
@nogc:

    void initialize()
    {
        _iir.initialize( IIRDescriptor(IIRType.lowPass, 
                                       IIRDesign.chebyshevI)  // I just like how they sound in general
                         .withOrder(3)                        // because it seems an upsampling filter don't need to reject that much?
                        .withPassBandRippleDb(0.4f)          // this is a tradeoff of rejection vs ripple, tuned roughly
                        .withCutoffHz(0.125f * 1.05f), 1.0f); // same as IIRUpsampler2x, change with ripple

        _iir2.initialize( IIRDescriptor(IIRType.lowPass, 
                                        IIRDesign.butterworth)
                            .withOrder(2)
                            .withCutoffHz(0.125f * 1.05f), 1.0f);
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Upsamplers report wrong latency, but corresponding downsamplers report the correct one for both
        return 0;
    }

    void nextBuffer(const(float)* input, float* output, int frames)
    {
        // sample and hold
        foreach(i; 0..frames)
        {
            output[4*i]= input[i]; // does sample-holding make any sense at all?
            output[4*i+1] = input[i];
            output[4*i+2] = input[i];
            output[4*i+3] = input[i];
        }

        _iir.nextBuffer(output, output, frames*4);
        _iir2.nextBuffer(output, output, frames*4);
    }

    // More filtering to improve on aliasing
    IIRFilter!4 _iir;
    IIRFilter!2 _iir2;
}

// TODO: this is just arbitrary for now
struct IIRUpsampler8x
{
nothrow:
@nogc:

    void initialize()
    {
        _iir.initialize( IIRDescriptor(IIRType.lowPass, 
                                       IIRDesign.chebyshevI)  // I just like how they sound in general
                         .withOrder(3)                        // because it seems an upsampling filter don't need to reject that much?
                         .withPassBandRippleDb(0.125f)          // this is a tradeoff of rejection vs ripple, tuned roughly
                         .withCutoffHz(0.0625f * 1.0f), 1.0f);

        _iir2.initialize( IIRDescriptor(IIRType.lowPass, 
                                        IIRDesign.butterworth)
                         .withOrder(5)
                         .withCutoffHz(0.0625f * 1.0f), 1.0f);
    }

    @disable this(this);

    static int latencySamples(float sampleRate)
    {
        // Upsamplers report wrong latency, but corresponding downsamplers report the correct one for both
        return 0;
    }

    void nextBuffer(const(float)* input, float* output, int frames)
    {
        // sample and hold
        foreach(i; 0..frames)
        {
            float inp = input[i];
            output[8*i]= inp; // does sample-holding make any sense at all?
            output[8*i+1] = inp;
            output[8*i+2] = inp;
            output[8*i+3] = inp;
            output[8*i+4] = inp;
            output[8*i+5] = inp;
            output[8*i+6] = inp;
            output[8*i+7] = inp;
        }

        _iir.nextBuffer(output, output, frames*8);
        _iir2.nextBuffer(output, output, frames*8);
    }

    // More filtering to improve on aliasing
    IIRFilter!4 _iir;
    IIRFilter!6 _iir2;
}


