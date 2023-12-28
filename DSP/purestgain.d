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
module purestgain;

import dplug.core;
import inteli.math;

/// A nice gift From AirWindows: https://github.com/airwindows/
/// It is a very quick gain smoothing intended for sliders. Neat to use.
/// You need to mention its lience and copyright notice in released product.
struct PurestGain(SampleType)
{
nothrow:
@nogc:

    void initialize(float sampleRate, int channels) // no sampleRate! PurestGain doesn't work like that
    {
        _sampleRate = sampleRate;
        _channels = channels;

        gainchase = -90.0;
        settingchase = -90.0;
        gainBchase = -90.0;
        chasespeed = 350.0;
    }

    void nextBuffer(SampleType** inoutSamples, 
                    int frames,
                    float gain)
    {
   /*     double overallscale = 1.0;
        overallscale /= 44100.0;
        overallscale *= _sampleRate;
*/
        double inputgain = 0;
        if (settingchase != inputgain) 
        {
            chasespeed *= 2.0;
            settingchase = inputgain;
            //increment the slowness for each fader movement
            //continuous alteration makes it react smoother
            //sudden jump to setting, not so much
        }

        if (chasespeed > 2500.0) 
            chasespeed = 2500.0;
        //bail out if it's too extreme
        if (gainchase < -60.0) 
        {
            gainchase = _mm_pow_ss(10.0f, inputgain / 20.0f);
            //shouldn't even be a negative number
            //this is about starting at whatever's set, when
            //plugin is instantiated.
            //Otherwise it's the target, in dB.
        }
        double targetgain;	
        //done with top controller
        double targetBgain = convertDecibelToLinearGain(gain);
        if (gainBchase < 0.0) 
            gainBchase = targetBgain;

        //this one is not a dB value, but straight multiplication
        //done with slow fade controller
        double outputgain;

        targetgain = _mm_pow_ss(10.0, settingchase/20.0);

        if (_channels == 1)
        {
            SampleType* pL = inoutSamples[0];
            for (int n = 0; n < frames; ++n)
            {            
                //now we have the target in our temp variable
                chasespeed *= 0.9999;
                chasespeed -= 0.01;
                if (chasespeed < 350.0) chasespeed = 350.0;
                //we have our chase speed compensated for recent fader activity
                gainchase = (((gainchase*chasespeed)+targetgain)/(chasespeed+1.0));
                //gainchase is chasing the target, as a simple multiply gain factor
                gainBchase = (((gainBchase*4000)+targetBgain)/4001);
                //gainchase is chasing the target, as a simple multiply gain factor
                outputgain = gainchase * gainBchase;
                //directly multiply the dB gain by the straight multiply gain
                pL[n] *= outputgain;
            }
        }
        else if (_channels == 2)
        {
            SampleType* pL = inoutSamples[0];
            SampleType* pR = inoutSamples[1];
            for (int n = 0; n < frames; ++n)
            {            
                //now we have the target in our temp variable
                chasespeed *= 0.9999;
                chasespeed -= 0.01;
                if (chasespeed < 350.0) chasespeed = 350.0;
                //we have our chase speed compensated for recent fader activity
                gainchase = (((gainchase*chasespeed)+targetgain)/(chasespeed+1.0));
                //gainchase is chasing the target, as a simple multiply gain factor
                gainBchase = (((gainBchase*4000)+targetBgain)/4001);
                //gainchase is chasing the target, as a simple multiply gain factor
                outputgain = gainchase * gainBchase;
                //directly multiply the dB gain by the straight multiply gain
                pL[n] *= outputgain;
                pR[n] *= outputgain;
            }
        }

    }

private:
    float _sampleRate;
    int _channels;

    //default stuff
    double gainchase;
    double settingchase;
    double gainBchase;
    double chasespeed;
}





	
