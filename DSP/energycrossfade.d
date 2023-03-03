module crossfader;

import std.math;
import std.algorithm;
import std.complex;

import  dplug.core,
        dplug.dsp;

import inteli.math;

public:
nothrow:
@nogc:

// Beaware that this crossfader is good especially when two different signals may be mixed together. It is very efficient if you are scared than one of the signal may impact the other one.
// read more from https://signalsmith-audio.co.uk/writing/2021/// cheap-energy-crossfade/
// I do use it on many plugins eventough the signals are similar, it gives a nice crossfafe feeling..

struct Cross_fade
{
  public:
  nothrow:
  @nogc:

void energyCrossfadePair(float mix)
{
    float x2 = 1 - mix;
    float A = mix*x2;
    float B = A*(1 + 1.4186*A);
    float C = (B + mix);
    float D = (B + x2);
    fadeIn = C*C;
    fadeOut = D*D;
}

float getfadeIn()
{
    return fadeIn;
}
float getfadeOut()
{
    return fadeOut;
}

private:
    float fadeIn = 1.0f;
    float fadeOut = 0.0f;
}
// end

// exemple:
// you declare :
// ...
// Cross_fade _fade;
// float mix;
// ...
// ...
// DECLARE THE MIX PARAM
// params.pushBack(mallocNew!LinearFloatParameter(paramMix, "Dry/Wet", "%", 0.0f, 100.0f, 100.0f) ); ...
// ...
// ...
// READ THE MIX PARAM
//  mix = readParam!float(paramMix) / 100.0f;
// ...
// _fade.energyCrossfadePair(mix);
// ...
/* for (int f = 0; f < frames; ++f)
{
    outputs[0][f] = (outputs[0][f] * _fade.getfadeIn) + ((inputs[0][f]*inputGain) * _fade.getfadeOut);
    outputs[1][f] = (outputs[1][f] * _fade.getfadeIn) + ((inputs[1][f]*inputGain) * _fade.getfadeOut);
}*/
// that's it !
