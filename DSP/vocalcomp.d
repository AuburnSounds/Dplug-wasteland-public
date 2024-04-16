/**
Copyright: Copyright Guillaume Piolat 2024
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module vocalcomp;

import dplug.core;
import dplug.dsp;

// Idealized pair of 1176-style compressor with a LA2A style compressor after,
// tuned for voice. Or something that looks like it heavily.
// - feedback-design with several iterations for fast attacks
// - triple envelope release (one fast, one medium, one slow)
// - no program-dependency
// - hard-knee (unlike the original units)
// - 100% stereo-linked
// - 1-1 and 2-2
//
// Note: soft-knee attempt was a failure, see commit log
// the problem is that the polynomial approximation isn't good in linear domain.
// Would be a better fit if this was computed in dB domain instead.
//
// Note: it's tempting to put both compressors in the feedback loop, to share 
// the feedback iterations. But this is not a win sonically.
//
// SOUND: there is no program dependency at all
// SOUND: a separate range and threshold diff for the 2nd envelope of the 
//        LA2A emulation.
struct SimpleCompressor
{
public:
nothrow:
@nogc:

    enum int MAX_CHANNELS = 2;

    void initialize(float sampleRate, int maxFrames, int numChans)
    {
        _sr = sampleRate;
        _numChans = numChans;
        _gainf  = _gains1 = _gains2 = 1;
        _levelf = _levels = 0;
        _sidechain.reallocBuffer(maxFrames);

        
        _sidechainFilter.initialize();
    }

    ~this()
    {
        _sidechain.reallocBuffer(0);
    }

    // Advised wet = 0.98f

    void nextBuffer(double** inoutSamples, // 1 or 2 pointers
                    int frames,
                    float thre_dB, // threshold in dB
                    double makeup_linear,
                    double wet,
                    float tune0,
                    float tune1) 
    {


        _attDF_fast  = expDecayFactor(FAST_ATT_SECS,  _sr*FAST_STAGES);
        _relDF_fast  = expDecayFactor(FAST_REL_SECS,  _sr*FAST_STAGES);
        _attDF_slow  = expDecayFactor(SLOW_ATT_SECS,  _sr*SLOW_STAGES);
        _rel1DF_slow = expDecayFactor(SLOW_REL1_SECS, _sr*SLOW_STAGES);
        _rel2DF_slow = expDecayFactor(SLOW_REL2_SECS, _sr*SLOW_STAGES);

        double threFast = convertDecibelToLinearGain(thre_dB);
        double threSlow = convertDecibelToLinearGain(thre_dB + THRESH_DIFF);

        double invCompThreshold_fast = 1.0 / threFast;
        double invCompThreshold_slow = 1.0 / threSlow;
     
        const double minGainf = convertDecibelToLinearGain(-FAST_RANGE);
        const double minGains = convertDecibelToLinearGain(-SLOW_RANGE);

        // stereo-link
        if (_numChans == 1)
            _sidechain[0..frames] = inoutSamples[0][0..frames];
        else
            _sidechain[0..frames] = (inoutSamples[0][0..frames] 
                                   + inoutSamples[1][0..frames]) * 0.5;

        // Note: there is no sidechain. It tend to sound worse on recorded 
        // vocals since bass content being sidechain will help reducing plosives, etc.

        // 1. Compute gain reduction, puts it in _sidechain

        for (int n = 0; n < frames; ++n)
        {
            // Feedback topology
            double inputSample = _sidechain[n];

            // take energy, removes one discontinuity
            // Now, I don't think it changes anything actually.
            double abs_input = fast_fabs(inputSample);

            // 1176 emulation.
            double gain = _gainf;
            for(int N = 0; N < FAST_STAGES; ++N)
            {
                double sample = abs_input * gain;
                _levelf += (sample - _levelf) * _attDF_fast;
                double t = _levelf * invCompThreshold_fast;
                double target = fastRatio4GainReduction(t);
                if (t < 1)          target = 1;
                if (target < minGainf) target = minGainf;
                if (target < gain)
                    gain = target;
                gain = gain + (1.0f - gain) * _relDF_fast;
            }
            _gainf = gain;
            abs_input *= gain; // 2nd compressor gets attenuated input

            double gain1 = _gains1;
            double gain2 = _gains2;
            double gainMix = gain1 * ENV1_MIX + gain2 * ENV2_MIX;

            // LA-2A emulation
            for(int N = 0; N < SLOW_STAGES; ++N)
            {
                double sample = abs_input * gainMix;
                _levels  += (sample - _levels) * _attDF_slow;
                double t = _levels * invCompThreshold_slow;
                double target = fastRatio6GainReduction(t);
                if (t < 1)          target = 1;
                if (target < minGains) target = minGains;
                if (target < gain1) gain1 = target;
                if (target < gain2) gain2 = target;
                gain1 = gain1 + (1.0f - gain1) * _rel1DF_slow;
                gain2 = gain2 + (1.0f - gain2) * _rel2DF_slow;
                gainMix = gain1 * ENV1_MIX + gain2 * ENV2_MIX;
            }
            _gains1 = gain1;
            _gains2 = gain2;
            _sidechain[n] = gain * gainMix * makeup_linear;
        }

        // 2. Apply GR
        for (int chan = 0; chan < _numChans; ++chan)
        {
            for (int n = 0; n < frames; ++n)
            {
                _sidechain[n] = 1.0 * (1.0 - wet) + _sidechain[n] * wet;
                inoutSamples[chan][n] *= _sidechain[n];
            }
        }
    } 

private:
    float  _sr;
    int    _numChans;   // number of channels, 1 or 2
    double _gainf;      // fast comp gain reduction
    double _gains1;     // slow comp gain reduction, 1st env
    double _gains2;     // slow comp gain reduction, 2nd env
    double _levelf;     // level estimation, fast comp
    double _levels;     // level estimation, slow comp
    double[] _sidechain;
    double _attDF_fast;
    double _relDF_fast;
    double _attDF_slow;
    double _rel1DF_slow;
    double _rel2DF_slow;

    BiquadDelay _sidechainFilter;

  

    // fast pow(w, FAST_EXPONENT), based on FAST_EXPONENT being -0.75
    double fastRatio4GainReduction(double x)
    {
        assert(x >= 0); // the only ill-case is x == 0, full silence
        x += double.min_normal;
        double sqrt_x = fast_sqrt(x); // x^0.5
        double sqrt_sqrt_x = fast_sqrt(sqrt_x); // x^0.25
        return 1.0 / (sqrt_x * sqrt_sqrt_x);
    }

    // fast pow(w, SLOW_EXPONENT), based on SLOW_EXPONENT being -0.833
    // Decomposing it in: -0.833 ~ (-0.5 -0.25 -0.125 + 0.0625) = -0.8125
    // Making it a ratio roughly equal to 5.33 instead of 6. Oh well.
    double fastRatio6GainReduction(double x)
    {
        assert(x >= 0); // the only ill-case is x == 0, full silence
        x += double.min_normal;
        double sqrt_x  = fast_sqrt(x);        // x^0.5
        double sqrt4_x = fast_sqrt(sqrt_x);   // x^0.25
        double sqrt8_x = fast_sqrt(sqrt4_x);  // x^0.125
        double sqrt16_x = fast_sqrt(sqrt8_x); // x^0.0625
        return sqrt16_x / (sqrt_x * sqrt4_x * sqrt8_x);
    }

    // <tuning constants>
    // This is pretty good sounding!
    // Part of the challenge in tuning this is that completely raw vocals
    // need different strategies than already compressed vocals.
    // This was tuned on both at once to accomodate whatever comes our way.
    enum float  FAST_ATT_SECS  = 0.004 * (0.5 + 0.63); // Critical, do not lower, looses life. Seems optimal.
    enum float  FAST_REL_SECS  = 0.045 * (0.5 + 0.5); // Seems optimal.
    enum float  FAST_RATIO     = 4;     // Match other emulations
    enum float  FAST_RANGE     = 6.75;
    enum int    FAST_STAGES    = 8;     // Improves attacks and plosives. Higher probably better still.
    enum float  SLOW_RATIO     = 6;     // 4:1 more life, 6:1 more control
    enum float  SLOW_ATT_SECS  = 0.00312 * (0.5 + 0.15);
    enum float  SLOW_REL1_SECS = 0.0603 * (0.5 + 0.62);
    enum float  SLOW_REL2_SECS = 0.7462 * (0.5 + 0.9);
    enum int    SLOW_STAGES    = 8;     // Same as the other stage.
    enum float  SLOW_RANGE     = 8.36;  // Possibly, this could go further.
    enum double ENV1_MIX       = 0.5875 * (0.5 + 0.71);
    enum double ENV2_MIX       = 1.0 - ENV1_MIX;
    enum float  THRESH_DIFF    = -11.00 * 2 * 0.33; // Balance quite hard. Tuned thrice.
    enum float FAST_EXPONENT   = 1.0 / FAST_RATIO - 1;
    enum float SLOW_EXPONENT   = 1.0 / SLOW_RATIO - 1;
    // </tuning constants>
}