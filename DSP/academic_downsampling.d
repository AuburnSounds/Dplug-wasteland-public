/**
Academic Downsampling.

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
module academic_downsampling;

import std.math;

import core.stdc.stdlib;
import core.stdc.math;

import dplug.core.vec;
import dplug.dsp;
import dplug.core.nogc;


nothrow:
@nogc:

/// Downsample
struct Downsampling
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

    void initialize(int oversampling, int frames, double sampleRate)
    {
        // Note: downsamplers are lazily initialized on first use
        _lastOversampling = 0;

        switch(oversampling)
        {
            case 1:
            {
                _lowpassbiasCoeff = biquadRBJLowPass
                (sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            case 2:
            {
                // Prepare the LPF Filter for oversampling X2
                //_lowpassbiasCoeff = biquadRBJLowPass
                //(sampleRate, sampleRate*2.0f, SQRT1_2);
                _lowpassbiasCoeff = biquadRBJLowPass
                (sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            case 4:
            {
                // Prepare the LPF Filter for oversampling X4
                //_lowpassbiasCoeff = biquadRBJLowPass
                //(sampleRate*4.0f/2.0f, sampleRate*4.0f, SQRT1_2);
                _lowpassbiasCoeff = biquadRBJLowPass
                (sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            case 8:
            {
                // Prepare the LPF Filter for oversampling X8
                //_lowpassbiasCoeff = biquadRBJLowPass
                //(sampleRate*8.0f/2.0f, sampleRate*8.0f, SQRT1_2);
                _lowpassbiasCoeff = biquadRBJLowPass
                (sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            case 16:
            {
                _lowpassbiasCoeff = biquadRBJLowPass
                (sampleRate/2.0f, sampleRate, SQRT1_2);
                break;
            }
            default:
                assert(false);
        }
        _hpDownsampling1.initialize(); //aliasing filter
        //_hpDownsampling2.initialize(); //aliasing filter
        _hpDownsampling3.initialize(); //aliasing filter
        //_hpDownsampling4.initialize(); //aliasing filter
  }

    void setextraParameters(bool _interpolation_mode,bool _dithering_mode)
    {
        interpolation_mode = _interpolation_mode;
        dithering_mode = _dithering_mode;
    }

    void initializeextraParameters()
    {
        if (interpolation_mode == true)
        {
            // Anti add-on // interpolation filter effect
      	    oversamplingCoefficients[0] = 4.01230529e-03f;
      	    oversamplingCoefficients[1] = -2.19517848e-18f;
      	    oversamplingCoefficients[2] = -2.33215245e-02f;
      	    oversamplingCoefficients[3] = -3.34765041e-02f;
      	    oversamplingCoefficients[4] = 7.16025226e-02f;
      	    oversamplingCoefficients[5] = 2.82377526e-01f;
      	    oversamplingCoefficients[6] = 3.97611349e-01f;
      	    oversamplingCoefficients[7] = 2.82377526e-01f;
      	    oversamplingCoefficients[8] = 7.16025226e-02f;
      	    oversamplingCoefficients[9] = -3.34765041e-02f;
      	    oversamplingCoefficients[10] = -2.33215245e-02f;
      	    oversamplingCoefficients[11] = -2.19517848e-18f;
      	    oversamplingCoefficients[12] = 4.01230529e-03f;

      	    for (int f = 0; f < 13; f++) {
      		    oversamplingFilter[f] = 0.0f;
      	    }
            
        } //END Anti add-on

        // note: normally, I execute two filters in sequential to do my downsampling/oversampling. 
        //It's really cool but too much CPU consuming 
        //so as a trade off between Quality and CPU I chose to remove the second filter :)

        // dithering ?
        if (dithering_mode==true)
        {
            if (flip==false)
            {
                fpdL = 1;
                while (fpdL < 16386) fpdL = rand()*UINT32_MAX;
                flip=true;
	            //this is reset: values being initialized only once. Startup values, whatever they are.
            }
        }
    }

    static int latencySamples(float sampleRate)
    {
        // Downsamplers report latency for the whole up+down combination
        //assert(IIRDownsampler2x.latencySamples(sampleRate) == 1);
        //assert(IIRDownsampler4x.latencySamples(sampleRate) == 2);
        return 2;
    }

    /// Takes one buffer of `oversampling`*`frames` samples, and output downsampled buffers of `frames` samples.
    void processBuffer(float* input, float* output, int frames, int oversampling, double sampleRate)
    {
        assert(isValidOversampling(oversampling));

        // lazily initialized oversampling engine to be used
        if (oversampling != _lastOversampling)
        {
          initialize(oversampling,  frames, sampleRate);
          _lastOversampling = oversampling;
        }
        //debugLogf("------- DWN sampling filter 1 ");

        _hpDownsampling1.nextBuffer(input, input, frames*oversampling, _lowpassbiasCoeff); // 12db slope
        //debugLogf("------- DWN sampling filter 2 ");
         // we could apply a filter to get 24db slope ? 
        _hpDownsampling3.nextBuffer(input, input, frames*oversampling, _lowpassbiasCoeff); // 24db slope
        
        //debugLogf("------- DWN begin ");
        switch(oversampling)
        {
                
        case 1: // X0

          for (int f = 0; f < frames; ++f)
          {

                int j;
                float s;

              output[f] = input[f];

              //begin 32 bit stereo floating point dither
              if (dithering_mode==true)
              {  
                int expon; frexpf(output[f], &expon);
                fpdL ^= fpdL << 13; fpdL ^= fpdL >> 17; fpdL ^= fpdL << 5;
                output[f] += fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
                //fpdL*3.4e-36L*powf(2,expon+62); // 64 bytes ??  
                //fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
              }
              if (interpolation_mode == true)
              {
                oversamplingFilter[0] = output[f];
                s = 0.0f;
          		    for (j = 0; j < 13; j++) {
          			       s += oversamplingCoefficients[j] * oversamplingFilter[j];
          		    }
          		  for (j = 1; j < 13; j++) {
          			     oversamplingFilter[j] = oversamplingFilter[j-1];
          		  }
                output[f] = s;
              }
          }
          break;

        case 2: // X2
          for (int f = 0; f < frames; ++f)
          {
                int j;
                float s;

              output[f] = input[f << 1];

              //begin 32 bit stereo floating point dither
              if (dithering_mode==true)
              {  
                int expon; frexpf(output[f], &expon);
                fpdL ^= fpdL << 13; fpdL ^= fpdL >> 17; fpdL ^= fpdL << 5;
                output[f] += fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
                //fpdL*3.4e-36L*powf(2,expon+62); // 64 bytes ??  
                //fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
              }
              
              if (interpolation_mode == true)
              {
                oversamplingFilter[0] = output[f];
                s = 0.0f;
          		    for (j = 0; j < 13; j++) {
          			       s += oversamplingCoefficients[j] * oversamplingFilter[j];
          		    }
          		  for (j = 1; j < 13; j++) {
          			     oversamplingFilter[j] = oversamplingFilter[j-1];
          		  }
                output[f] = s;
              }
          }
          break;

        case 4: // X4
          for (int f = 0; f < frames; ++f)
          {
              int j;
              float s;

              output[f] = input[f << 2];

               //debugLogf("------- DWN loop f=%d, frames  %d, oversampling ratio %d",f, frames,oversampling);

              //begin 32 bit stereo floating point dither
              if (dithering_mode==true)
              {  
                int expon; frexpf(output[f], &expon);
                fpdL ^= fpdL << 13; fpdL ^= fpdL >> 17; fpdL ^= fpdL << 5;
                output[f] += fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
                //fpdL*3.4e-36L*powf(2,expon+62); // 64 bytes ??  
                //fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
              }
              
              if (interpolation_mode == true)
              {
                oversamplingFilter[0] = output[f];
                s = 0.0f;
          		    for (j = 0; j < 13; j++) {
          			       s += oversamplingCoefficients[j] * oversamplingFilter[j];
          		    }
          		  for (j = 1; j < 13; j++) {
          			     oversamplingFilter[j] = oversamplingFilter[j-1];
          		  }
                output[f] = s;
              }
          }
          break;

        case 8:  // X8
                    //debugLogf("------- DWN sampling over x8 ");

          	for (int f = 0; f < frames; ++f)
          	{
                  int j;
                  float s;

                output[f] = input[f << 3];

              //begin 32 bit stereo floating point dither
              if (dithering_mode==true)
              {  
                int expon; frexpf(output[f], &expon);
                fpdL ^= fpdL << 13; fpdL ^= fpdL >> 17; fpdL ^= fpdL << 5;
                output[f] += fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
                //fpdL*3.4e-36L*powf(2,expon+62); // 64 bytes ??  
                //fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
              }
              
              if (interpolation_mode == true)
                {
                  oversamplingFilter[0] = output[f];
                  s = 0.0f;
            		    for (j = 0; j < 13; j++) {
            			       s += oversamplingCoefficients[j] * oversamplingFilter[j];
            		    }
            		  for (j = 1; j < 13; j++) {
            			     oversamplingFilter[j] = oversamplingFilter[j-1];
            		  }
                  output[f] = s;
                }
            }
            break;

        case 16:

          	for (int f = 0; f < frames; ++f)
          	{
                  int j;
                  float s;

                output[f] = input[f << 4];

              //begin 32 bit stereo floating point dither
              if (dithering_mode==true)
              {  
                int expon; frexpf(output[f], &expon);
                fpdL ^= fpdL << 13; fpdL ^= fpdL >> 17; fpdL ^= fpdL << 5;
                output[f] += fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
                //fpdL*3.4e-36L*powf(2,expon+62); // 64 bytes ??  
                //fpdL*5.5e-36L*powf(2,expon+62); // 32 bytes
              }
              
              if (interpolation_mode == true)
                {
                  oversamplingFilter[0] = output[f];
                  s = 0.0f;
            		    for (j = 0; j < 13; j++) {
            			       s += oversamplingCoefficients[j] * oversamplingFilter[j];
            		    }
            		  for (j = 1; j < 13; j++) {
            			     oversamplingFilter[j] = oversamplingFilter[j-1];
            		  }
                  output[f] = s;
                }
            }
            break;
        default:
            assert(false);
        }

        //_hpDownsampling3.nextBuffer(output, output, frames, _lowpassbiasCoeff); // 12DB slope ;-)
        // according to the literrature I don't have to add such filter at the end

        //_hpDownsampling4.nextBuffer(output, output, frames, _lowpassbiasCoeff); // 24db slope !
        // note: normally, I execute two filters in sequential to do my downsampling/oversampling. 
        // It's really cool but too much CPU consuming so as a trade off between Quality and CPU 
        // I chose to remove the second filter :)
        
        //debugLogf("------- DWN end");

    }

private :

    bool interpolation_mode = false;
    bool dithering_mode = false;

    int _lastOversampling = 0;
    float _delay0, _delay1;
    BiquadDelay _hpDownsampling1, _hpDownsampling2;
    BiquadDelay _hpDownsampling3, _hpDownsampling4;
    BiquadCoeff _lowpassbiasCoeff;

    // dithering
    enum UINT32_MAX = 4294967295u;
	uint fpdL; //uint32 ??
    bool flip=false;

    // Anti Add-on
		float[13] oversamplingCoefficients;
		float[13] oversamplingFilter;
}
