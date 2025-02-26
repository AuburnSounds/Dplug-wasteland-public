/**
Academic Oversampling (fill with zeros)

Copyright: SMAOLAB 2025
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Author:   Stephane Ribas

Note 1 : This is a very naive and simple downsampling algo.
Note 2: this is downsampling algorithms has a little mistake in the filter coeffs.
But this gives a nice sounds, different sound if your X2 or X4 or X8.
I like it on my Saturation/distortion plugins. 
Note 3: you can easily improve this code by processing the buffers not once by once by 4 by 4 ;-)
Note 4 : you can set other options, look at the code (dithering & more filtering)
Note 5 : few part of the code is inspired by Guillaume Piolat

  --- TUTORIAL BEFORE THE CODE -----

1- In main.d, , at the top, declare :

...
import academic_downsampling;
import academic_oversampling;
...

2- In main.d, , at the end, in the private section, declare :

Private: 
    float[] _upsampledBufferL, _upsampledBufferR; // the buffers where the oversampled signals are stored
    float[] _downsampledBufferL, _downsampledBufferR; // the buffers where the oversampled signals are stored
    float[] _tempPreEQBufferL, _tempPreEQBufferR; // optional temporary buffer
    int _oversamplingratio = 4; 
    ...

3- then, in main.d, in the RESET function, write the following code : 

override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
{
        ...
        // Downsampling buffers
        _downsampledBufferL.reallocBuffer(maxFrames*_oversamplingratio);
        _downsampledBufferR.reallocBuffer(maxFrames*_oversamplingratio);

        // Upsampling buffers
        _upsampledBufferL.reallocBuffer(maxFrames*_oversamplingratio);
        _upsampledBufferR.reallocBuffer(maxFrames*_oversamplingratio);
        ...
        // optional 
        _tempPreEQBufferL.reallocBuffer(maxFrames*_oversamplingratio);
        _tempPreEQBufferR.reallocBuffer(maxFrames*_oversamplingratio);
        ...
}

4- then ,in main.d, in the processaudio function, write the following code : 
override void processAudio(const(float*)[] inputs, float*[]outputs, int frames,TimeInfo info) nothrow @nogc
{
...
            // get the input signal and copy it to a buffer
            for (int f = 0; f < frames; ++f)
                {
                    _tempPreEQBufferL[f] = inputs[0][f]; // I used a temporay buffer 
                    _tempPreEQBufferR[f] = inputs[1][f]; // to play with it later :-)
                }
            //  oversample
            // We copy the "input/_tempPreEQBufferL" buffer to the oversampled buffer "_upsampledBufferL"
            _upsamplingL.processBuffer(_tempPreEQBufferL.ptr, _upsampledBufferL.ptr, frames, _oversamplingratio, _sampleRate);
            _upsamplingR.processBuffer(_tempPreEQBufferR.ptr, _upsampledBufferR.ptr, frames, _oversamplingratio,_sampleRate);

            // process you audio based on the new oversampled buffer 
            for (int f = 0; f < frames*_oversamplingratio; ++f)
                {
                    _upsampledBufferL[f] = tanh(_upsampledBufferL[f]);
                    _upsampledBufferR[f] = tanh(_upsampledBufferR[f]);
                }

            ... and so on

            // before the end of your program, you have to downsample !
            // We copy the oversample buffer "_upsampledBufferL" to the "Output" buffer
            _downsamplingL.processBuffer(_upsampledBufferL.ptr,outputs[0], frames, _oversamplingratio,_sampleRate);
            _downsamplingR.processBuffer(_upsampledBufferR.ptr,outputs[1], frames, _oversamplingratio,_sampleRate);       

            // Mix input/output :-)
            for (int f = 0; f < frames; ++f)
                {
                    outputs[0][f] = ((outputs[0][f] * fadeIn) + (inputs[0][f] * fadeOut));
                    outputs[1][f] = ((outputs[1][f] * fadeIn) + (inputs[1][f] * fadeOut));
                }
...
}

5- that's all :-)
*/
module academic_oversampling;

import std.math;
import dplug.core.vec;
import dplug.dsp;

nothrow:
@nogc:

