/*
MIT License

Copyright (c) 2018 Chris Johnson
Copyright (c) 2021 Guillaume Piolat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
module transformer;

import inteli.math;
import std.math: PI, tan;
import auburn.dsp;
import dplug.core;

/// Another gift From AirWindows: https://github.com/airwindows/
/// You need to mention its licence and copyright notice in released product.
struct Transformer
{
nothrow @nogc:

    enum MAX_CHANNELS = 2;

    void initialize(float sampleRate, int channels)
    {
        _sampleRate = sampleRate;
        _channels = channels;
        assert(_channels <= MAX_CHANNELS);

        for (int chan = 0; chan < _channels; ++chan)
        {
            for (int x = 0; x < 9; x++) 
            {
                figure[chan][x] = 0.0;
            }
        }
    }

    void nextBuffer(double** inoutSamples, 
                    int frames,
                    float saturation = 0.25f, // 0 to 1
                    float DC = 0.5f, // 0 to 1
                    float wet = 0.95f) // 0 to 1
    {
        //[0] is frequency: 0.000001 to 0.499999 is near-zero to near-Nyquist
        //[1] is resonance, 0.7071 is Butterworth. Also can't be zero
        double boost = 1.0 - _mm_pow_ss(saturation,2);
        if (boost < 0.001) 
            boost = 0.001; //there's a divide, we can't have this be zero

        double offset = (DC*2.0)-1.0;
        double sinOffset = fast_sin(offset);

        for (int chan = 0; chan < _channels; ++chan)
        {
            // re-tuned, 840hz sounded a bit better on rock/trap and more in line with Lens
            figure[chan][0] = 840.0f / _sampleRate; //changed  frequency, was 600hz originally (GP)
            figure[chan][1] = 0.03; // re-tuned, was 0.023 (GP) //resonance

            double K = tan(PI * figure[chan][0]);
            double norm = 1.0 / (1.0 + K / figure[chan][1] + K * K);
            figure[chan][2] = K / figure[chan][1] * norm;
            figure[chan][4] = -figure[chan][2];
            figure[chan][5] = 2.0 * (K * K - 1.0) * norm;
            figure[chan][6] = (1.0 - K / figure[chan][1] + K * K) * norm;
        }

        for (int chan = 0; chan < _channels; ++chan)
        {
            for (int n = 0; n < frames; ++n)
            {
                double inputSample = inoutSamples[chan][n];
                double drySample = inputSample;

                double tempSample = (inputSample * figure[chan][2]) + figure[chan][7];
                figure[chan][7] = -(tempSample * figure[chan][5]) + figure[chan][8];
                figure[chan][8] = (inputSample * figure[chan][4]) - (tempSample * figure[chan][6]);
                inputSample = tempSample + ((fast_sin(((drySample-tempSample)/boost)+offset) - sinOffset)*boost);
                //given a bandlimited inputSample, freq 600hz and Q of 0.023, this restores a lot of
                //the full frequencies but distorts like a real transformer. Since
                //we are not using a high Q we can remove the extra sin/asin on the biquad.

                inputSample = (inputSample * wet) + (drySample * (1.0 - wet));
                inoutSamples[chan][n] = inputSample;
            }
        }
    }


private:
    float _sampleRate;
    int _channels;

    double[9][MAX_CHANNELS] figure;
}


/// Emulate the "Digi" mode of SDRR with harmonic 2 and 4, little Drive, HQ = Off
/// This is the "Even" distortion on Lens, not particularly interesting shaper.
struct EvenHarmonics
{
nothrow @nogc:

    void initialize(float sampleRate, int channels)
    {
        _channels = channels;
    }

    void nextBuffer(double** inoutSamples, 
                    int frames,
                    float saturation,
                    float sinAmp,
                    float wet)
    {
        for (int chan = 0; chan < _channels; ++chan)
        {
            for (int n = 0; n < frames; ++n)
            {
                double x = inoutSamples[chan][n];
                double xx = x * x;
                double h2 = saturation * xx;
                h2 = fast_sin(h2) * sinAmp;
                double distorted = x + wet * h2;
                inoutSamples[chan][n] = distorted;
            }
        }
    }


private:
    int _channels;
}