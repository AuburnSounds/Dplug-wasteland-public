/**
*
* Soft Clipping function
*
* License: MIT
* Licence details : http://creativecommons.org/licenses/MIT/
* Dlang/Dplug code ported by : Stephane Ribas, SMAOLAB.ORG, 03/12/2022
* Detailled academic specification : https://wiki.analog.com/resources/tools-software/sigmastudio/toolbox/nonlinearprocessors/asymmetricsoftclipper
*
*/

/** How to use it ?

...
for (int f = 0; f < frames; ++f)

  outputleft= soft_clipping(inputsignal, tau1, tau2);
  outputright= soft_clipping(inputsignal, tau1, tau2);

tau1 : should be between 0.0f and 1.0f (it's the lower window section)
tau2 : should be between 0.0f and 1.0f (it's the upper window section)

A good TAU choice is : tau1 =0.5f and tau2=0.5f

Note that normally TAU1 should be somethinbg like -0.5f or -0.707f... but I implemented the code in such way that TAU1 should be set to a positive value between 0 and 1. Of course, you can changed this if you want...

*/

module clipping;

import std.math;
import std.algorithm;
import std.complex;
import utils;
import dplug.core.math;

public:
nothrow:
@nogc:

// SOFT CLIPPING FUNCTION --------------------------------------
//

float soft_clipping(float inputsignal, float tau1, float tau2)
{
  // Soft clipping, very nice clipping method , I like it !
  // see https://wiki.analog.com/resources/tools-software/sigmastudio/toolbox/nonlinearprocessors/asymmetricsoftclipper
  // exemple : tau1 = 0.5, tau2=0.5
  // Tau1 and 2 are the window limits...
  // then we apply the formula below
  // out = in , if abs(in) <tau1 when in >0, idem if abs(in) < tau2 for input <0

  float outputclipped = inputsignal;

  if ( ( abs(inputsignal) < tau1 ) && (inputsignal > 0 ))
  {
    // Signal is good :) no clipping
    outputclipped = inputsignal;
    return outputclipped;
  }
  else
  //  if abs(in) >=tau1 & in > 0 THEN out = tau1 + (1 - tau1) * tanh ( (abs(in) - tau1) / (1 - tau1) )
  if ( ( abs(inputsignal) >= tau1 ) && ( inputsignal > 0 ) )
  {
    outputclipped = tau1 + (1 - tau1) * tanh ( (abs(inputsignal) - tau1) / (1 - tau1) );
    return outputclipped;
  }
  else
  // if abs(in) >=tau2 & In < 0 THEN out = -tau2 - (1 - tau2) * tanh ( (abs(in) - tau2) / (1 - tau2) )
  if ( ( abs(inputsignal) >= tau2 ) && ( inputsignal < 0 ) )
  {
    outputclipped = -tau2 - (1 - tau2) * tanh ( (abs(inputsignal) - tau2) / (1 - tau2) );
    return outputclipped;
  }
  else if ( ( abs(inputsignal) < tau2 ) && (inputsignal < 0 ))
  {
    // Signal (negative) is good :) no clipping
    outputclipped = inputsignal;
    return outputclipped;
  }
  else return outputclipped;
}
//
// END END