/// Upsample a signal
struct Upsampling
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
            || (oversampling == 8)
            || (oversampling == 16);
    }

    void initialize(int oversampling, int frames,  double sampleRate)
    {
        // Note: upsamplers are lazily initialized on first use
        _lastOversampling = 0;

        switch(oversampling)
        {
            case 1:
            {
                // Prepare the LPF Filter for oversampling X0
                _lowpassbiasCoeff = biquadRBJLowPass(sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            case 2:
            {
                // Prepare the LPF Filter for oversampling X2
                _lowpassbiasCoeff = biquadRBJLowPass(sampleRate/2.0f, sampleRate, SQRT1_2);
                // should be sampleRate*2/2.0f
                break;
            }
            case 4:
            {
                // Prepare the LPF Filter for oversampling X4
                _lowpassbiasCoeff = biquadRBJLowPass(sampleRate/2.0f, sampleRate, SQRT1_2);
                // should be sampleRate*4/2.0f => sampleRate*2.0f
                break;
            }
            case 8:
            {
                // Prepare the LPF Filter for oversampling X8
                _lowpassbiasCoeff = biquadRBJLowPass(sampleRate/2.0f, sampleRate, SQRT1_2);
                // should be sampleRate*8/2.0f => sampleRate*4.0f
                break;
            }
            case 16:
            {
                _lowpassbiasCoeff = biquadRBJLowPass(sampleRate/2.0f, sampleRate, SQRT1_2);
                // should be sampleRate*16/2.0f => sampleRate*8.0f
                break;
            }
            default:
                assert(false);
        }

        _hpOversampling.initialize(); //aliasing filter
        _hpOversampling1.initialize(); //aliasing filter
      // note: normally, I execute two filters in sequential to do my downsampling/oversampling. It's really cool but too much CPU consuming so as a trade off between Quality and CPU I chose to remove the second filter :)
    }

    /// Process samples.
    void processBuffer(const(float)* input, float* output, int frames, int oversampling, double sampleRate)
    {
        int j;
        float s;
    
        assert(isValidOversampling(oversampling));

        // lazily initialized oversampling engine to be used
        if (oversampling != _lastOversampling)
        {
            initialize(oversampling, frames, sampleRate);
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
                int f = 0;
                for (; f + 3 < frames; f += 4)
                {
                    int index0 = f << 1;
                    int index1 = (f + 1) << 1;
                    int index2 = (f + 2) << 1;
                    int index3 = (f + 3) << 1;

                    output[index0]     = input[f];
                    output[index0 + 1] = 0.0f;

                    output[index1]     = input[f + 1];
                    output[index1 + 1] = 0.0f;

                    output[index2]     = input[f + 2];
                    output[index2 + 1] = 0.0f;

                    output[index3]     = input[f + 3];
                    output[index3 + 1] = 0.0f;
                }

                // Traiter les éléments restants (si frames n'est pas un multiple de 4)
                /*for (; f < frames; ++f)
                {
                    int index = f << 1;
                    output[index]     = input[f];
                    output[index + 1] = 0.0f;
                }*/

                break;
            }
            case 4:
            {
                int f = 0;
                for (; f + 3 < frames; f += 4)
                {
                    int index0 = f << 2;
                    int index1 = (f + 1) << 2;
                    int index2 = (f + 2) << 2;
                    int index3 = (f + 3) << 2;

                    output[index0]     = input[f];
                    output[index0 + 1] = 0.0f;
                    output[index0 + 2] = 0.0f;
                    output[index0 + 3] = 0.0f;

                    output[index1]     = input[f + 1];
                    output[index1 + 1] = 0.0f;
                    output[index1 + 2] = 0.0f;
                    output[index1 + 3] = 0.0f;

                    output[index2]     = input[f + 2];
                    output[index2 + 1] = 0.0f;
                    output[index2 + 2] = 0.0f;
                    output[index2 + 3] = 0.0f;

                    output[index3]     = input[f + 3];
                    output[index3 + 1] = 0.0f;
                    output[index3 + 2] = 0.0f;
                    output[index3 + 3] = 0.0f;
                }

                // Traiter les éléments restants
                /*for (; f < frames; ++f)
                {
                    int index = f << 2;
                    output[index]     = input[f];
                    output[index + 1] = 0.0f;
                    output[index + 2] = 0.0f;
                    output[index + 3] = 0.0f;
                }*/
                break;
            }
            case 8:
            {
                int f = 0;
                for (; f + 3 < frames; f += 4)
                {
                    int index0 = f << 3;
                    int index1 = (f + 1) << 3;
                    int index2 = (f + 2) << 3;
                    int index3 = (f + 3) << 3;

                    output[index0]     = input[f];
                    output[index0 + 1] = 0.0f;
                    output[index0 + 2] = 0.0f;
                    output[index0 + 3] = 0.0f;
                    output[index0 + 4] = 0.0f;
                    output[index0 + 5] = 0.0f;
                    output[index0 + 6] = 0.0f;
                    output[index0 + 7] = 0.0f;

                    output[index1]     = input[f + 1];
                    output[index1 + 1] = 0.0f;
                    output[index1 + 2] = 0.0f;
                    output[index1 + 3] = 0.0f;
                    output[index1 + 4] = 0.0f;
                    output[index1 + 5] = 0.0f;
                    output[index1 + 6] = 0.0f;
                    output[index1 + 7] = 0.0f;

                    output[index2]     = input[f + 2];
                    output[index2 + 1] = 0.0f;
                    output[index2 + 2] = 0.0f;
                    output[index2 + 3] = 0.0f;
                    output[index2 + 4] = 0.0f;
                    output[index2 + 5] = 0.0f;
                    output[index2 + 6] = 0.0f;
                    output[index2 + 7] = 0.0f;

                    output[index3]     = input[f + 3];
                    output[index3 + 1] = 0.0f;
                    output[index3 + 2] = 0.0f;
                    output[index3 + 3] = 0.0f;
                    output[index3 + 4] = 0.0f;
                    output[index3 + 5] = 0.0f;
                    output[index3 + 6] = 0.0f;
                    output[index3 + 7] = 0.0f;
                }

                // Traiter les éléments restants (si frames n'est pas un multiple de 4)
                /*for (; f < frames; ++f)
                {
                    int index = f << 3;
                    output[index]     = input[f];
                    output[index + 1] = 0.0f;
                    output[index + 2] = 0.0f;
                    output[index + 3] = 0.0f;
                    output[index + 4] = 0.0f;
                    output[index + 5] = 0.0f;
                    output[index + 6] = 0.0f;
                    output[index + 7] = 0.0f;
                }*/
                break;
            }
            case 16:
            {
                int f = 0;
                for (; f + 7 < frames; f += 8)
                {
                    int index0 = f << 4;
                    int index1 = (f + 1) << 4;
                    int index2 = (f + 2) << 4;
                    int index3 = (f + 3) << 4;
                    int index4 = (f + 4) << 4;
                    int index5 = (f + 5) << 4;
                    int index6 = (f + 6) << 4;
                    int index7 = (f + 7) << 4;

                    output[index0] = input[f];
                    output[index1] = input[f + 1];
                    output[index2] = input[f + 2];
                    output[index3] = input[f + 3];
                    output[index4] = input[f + 4];
                    output[index5] = input[f + 5];
                    output[index6] = input[f + 6];
                    output[index7] = input[f + 7];

                    for (int i = 1; i < 16; ++i) {
                        output[index0 + i] = 0.0f;
                        output[index1 + i] = 0.0f;
                        output[index2 + i] = 0.0f;
                        output[index3 + i] = 0.0f;
                        output[index4 + i] = 0.0f;
                        output[index5 + i] = 0.0f;
                        output[index6 + i] = 0.0f;
                        output[index7 + i] = 0.0f;
                    }
                }

                // Traiter les éléments restants (si frames n'est pas un multiple de 8)
                /*for (; f < frames; ++f)
                {
                    int index = f << 4;
                    output[index] = input[f];

                    for (int i = 1; i < 16; ++i) {
                        output[index + i] = 0.0f;
                    }
                }*/
                break;
            }
            default:
                assert(false);
        }
        // end oversampling


        _hpOversampling.nextBuffer(output, output, frames*oversampling, _lowpassbiasCoeff); // 12DB
        _hpOversampling1.nextBuffer(output, output, frames*oversampling, _lowpassbiasCoeff); // 24db slope

        // note: normally, I execute two filters in sequential to do my downsampling/oversampling. It's really cool but too much CPU consuming so as a trade off between Quality and CPU I chose to remove the second filter :)

    }

private :
    int _lastOversampling = 0;
    BiquadDelay _hpOversampling, _hpOversampling1;
    BiquadCoeff _lowpassbiasCoeff;
}
// END
