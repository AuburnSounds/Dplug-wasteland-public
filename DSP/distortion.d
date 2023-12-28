/**
*
* Distortions/TUBE functions
* - Guitar Tube emulator
* - Tarabia Waveshaper
* - WarmTube
* 03/12/2022
* License: MIT
* Licence details : http://creativecommons.org/licenses/MIT/
* Original Author : Stephane Ribas, contact@smaolab.org
* URL: https://SMAOLAB.ORG
*
*/

/** How to use it ?

...
for (int f = 0; f < frames; ++f)

  outputleft= tarabiadisto(inputsignalLeft, amount, gain);
...

- amount and gain is 0.1 to 1.0 :-)
- I adviced you to smooth the amount & gain values

*/

module distortion;

import std.math;
import std.random;
import std.algorithm;
import std.complex;
import dplug.core.math;

public:
nothrow:
@nogc:

// DISTO & TUBE FUNCTIONS --------------------------------------------
//
//

// Tarabia (yes!)
//
float tarabiadisto(float inputsignal, float tarabiaamount, float tarabiagain)
{
  float x, k , _outputSample;
  x = inputsignal; // input in [-1..1]

  //
  // The tarabia formula
  //
  k = 2*tarabiaamount/(1-tarabiaamount); // amount accepted in [-1..1] or 0 to 1 :)
  _outputSample = (1+k)*x/(1+k*fabs(x));

  // gain
  _outputSample *=tarabiagain;

  return _outputSample;
}

// WarmTube
float warmtube(float inputsignal, float kp, float kn, int gp, int gn)
{
  float y;

  y = inputsignal;

  if (inputsignal>kp)
  {
    y = tanh(kp) - ((tanh(kp)*tanh(kp)-1)/gp)*tanh(gp*inputsignal-kp);
  }
  else
  if ((inputsignal>=(-1.0f*kn)) && (inputsignal<=kp))
  {
      y = tanh(inputsignal);
  }
  else
  if (inputsignal<(-1.0f*kn))
  {
      y = -1.0f*tanh(kn) - ((tanh(kn)*tanh(kn)-1)/gn)*tanh(gn*inputsignal+kn) ;
  }

  return y;
}

// tube vaccum simple emulator
// quite clean and boost :)
float cleanvacuumtube(float inputsignal, int stage)
{
    // tube vaccum simple emulator
    // quite clean and boost :)
    float y1, y2, y3, y4, y5, y6, y7,y8,y9;

    //if (inputsignal < 0.0) // Half wave
    //  inputsignal=-1.0f*(inputsignal);
    // in a tube simulation we should do do asymtetric
    // but I don't like the result :)

    // First stage
    y1 = ((3*inputsignal)/2)*(1-((inputsignal*inputsignal)/3));

    // second stage
    y2 = ((3*y1)/2)*(1-((y1*y1)/3));

    // third stage
    y3 = ((3*y2)/2)*(1-((y2*y2)/3));

    /* at this point you can return Y3 (you have a tube emulation)
     but if you want you can continue and push further the
     formula to add more tubes ! */

    if (stage == 4) {
        // fourth stage / tube
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        return y4;
    } else
    if (stage == 5) {
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        // fifth stage / tube
        y5 = ((3*y4)/2)*(1-((y4*y4)/3));
        return y5;
    }
    else
    if (stage == 6) {
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        y5 = ((3*y4)/2)*(1-((y4*y4)/3));
        // sixth stage
        y6 = ((3*y5)/2)*(1-((y5*y5)/3));
        return y6;
    }
    else
    if (stage == 7) {
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        y5 = ((3*y4)/2)*(1-((y4*y4)/3));
        y6 = ((3*y5)/2)*(1-((y5*y5)/3));
        // seventh stage
        y7 = ((3*y6)/2)*(1-((y6*y6)/3));
        return y7;
    }
    else
    if (stage == 8) {
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        y5 = ((3*y4)/2)*(1-((y4*y4)/3));
        y6 = ((3*y5)/2)*(1-((y5*y5)/3));
        y7 = ((3*y6)/2)*(1-((y6*y6)/3));
        // Eigth stage
        y8 = ((3*y7)/2)*(1-((y7*y7)/3));
        return y8;
    }
    else
    if (stage == 9) {
        y4 = ((3*y3)/2)*(1-((y3*y3)/3));
        y5 = ((3*y4)/2)*(1-((y4*y4)/3));
        y6 = ((3*y5)/2)*(1-((y5*y5)/3));
        y7 = ((3*y6)/2)*(1-((y6*y6)/3));
        y8 = ((3*y7)/2)*(1-((y7*y7)/3));
        // Eigth stage
        y9 = ((3*y8)/2)*(1-((y8*y8)/3));
        return y9;
    }
    else return y3;
}

