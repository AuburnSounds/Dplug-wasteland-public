/**
*
* Soft Limiting function
*
* Original author : pichenettes
* Original code repository : https://github.com/pichenettes/stmlib/blob/master/dsp/ (check the limiter code files, i.e limiter.h, etc.)
* License: MIT
* Licence details : http://creativecommons.org/licenses/MIT/
* Dlang/Dplug code ported by : Stephane Ribas, SMAOLAB.ORG, 03/12/2022
*
*/

/** How to use it ?

...
Limiter _Limitleft, _Limitright;
...
_Limitleft.init(); _Limitright.init();
...

for (int f = 0; f < frames; ++f)

  outputleft= _Limitleft.processSample(your_input_sound,pre_gain);
  outputright= _Limitright.processSample(your_input_sound,pre_gain);

You can also use the Buffer version, You don't need the For Loop:
  _Limitleft.processBuffer(your_input_sound_array,your_output_sound_limitedsound_array, pre_gain, number of the buffer frames);

  ex: _Limitleft.processBuffer(outputs[0], outputs[0], frames,_pre_gain);


Pre_gain : should be between -0.1f up to -12.0f ... whatever it's gain multiplier :-) a good pre_gain is -0.7 . -0.8 . -1.0.. -2.0 maximum. Note that pre_gain it should be negative :)

your_input_sound : -1 to +1 :-)

*/

module softlimiter;

import std.math;
import std.algorithm;
import std.complex;
import utils;

import  dplug.core,
        dplug.dsp;

/* I think you can optimise the import section! */

struct Limiter
{
public:
nothrow:
@nogc:

  // Limiter FUNCTIONS -------------------------------------
  void init()
  {
      peak_ = 0.5f;
  }

  float calcul_slope(float y, float x, float positive, float negative)
  {
    float error = (x)-y;
    y += (error > 0 ? positive : negative) * error;
    return y;
  }

  /** Soft Limiting function */
  float softLimit(float x)
  {
      return x * (27.0f + x * x) / (27.0f + 9.0f * x * x);
      // you can change the coefs (9.0f...) to get different sin() curve
  }

  // mono process
  // buffer ...
  void processBuffer(const(float)* input, float* output, float pre_gain, int frames)
  {
      // let's process the sound
      for (int f = 0; f < frames; ++f)
      {
          float pre  = input[f] * pre_gain;
          float peak = fabs(pre);

          peak_ = calcul_slope(peak_, peak, 0.05f, 0.00002f);
          float gain = (peak_ <= 1.0f ? 1.0f : 1.0f / peak_);
          output[f]  = softLimit(pre * gain* 0.7f);
            // note : changing the 0.7f to ...  1.0 or other value will change the overall sound level... Originally this coef has been set to 0.7f but you can set it to 1.0f ;-) The pre-gain parameter will have then more impact on the sound results.
      }
  }

  // mono process
  // sample by sample
  float processSample(float input,float pre_gain)
  {
      float pre  = input * pre_gain;
      float peak = fabs(pre);
      peak_ = calcul_slope(peak_, peak, 0.05f, 0.00002f);
      float gain = (peak_ <= 1.0f ? 1.0f : 1.0f / peak_);
      return softLimit(pre * gain * 0.7f);
        // note : changing the 0.7f to 1.0 or other value will change the overall sound level... Originally this coef has been set to 0.7f but you can set it to 1.0f ;-) The pre-gain parameter will have then more impact on the sound results.
  }

private:
  float peak_= 0.5f;
  float[] _envelope;
  float[] _gain;

}
