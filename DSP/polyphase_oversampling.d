/// Upsample through a set of polyphase filters
/// Problem is, to sound not metalic it needs to be min-phase and requires quite a lot of samples.
/// So IIR is probably where it's at.
/// Copyright: Guillaume Piolat 2019.
/// License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
struct PolyphaseUpsampler
{
public:
nothrow:
@nogc:

    /// Initialize the PolyphaseUpsampler with a lowpass windowed FIR obtained with given `ripple` and `transitionWidthHz`.
    /// You can get to lower orders if those valued are tuned to your needs.
    /// Note: `minPhase` being `true` is discouraged since this will once again delay the bass against the highs,
    /// while upsampling isn't that expensive.
    void initialize(float sampleRate, int oversampling = 2, bool minPhase = false, float ripple = 0.30, float transitionWidthHz = 1000)
    {
        float kaiserAlpha;
        designTaps(sampleRate, ripple, transitionWidthHz, oversampling, _taps, kaiserAlpha);

        _tapsPerPolyphaseFiler = _taps / oversampling;
        _oversampling = oversampling;
        _lowpassImpulse.reallocBuffer(_taps);

        // Generate the FIR impulse
        {
            // MAYDO should we offset the cutoff?
            float cutoffNormalized = 0.5 / oversampling;
            assert(cutoffNormalized >= 0);
            assert(cutoffNormalized < 0.5);
            generateLowpassImpulse(_lowpassImpulse[], cutoffNormalized, 1.0);

            // Always use a kaiser window with alpha provided by the design method
            auto windowDesc = WindowDesc(WindowType.kaiserBessel, WindowAlignment.right, kaiserAlpha);

            multiplyByWindow(_lowpassImpulse[], windowDesc);

            if (minPhase)
            {
                _tempStorage.reallocBuffer( tempBufferSizeForMinPhase(_lowpassImpulse[]) );
                minimumPhaseImpulse!float(_lowpassImpulse[], _tempStorage);
            }

            // In order for the upsampler to have unity gain, we must multipy by the oversampling factor
            // since the impulse will be sampled by polyphase.
            foreach(ref sample; _lowpassImpulse)
                sample *= oversampling;
        }

        _delayline.initialize(_tapsPerPolyphaseFiler);
        _minPhase = minPhase;
    }

    static void designTaps(float sampleRate, float ripple, float transitionWidthHz, int oversampling, out int numTaps, out float kaiserAlpha)
    {
        int order;
        float kaiserBeta;
        designParametersKaiserFIR(ripple, transitionWidthHz, sampleRate, order, kaiserBeta);

        int multipleOf = 2 * oversampling;
        while((order % multipleOf) != 0)
            order++;

        numTaps = order;
        kaiserAlpha = kaiserBeta / PI;
    }

    /// Returns: Number of samples of delay added.
    static int latencySamples(float sampleRate, int oversampling, bool minPhase,  float ripple, float transitionWidthHz )
    {
        if (minPhase)
            return 0; // phase isn't linear in that case

        int taps;
        float kaiserAlpha;
        designTaps(sampleRate, ripple, transitionWidthHz, oversampling, taps, kaiserAlpha);
        
        // Note: divide by 2 because supposed linear-phase hence symmetric.
        //       divide by oversampling because latency is given in original space.
        int multipleOf = 2 * oversampling;
        assert((taps % multipleOf) == 0);
        return taps / multipleOf;
    }

    ~this()
    {
        _lowpassImpulse.reallocBuffer(0);
        _tempStorage.reallocBuffer(0);
    }

    float[] impulse()
    {
        return _lowpassImpulse;
    }

    @disable this(this);

    /// For each input sample, there are _oversampling output samples.
    /// Note: output[0]            is considered aligned on input samples, while 
    ///       output[i] with i > 0 do not correspond to a sample in the input.
    void nextSample(float input, float* output) nothrow @nogc
    {
        _delayline.feedSample(input);

        for (int o = 0; o < _oversampling; ++o)
        {
            float sum = 0;
            for (int i = 0; i < _tapsPerPolyphaseFiler; ++i)
                sum += _lowpassImpulse.ptr[i * _oversampling + o] * _delayline.sampleFull(i);
            output[o] = sum;
        }
    }

