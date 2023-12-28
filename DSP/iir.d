/*

"A Collection of Useful C++ Classes for Digital Signal Processing"
By Vincent Falco

Official project location:
http://code.google.com/p/dspfilterscpp/

See Documentation.cpp for contact information, notes, and bibliography.

--------------------------------------------------------------------------------

License: MIT License (http://www.opensource.org/licenses/mit-license.php)
Copyright (c) 2009 by Vincent Falco
Copyright (c) 2018 by Guillaume Piolat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

/// Basic IIR design.
module auburn.dsp.iir;

import core.stdc.complex: cabs, cexp;

import std.math;

import dplug.core.complex;
import dplug.core.math;
import dplug.dsp.iir;

nothrow:
@nogc:

// DMD with a 32-bit target uses the FPU
version(X86)
{
    version(DigitalMars)
    {
        version = killDenormals;
    }
}


/// The type of IIR filter.
enum IIRType
{
    lowPass, // FUTURE: add more types
    highPass
}

/// Poles and zero placement method.
// FUTURE: add more designs
enum IIRDesign
{
    butterworth,
    bessel,
    chebyshevI,
    chebyshevII,
}

/// Fully describes an IIR filter, regardless of the sampling rate though.
struct IIRDescriptor
{
public:
nothrow:
@nogc:

    this(IIRType type, 
         IIRDesign design, 
         int order = -1, 
         float cutoffHz = float.nan,
         float passBandRippleDb = float.nan,
         float stopBandAttenuationDb = float.nan)
    {
        this.type = type;
        this.design = design;
        this.order = order;
        this.cutoffHz = cutoffHz;
        this.passBandRippleDb = passBandRippleDb;
        this.stopBandAttenuationDb = stopBandAttenuationDb;
    }

    /// Type of this filter.
    IIRType type;

    /// Choose placement method for poles and zeroes.    
    IIRDesign design;
    
    /// Order of the filter, ie. number of poles.
    int order = -1;

    /// Cutoff frequency in Hz.
    float cutoffHz = float.nan;

    /// Pass band max ripple (in dB). Used by Chebyshev I designs.
    float passBandRippleDb = float.nan;

    /// Stop band attenuation (in dB). Used by Chebyshev II designs.
    float stopBandAttenuationDb = float.nan;

    /// Convenience setter for filter order (number of poles).
    IIRDescriptor withOrder(int order)
    {
        this.order = order;
        return this;
    }

    /// Convenience setter for cutoff frequency parameter.
    IIRDescriptor withCutoffHz(float cutoffHz)
    {
        this.cutoffHz = cutoffHz;
        return this;
    }

    /// Convenience setter for passband attenuation parameter.
    IIRDescriptor withPassBandRippleDb(float passBandRippleDb)
    {
        this.passBandRippleDb = passBandRippleDb;
        return this;
    }

    /// Convenience setter for stopband attenuation parameter (eg: 48 dB).
    IIRDescriptor withStopBandAttenuationDb(float stopBandAttenuationDb)
    {
        this.stopBandAttenuationDb = stopBandAttenuationDb;
        return this;
    }
}

/// IIRFilter, hold state and coefficients.
/// Modulation not supported.
/// Realization is always through biquads.
/// Such a filter can host any design up to `maxPoles` poles and `maxPoles` zeroes.
struct IIRFilter(int maxPoles = 4)
{
public:
nothrow:
@nogc:
    // Each biquad stage can hold 0 to 2 poles, and 0 to 2 zeroes.
    enum numBiquadStages = (maxPoles + 1)/2;

    /// Realizes a IIR filter, and clear state.
    void initialize(IIRDescriptor desc, float sampleRate)
    {
        // Finds poles and zeros in s-plane.
        IIRLayout!maxPoles analog;
        if (desc.type == IIRType.lowPass || desc.type == IIRType.highPass)
            generateSPlaneHalfBandLowPass(desc.design, 
                                          desc.order, 
                                          desc.passBandRippleDb,
                                          desc.stopBandAttenuationDb,                                          
                                          analog);
        else
            assert(false, "Unsupported IIRType");

        // Transform into z-plane.
        IIRLayout!maxPoles digital;
        poleFilterTransform(&analog, &digital, desc, sampleRate);

        generateCoefficients(digital);

        // Clear delay state.
        clearState();
    }

    /// Puts the IIR filter in the state as if it would have ingested only zeroes.
    void clearState()
    {
        foreach(i; 0.._usedStages)
            _stages[i].initialize();
    }

    /// Process one sample.
    float nextSample(float input)
    {
        int numStages = _usedStages;
        double x = input;
        for(int i = 0; i < numStages; ++i)
            x = _stages[i].nextSample(x, _coeffs[i]);
        return x;
    }

    /// Process one buffer.
    /// `input` and `output` can be identical.
    void nextBuffer(const(float)* input, float* output, int samples)
    {
        int numStages = _usedStages;
        assert(numStages > 0);
        const(BiquadCoeff*) pCoeff = _coeffs.ptr;
        BiquadDelay* stages = _stages.ptr;
        stages[0].nextBuffer(input, output, samples, pCoeff[0]);
        for(int i = 1; i < numStages; ++i)
        {   
            stages[i].nextBuffer(output, output, samples, pCoeff[i]);
        }
    }

    /// Process one buffer with a constant DC input.
    /// `input` and `output` can be identical.
    void nextBuffer(float input, float* output, int samples)
    {
        int numStages = _usedStages;
        assert(numStages > 0);
        const(BiquadCoeff*) pCoeff = _coeffs.ptr;
        BiquadDelay* stages = _stages.ptr;
        stages[0].nextBuffer(input, output, samples, pCoeff[0]);
        for(int i = 1; i < numStages; ++i)
        {
            stages[i].nextBuffer(output, output, samples, pCoeff[i]);
        }
    }

    /// Initialize filter so that first output sample is around `dcOut`.
    /// Useful for lowpass filters used as smoothers.
    void setStateDC(double dcOut)
    {
        // Note: we simulate infinite output dcOut, what is the infinite value that gives it at input?
        // Given the realization, that gives the equation:
        //    dcIn * (stage[0] + stage[1] + stage[2]) = (1 + stage[3] + stage[4]) * dcOut

        for(int stage = _usedStages - 1; stage >= 0; --stage)
        {
            BiquadCoeff coeff = _coeffs[stage];
            double dcIn = (1 + coeff[3] + coeff[4]) * dcOut / (coeff[0] + coeff[1] + coeff[2]);

            _stages[stage]._x0 = dcIn;
            _stages[stage]._x1 = dcIn;
            _stages[stage]._y0 = dcOut; // initialize state
            _stages[stage]._y1 = dcOut; // initialize state

            dcOut = dcIn;
        }
    }

private:
    int _usedStages;
    BiquadCoeff[numBiquadStages] _coeffs;
    BiquadDelay[numBiquadStages] _stages;

    void generateCoefficients(ref IIRLayout!maxPoles digital)
    {
        int M = digital.numZeroes;
        int N = digital.numPoles;
        assert(M == N, "Different number of zeroes and poles, not supported for now");

        _usedStages = 0;

        for(int i = 0; i + 1 < N; i += 2)
            _coeffs[_usedStages++] = biquad2Poles(digital.poles[i], digital.zeroes[i], 
                                                        digital.poles[i+1], digital.zeroes[i+1]);
        if (N & 1)
            _coeffs[_usedStages++] = biquad1Pole(digital.poles[N-1], digital.zeroes[N-1]);


        double scaleFactor = digital.normalGain / std.complex.abs( response( digital.normalW /(2 * PI) ) );
        assert(isFinite(scaleFactor), "scaleFactor is not finite, BiquadCoeff should be double[5]");
        _coeffs[0] = biquadApplyScale(_coeffs[0], scaleFactor);
    }

    // Calculate filter response at the given normalized frequency.
    BuiltinComplex!double response(double normalizedFrequency)
    {
        static BuiltinComplex!double addmul(BuiltinComplex!double c, double v, BuiltinComplex!double c1)
        {
            return BuiltinComplex!double(c.re + v * c1.re, c.im + v * c1.im);
        }

        double w = 2 * PI * normalizedFrequency;
        BuiltinComplex!double czn1 = std.complex.fromPolar (1., -w);
        BuiltinComplex!double czn2 = std.complex.fromPolar (1., -2 * w);
        BuiltinComplex!double ch = 1.0;
        BuiltinComplex!double cbot = 1.0;

        foreach(i; 0.._usedStages)
        {
            BiquadCoeff stage = _coeffs[i];
            BuiltinComplex!double cb = 1.0;
            BuiltinComplex!double ct = stage[0]; // b0
            ct = addmul (ct, stage[1], czn1); // b1
            ct = addmul (ct, stage[2], czn2); // b2
            cb = addmul (cb, stage[3], czn1); // a1
            cb = addmul (cb, stage[4], czn2); // a2
            ch   *= ct;
            cbot *= cb;
        }
        return ch / cbot;
    }
}

/// Returns: estimated latency for a bessel filter, in samples.
float estimateLatencyAtDCForBesselFilter(float cutoff, float sampleRate) pure
{
    return 0.15915*(sampleRate/cutoff);
}


/// Returns: from a passband latency, return the needed cutoff (in Hz).
float estimateBesselCutoffForLatency(float latencySamples, float sampleRate) pure
{
    float cutoffHz = (sampleRate * 0.15915) / latencySamples;
    return cutoffHz;
}



/// This is another version of `ExpSmoother`, which is going to be deprecated
/// because of useless conditionals. This one only operates on `float`.
struct OnePoleSmoother
{
public:
nothrow:
@nogc:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float samplerate, float timeAttackRelease)
    {
        _sampleRate = samplerate;

        setAttackReleaseTime(timeAttackRelease);

        assert(isFinite(_expFactor));
    }

    /// Changes attack and release time (given in seconds).
    void setAttackReleaseTime(float timeAttackRelease)
    {
        _expFactor = cast(float)(expDecayFactor(timeAttackRelease, _sampleRate));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    float nextSample(float target)
    {
        float current = _current;
        if (current != current) // NaN => initialize immediately
            current = target;

        float newCurrent = current + (target - current) * _expFactor;

        version(killDenormals)
        {
            newCurrent += 1e-18f;
            newCurrent -= 1e-18f;
        }
        _current = newCurrent;
        return _current;
    }

    /// Advance smoothing `frames` times, gives back the latest values.
    /// useful for smoothing a parameter in unknown framing conditions, without a buffer.
    float nextBuffer(float input, int frames)
    {
        // PERF: do it at once
        for (int n = 0; n < frames; ++n)
        {
            nextSample(input);
        }
        return _current;
    }

    void nextBuffer(const(float)* input, float* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    void nextBuffer(float input, float* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    float _current = float.nan;
    float _expFactor;
    float _sampleRate;
}

// Note: when it comes to delays, they are best smoothed with a LP6, it seems
static IIRDescriptor standardGainSmoother()
{
    return IIRDescriptor(IIRType.lowPass, IIRDesign.bessel).withOrder(2).withCutoffHz(30.0f);
}

/// Smoother for typical slow modulation signals (dry/wet, linear gains, etc)
struct GainSmoother
{
public:
nothrow:
@nogc:

    /// Initialize the gain smoother with unknown state conditions.
    /// this will take the first input sample.
    /// The first input sample will initialize state as if this was the expected output DC.
    void initialize(IIRDescriptor iirDescriptor, float sampleRate)
    {
        _inner.initialize(iirDescriptor, sampleRate);        
    }

    /// Initialize the gain smoother with known input conditions
    void initialize(IIRDescriptor iirDescriptor, float sampleRate, float initialValue)
    {
        assert(initialValue == initialValue); // not NaN
        _inner.initialize(iirDescriptor, sampleRate);
        setStateDC(initialValue);
    }

    void nextBuffer(float* inSamples, float* outSamples, int frames)
    {
        if (!_initialized && frames > 0)
            setStateDC(inSamples[0]);
        _inner.nextBuffer(inSamples, outSamples, frames);
    }

    void nextBuffer(float inGain, float* outSamples, int frames)
    {
        // Fill inner state information so that it generate output same as input
        if (!_initialized)
            setStateDC(inGain);
        _inner.nextBuffer(inGain, outSamples, frames);
    }

    /// Returns: estimated latency in seconds
    static float estimateLatencyAtDC()
    {
        return 0.15915f / 30.0f;
    }

private:
    IIRFilter!2 _inner;
    bool _initialized = false;

    void setStateDC(float dcOut)
    {
        _inner.setStateDC(dcOut);
        _initialized = true;
    }
}


private:


/// Holds poles and zeroes, either in s-plane or z-plane.
struct IIRLayout(int maxPoles)
{
public:
nothrow:
@nogc:
    int numZeroes = 0;
    int numPoles = 0;

    /// Gain of that filter for the passband.
    double normalGain = 1;

    /// Passband location.
    double normalW = 0;

    // Note: poles and zeroes are associated by pairs.
    // They go in the same biquad.
    BuiltinComplex!double[maxPoles] poles;
    BuiltinComplex!double[maxPoles] zeroes;  

    void addPole(BuiltinComplex!double pole)
    {
        poles[numPoles++] = pole;
    }

    void addZero(BuiltinComplex!double zero)
    {
        zeroes[numZeroes++] = zero;
    }

    void addPoleAndZero(BuiltinComplex!double pole, BuiltinComplex!double zero)
    {
        addPole(pole);
        addZero(zero);
    }

    // Adds a pole and its conjugate.
    void addPolePair(BuiltinComplex!double pole)
    {
        addPole(pole);
        addPole( BuiltinComplex!double(pole.re, - pole.im));
    }

    void addPoleAndZeroPairs(BuiltinComplex!double pole, BuiltinComplex!double zero)
    {
        addPole(pole);
        addPole(BuiltinComplex!double(pole.re, - pole.im));
        addZero(zero);
        addZero(BuiltinComplex!double(zero.re, - zero.im));
    }
}

// Generates a s-plane half-band lowpass filter.
void generateSPlaneHalfBandLowPass(int maxPoles)(IIRDesign design, 
                                                 int order,
                                                 float passBandRippleDb,
                                                 float stopBandAttenuationDb,
                                                 out IIRLayout!maxPoles polesZeroes)
{
    // Note: If you fail here, order has not been defined in IIRDescription.
    assert(order != -1, "no order provided for IIR filter");

    // Note: If you fail here, your IIRFilter instantiation has too low `maxPoles` to contain this design.
    assert(order <= maxPoles, "maxPoles is too low for this IIR order");

    // Important: high-order (>= 6) bessels don't sound good at all. Not sure why.

    with (polesZeroes)
    {
        normalGain = 1;
        normalW = 0;
        if (design == IIRDesign.bessel)
        {
            switch (order) 
            {
                case 2:
                    addPolePair(BuiltinComplex!double(-1.5 , 0.8660));
                    break;
                case 3:
                    addPolePair(BuiltinComplex!double(-1.8390 , 1.7543));
                    addPole(BuiltinComplex!double(-2.3222 , 0.0));
                    break;
                case 4:
                    addPolePair(BuiltinComplex!double(-2.1039 , 2.6575));
                    addPolePair(BuiltinComplex!double(-2.8961 , 0.8672));
                    break;
                case 5: 
                    addPolePair(BuiltinComplex!double(-2.3247 , 3.5710));
                    addPolePair(BuiltinComplex!double(-3.3520 , 1.7427));
                    addPole(BuiltinComplex!double(-3.6467 , 0.0));
                    break;
                case 6:
                    addPolePair(BuiltinComplex!double(-2.5158 , 4.4927));
                    addPolePair(BuiltinComplex!double(-3.7357 , 2.6263));
                    addPolePair(BuiltinComplex!double(-4.2484 , 0.8675));
                    break;
                case 7:
                    addPolePair(BuiltinComplex!double(-2.6857 , 5.4206));
                    addPolePair(BuiltinComplex!double(-4.0701 , 3.5173));
                    addPolePair(BuiltinComplex!double(-4.7584 , 1.7393));
                    addPole(BuiltinComplex!double(-4.9716 , 0.0));
                    break;
                case 8:
                    addPolePair(BuiltinComplex!double(-5.2049 , 2.6162));
                    addPolePair(BuiltinComplex!double(-4.3683 , 4.4146));
                    addPolePair(BuiltinComplex!double(-2.8388 , 6.3540));
                    addPolePair(BuiltinComplex!double(-5.5878 , 0.8676));
                    break;
                default: 
                    assert(false, "Only order from 2 to 8 supported for Bessel IIR designs");
            }
        }
        else if (design == IIRDesign.butterworth)
        {
            assert(order >= 0);
            foreach(k; 1..order/2+1)
            {
                double phi = PI * (2.0 * k + order - 1.0) / (2.0 * order);
                BuiltinComplex!double pole = BuiltinComplex!double(cos(phi) , sin(phi));
                addPolePair(pole);
            }
        }
        else if (design == IIRDesign.chebyshevI)
        {
            double eps = sqrt (1. / exp (-passBandRippleDb * 0.1 * LN10) - 1);
            double v0 = asinh (1 / eps) / order;
            double sinh_v0 = -sinh (v0);
            double cosh_v0 = cosh (v0);

            double n2 = 2 * order;
            int pairs = order / 2;

            BuiltinComplex!double zero = BuiltinComplex!double(double.infinity , 0);

            for (int i = 0; i < pairs; ++i)
            {
                int k = 2 * i + 1 - order;
                double a = sinh_v0 * cos (k * PI / n2);
                double b = cosh_v0 * sin (k * PI / n2);
                addPoleAndZeroPairs( BuiltinComplex!double(a, b), zero);
            }

            if (order & 1)
            {
                BuiltinComplex!double pole = BuiltinComplex!double(1 / sinh_v0 , 0);
                addPoleAndZero(pole, zero);
            }
        }
        else if (design == IIRDesign.chebyshevII)
        {
            assert(isFinite(stopBandAttenuationDb),
                   "stopBandAttenuationDb wasn't provided in IIR description");

            double eps = sqrt (1. / (exp (stopBandAttenuationDb * 0.1 * LN10) - 1));
            double v0 = asinh (1 / eps) / order;
            double sinh_v0 = -sinh (v0);
            double cosh_v0 = cosh (v0);
            double fn = PI / (2 * order);

            int k = 1;
            for (int i = order / 2; --i >= 0; k+=2)
            {
                double a = sinh_v0 * cos ((k - order) * fn);
                double b = cosh_v0 * sin ((k - order) * fn);
                double d2 = a * a + b * b;
                double im = 1 / cos (k * fn);
                BuiltinComplex!double pole = BuiltinComplex!double( (a / d2) , b / d2 );
                BuiltinComplex!double zero = BuiltinComplex!double(0 , im);
                addPoleAndZeroPairs(pole, zero);
            }

            if (order & 1)
            {
                BuiltinComplex!double pole = 1 / sinh_v0;
                BuiltinComplex!double zero = BuiltinComplex!double(double.infinity , 0);
                addPoleAndZero(pole, zero);
            }
        }
    }
}

void poleFilterTransform(int maxPoles)(IIRLayout!maxPoles* analog, 
                                       IIRLayout!maxPoles* digital,
                                       IIRDescriptor desc, 
                                       double sampleRate)
{
    auto type = desc.type;
    int M = analog.numZeroes;
    int N = analog.numPoles;

    // Enable the MZT if you need bessel with non-small fc
    bool useMatchedZTransform = (desc.design == IIRDesign.bessel);

    if (type == IIRType.lowPass)
    {
        *digital = *analog;
      
        double fc = desc.cutoffHz / sampleRate;
        double f = tan(PI * fc);

        if (useMatchedZTransform)
        {
            double T = 1 / sampleRate;
            foreach(i; 0..M)
                digital.zeroes[i] = MZT_TransformLowpass(digital.zeroes[i], fc*2*PI);
            foreach(i; 0..N)
                digital.poles[i] = MZT_TransformLowpass(digital.poles[i], fc*2*PI);
        }
        else // bilinear transform
        {
            foreach(i; 0..M)
                digital.zeroes[i] = BLT_TransformLowpass(digital.zeroes[i], f);
            foreach(i; 0..N)
                digital.poles[i] = BLT_TransformLowpass(digital.poles[i], f);
        }

        // Add additional zeroes at -1 for lowpass
        foreach(i; M..N)
            digital.addZero( BuiltinComplex!double(-1.0, 0) );
    }
    else if (type == IIRType.highPass)
    {
        *digital = *analog;
        digital.normalW = PI - digital.normalW; // Normalized based on amplitude at Nyquist instead of DC

        double fc = desc.cutoffHz / sampleRate;
        double f = 1 / tan(PI * fc);

        if (useMatchedZTransform)
        {
            double T = 1 / sampleRate;
            foreach(i; 0..M)
                digital.zeroes[i] = MZT_TransformHighpass(digital.zeroes[i], f);
            foreach(i; 0..N)
                digital.poles[i] = MZT_TransformHighpass(digital.poles[i], f);
        }
        else // bilinear transform
        {
            foreach(i; 0..M)
                digital.zeroes[i] = BLT_TransformHighpass(digital.zeroes[i], f);
            foreach(i; 0..N)
                digital.poles[i] = BLT_TransformHighpass(digital.poles[i], f);
        }

        // Add additional zeroes at +1 for highpass
        foreach(i; M..N)
            digital.addZero( BuiltinComplex!double(1.0, 0.0) );
    }
    else
        assert(false);
}

BiquadCoeff biquadApplyScale(BiquadCoeff biquad, double scale)
{
    biquad[0] *= scale;
    biquad[1] *= scale;
    biquad[2] *= scale;
    return biquad;
}

BiquadCoeff biquad1Pole(BuiltinComplex!double pole, BuiltinComplex!double zero)
{
    assert (pole.im == 0); 
    assert (zero.im == 0);
    double a0 = 1;
    double a1 = -pole.re;
    double a2 = 0;
    double b0 = -zero.re;
    double b1 = 1;
    double b2 = 0;
    return [b0, b1, b2, a1, a2];
}

// Note: either it's a double pole, or two pole on the real axis.
// Same for zeroes
BiquadCoeff biquad2Poles(BuiltinComplex!double pole1, BuiltinComplex!double zero1, BuiltinComplex!double pole2, BuiltinComplex!double zero2)
{
    assert(std.complex.abs(pole1) <= 1);
    assert(std.complex.abs(pole2) <= 1);

    double a1;
    double a2;
    double epsilon = 0;

    if (pole1.im != 0)
    {
        assert(pole1.re == pole2.re);
        assert(pole1.im == -pole2.im);
        a1 = -2 * pole1.re;
        a2 = std.complex.sqAbs(pole1);
    }
    else
    {
        assert(pole2.im == 0);
        a1 = -(pole1.re + pole2.re);
        a2 =   pole1.re * pole2.re;
    }

    const double b0 = 1;
    double b1;
    double b2;

    if (zero1.im != 0)
    {
        assert(zero2.re == zero2.re);
        assert(zero2.im == -zero2.im);
        b1 = -2 * zero1.re;
        b2 = std.complex.sqAbs(zero1);
    }
    else
    {
        assert(zero2.im == 0);
        b1 = -(zero1.re + zero2.re);
        b2 =   zero1.re * zero2.re;
    }

    return [b0, b1, b2, a1, a2];
}


unittest
{
    IIRFilter!4 filter;
    filter.initialize( IIRDescriptor(IIRType.lowPass, IIRDesign.butterworth, 2), input.sampleRate);
}

// MZT

BuiltinComplex!double MZT_TransformLowpass(BuiltinComplex!double c, double T) nothrow @nogc
{
    if (c.re == double.infinity && c.im == 0)
        return BuiltinComplex!double(-1 , 0);
    return std.complex.exp(c * T);
}

BuiltinComplex!double MZT_TransformHighpass(BuiltinComplex!double c, double T) nothrow @nogc
{
    if (c.re == double.infinity && c.im == 0)
        return BuiltinComplex!double(1 , 0);
    return -std.complex.exp(c * T);
}


// BLT

BuiltinComplex!double BLT_TransformLowpass(BuiltinComplex!double c, double f) nothrow @nogc
{
    if (c.re == double.infinity && c.im == 0)
        return BuiltinComplex!double(-1 , 0);

    return preciseBLTDivision(c, f);
}

BuiltinComplex!double BLT_TransformHighpass(BuiltinComplex!double c, double f) nothrow @nogc
{
    if (c.re == double.infinity && c.im == 0)
        return BuiltinComplex!double(1 , 0);
    return -preciseBLTDivision(c, f);
}

// Returns: `(1 + pole*f) / (1 - pole*f)` computed at a higher-precision than naïvely.
//          Don't know the exact mechanism by which we get higher precision this way.
BuiltinComplex!double preciseBLTDivision(BuiltinComplex!double pole, double f)
{
    // Strangely this seems more precise than the builtin complex divide.
    double re_scaled = pole.re * f;
    double a = 1.0 + re_scaled;
    double b = pole.im * f;
    double c = 1.0 - re_scaled; // Supposedly for Bessel with low fc this loose lots of precision
    double d = -b;

    // The result of the division of (a+b*i)/(c+d*i) is:
    //    (ac+bd)/(c²+d²) + i * (bc-ad)/(c²+d²)
    // However here b = -d so it gives b*(c+a)/(c²+d²) for the imaginary part

    double divider = c*c + d*d;
    double re = (a*c + b*d)/divider;
    double im = (b*(c + a))/divider; // since b = -d
    return BuiltinComplex!double(re , im);
}