// tube vaccum simple emulator OPTIMIZED
// USE THIS ONE !!!
float cleanvacuumtube_optimised(float inputsignal, int stage)
{
    // tube vaccum simple emulator
    // quite clean and boost :)
    float y1, y2, y3, y4, y5, y6, y7,y8,y9;

    //if (inputsignal < 0.0) // Half wave
    //  inputsignal=-1.0f*(inputsignal);
    // in a tube simulation we should do do asymtetric
    // but I don't like the result :)

    // First stage
    y1 = ((3*inputsignal)/2)*(1-((fast_pow(inputsignal,2))/3));

    // second stage
    y2 = ((3*y1)/2)*(1-((fast_pow(y1,2))/3));

    // third stage
    y3 = ((3*y2)/2)*(1-((fast_pow(y2,2))/3));


    if (stage == 4) {
        // fourth stage
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        return y4;
    } else
    if (stage == 5) {
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        // fifth stage
        y5 = ((3*y4)/2)*(1-((fast_pow(y4,2))/3));
        return y5;
    }
    else
    if (stage == 6) {
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        y5 = ((3*y4)/2)*(1-((fast_pow(y4,2))/3));
        // sixth stage
        y6 = ((3*y5)/2)*(1-((fast_pow(y5,2))/3));
        return y6;
    }
    else
    if (stage == 7) {
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        y5 = ((3*y4)/2)*(1-((fast_pow(y4,2))/3));
        y6 = ((3*y5)/2)*(1-((fast_pow(y5,2))/3));
        // seventh stage
        y7 = ((3*y6)/2)*(1-((fast_pow(y6,2))/3));
        return y7;
    }
    else
    if (stage == 8) {
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        y5 = ((3*y4)/2)*(1-((fast_pow(y4,2))/3));
        y6 = ((3*y5)/2)*(1-((fast_pow(y5,2))/3));
        y7 = ((3*y6)/2)*(1-((fast_pow(y6,2))/3));
        // Eigth stage
        y8 = ((3*y7)/2)*(1-((fast_pow(y7,2))/3));
        return y8;
    }
    else
    if (stage == 9) {
        y4 = ((3*y3)/2)*(1-((fast_pow(y3,2))/3));
        y5 = ((3*y4)/2)*(1-((fast_pow(y4,2))/3));
        y6 = ((3*y5)/2)*(1-((fast_pow(y5,2))/3));
        y7 = ((3*y6)/2)*(1-((fast_pow(y6,2))/3));
        y8 = ((3*y7)/2)*(1-((fast_pow(y7,2))/3));
        // Eigth stage
        y9 = ((3*y8)/2)*(1-((fast_pow(y8,2))/3));
        return y9;
    }
    else return y3;
}

// Guitar Tube emulator
// quite dirty !
float guitarvacuumtube(float inputsignal)
{
    // Guitar tube vaccum emulator
    // quite dirty
    float _x, y0,y1,y2,y3,y4;

    if (inputsignal >= 0.0)
      _x=(fabs(2*inputsignal)- inputsignal*inputsignal);
    else if (inputsignal < 0.0)
      _x=-(fabs(2*inputsignal)- inputsignal*inputsignal);

    // Output Gain :)
    //x = x *outputGain;

    // Hard Clipping of the second tube vacuum
    if (_x < -0.08905 && _x >= -1)
    {
      y0 = fabs(_x)-0.032847;
      y1 = 1.0-y0;
      y2 = pow(y1, 12); // ; fast_pow(y1, 12);
      y3 = y2/3;
      y4 = 3/4*(1-y1+y3)+0.01;
      return y4;
    }
    else if (_x >= -0.08905 && _x < 0.320018)
    {
        y4= -6.153*_x*_x+3.9375*_x;
        return y4;
    }
    else if (_x <= 1 && _x >= 0.320018)
    {
        y4 = 0.630035;
        // Uncomment if you want to get a more TB303 sound :-)
        //y0 = _x-0.032847;
        //y1 = 1.0-y0;
        //y2 = pow(y1, 12); // ; fast_pow(y1, 12);
        //y3 = y2/3;
        //y4 = 3/4*(1-y1+y3)+0.01;
        return y4;
    }
    else return _x;
    // fin du hard clipping

}

//
// END END
// ---- DISTO FUNCTIONS ------------------------------------