    /// Process input buffer and generates _(oversampling * frames) output samples.
    /// `input` and `output` cannot be the same buffer, else output samples will overrun input samples.
    void nextBuffer(const(float)* input, float* output, int frames)
    {
        int oversampling = _oversampling;
        for(int n = 0; n < frames; ++n)
        {
            _delayline.feedSample(input[n]);

            for (int o = 0; o < oversampling; ++o)
            {
                float sum = 0;
                for (int i = 0; i < _tapsPerPolyphaseFiler; ++i)
                    sum += _lowpassImpulse.ptr[i * oversampling + o] * _delayline.sampleFull(i);
                output[n * oversampling + o] = sum;
            }
        }
    }

private:
    int _taps;
    int _tapsPerPolyphaseFiler; // I guess this is the real quality of the upsampling
    float[] _lowpassImpulse; // contains all coefficients
    int _oversampling;
    Delayline!float _delayline;
    cfloat[] _tempStorage;
    bool _minPhase;
}


/// Design a FIR window with desired transition bands and ripple.
/// Returns: a FIR order `M` and a Kaiser window parameters `kaiserBeta`.
/// See_also: http://www.labbookpages.co.uk/audio/firWindowing.html#kaiser
void designParametersKaiserFIR(float ripple,
                               float transitionWidthHz,
                               float sampleRate,
                               out int M,
                               out float kaiserBeta)
{
    double A = -20 * log10(ripple);
    double tw = 2 * PI * transitionWidthHz / sampleRate;

    if (A > 21)
        M = cast(int)ceil((A - 7.95)/(2.285*tw));
    else
        M = cast(int)ceil(5.79 / tw);

    if (A <= 21)
        kaiserBeta = 0;
    else if (A > 50)
        kaiserBeta = 0.1102 * (A - 8.7);
    else
        kaiserBeta = 0.5842 * pow(A - 21, 0.4) + 0.07886 * (A - 21);
}

/// Downsample with a FIR, most common
struct FIRDownsampler
{
public:
nothrow:
@nogc:

    void initialize(int downsampling, 
                    int taps, 
                    bool minPhase = false, 
                    WindowDesc windowDesc = WindowDesc(WindowType.hann, WindowAlignment.right) )
    {
        assert(taps % (2 * downsampling) == 0); // else latency would be non-integer in output samplerate
        _taps = taps;
        _downsampling = downsampling;
        _lowpassImpulse.reallocBuffer(taps);


        float cutoffNormalized = 0.5 / downsampling;
        assert(cutoffNormalized >= 0);
        assert(cutoffNormalized < 0.5);
        generateLowpassImpulse(_lowpassImpulse, cutoffNormalized, 1.0);

        multiplyByWindow(_lowpassImpulse, windowDesc);

        if (minPhase)
        {
            _tempStorage.reallocBuffer( tempBufferSizeForMinPhase(_lowpassImpulse[]) );
            minimumPhaseImpulse!float(_lowpassImpulse[], _tempStorage);
        }

        _delayline.initialize(taps + downsampling - 1);
        _minPhase = minPhase;
    }

    /// Returns: Number of samples of delay added, in terms of the output sample-rate.
    int latency()
    {
        if (_minPhase)
            return 0; // phase isn't linear in that case

        return _taps / (2 * _downsampling);
    }

    ~this()
    {
        _lowpassImpulse.reallocBuffer(0);
        version(minPhaseDownsampling)
            _tempStorage.reallocBuffer(0);
    }

    @disable this(this);

    /// For _downsampling input samples, there are 1 output sample
    /// Note: that output sample is temporally aligned with input[0].
    float nextSample(float* input) nothrow @nogc
    {
        foreach(int o; 0.._downsampling)
            _delayline.feedSample(input[o]);

        // A bit tricky for latency:
        //
        // Input is 
        //      x...x...x...x...
        //
        // So in the delay-line reversed:
        //      ...x...x...x...x
        //
        // We wan't to convolve with an impulse whose center is at tap/2.
        //
        //      01234567
        //          ^center
        // 
        // So without delay this would make:
        //      ...x...x...x...x
        //      01234567
        //          ^no aligned with input samples
        //
        // We introduce (downsampling - 1) samples of delay in oversampled space, to avoid this latency.
        //      ...x...x...x...x
        //      ==>01234567
        //      ^delay ^centered on output samples

        double sum = 0;
        int delayForCompensation = _downsampling - 1;
        for (int i = 0; i < _taps; ++i)
            sum += _lowpassImpulse.ptr[i] * _delayline.sampleFull(i + delayForCompensation);
        return sum;
    }

private:
    int _taps;
    int _tapsPerPolyphaseFiler; // I guess this is the real quality of the upsampling
    float[] _lowpassImpulse; // contains all coefficients
    int _downsampling;
    Delayline!float _delayline;
    cfloat[] _tempStorage;
    bool _minPhase; // min-phase or linear phase?
}
