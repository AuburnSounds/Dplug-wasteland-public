/**
* Copyright: Cut Through Recordings 2019
* License:   GPL v3
* Authors:   Ethan Reker
*/

module popmeter;

import dplug.graphics;
import dplug.gui;
import dplug.core.nogc;
import dplug.client.params;

import ddsp.util.scale;
import ddsp.util.functions;

import std.algorithm;

class PopMeter : UIBufferedElementRaw, IParameterListener
{
    this(UIContext context, RGBA inColor, RGBA outColor, uint size, uint windowSize, FloatParameter thresholdParam) nothrow @nogc
    {
        super(context, flagRaw);
        _inColor = inColor;
        _outColor = outColor;
        _size = size;
        _windowSize = windowSize;
        inBars = mallocSlice!float(_size);
        outBars = mallocSlice!float(_size);
        writeIndex = 0;
        foreach(index; 0..size)
        {
            inBars[index] = 0.005;
            outBars[index] = 0.005;
        }
        _param = thresholdParam;
        _param.addListener(this);
        scale.initialize(RealRange(0.00001f, 1.0f), RealRange(0.00001f, 1.0f));
    }
    
    ~this()
    {
        _param.removeListener(this);
    }
    
    override void onDrawBufferedRaw(ImageRef!RGBA rawMap, ImageRef!L8 opacity) nothrow @nogc
    {
        assert(_size <= rawMap.w);

        {
            opacity.fillAll(L8(255));
        }
        
        float threshold = interpInput(xVals, yVals, 7, decibelToFloat(_param.value()));
        int thresholdY = cast(int)(rawMap.h * (1 - threshold));
        thresholdY = clamp(thresholdY, 0, rawMap.h - 1);

        for(int j = 0; j < rawMap.h; ++j)
        {
            auto output = rawMap.scanline(j);
            for(int i = 0; i < rawMap.w; ++i)
            {
                //Starts from the most recently added value and then moves along the buffers based on i
                //This way the the meter should seem to move. Each time the index increments, all of the data
                //should move 1px to the left
                size_t index = (writeIndex + i) % _size;
                float inBarHeight = inBars[index];
                float outBarHeight = outBars[index];
                
                int inY = cast(int)(rawMap.h * (1 - inBarHeight));
                int outY = cast(int)(rawMap.h * (1 - outBarHeight));
                RGBA blended = RGBA(0, 0, 0,255);
                ubyte alpha = 255;
                if(j >= inY)
                {
                    blended = blendColor(_inColor, blended, alpha);
                }
                if(j >= outY)
                {
                    if(j < inY)
                    {
                        blended = RGBA(0, 0,255,255);
                    }
                    else
                    {
                        blended = blendColor(_outColor, blended, cast(ubyte)(alpha/2));
                    }
                }
                if(j == thresholdY)
                    blended = RGBA(120, 120, 120, 255);
                output[i] = blended;
            }
        }
    }
    
    void pushBackValues(float input, float output, float sampleRate) nothrow @nogc
    {
        float samplesPerSec = sampleRate / 2000;
        ++counter;
        if(counter >= samplesPerSec / speed)
        {
            if(++writeIndex >= _size)
            {
                writeIndex = 0;
            }
            float inConv = interpInput(xVals, yVals, 7, input);
            float outConv = interpInput(xVals, yVals, 7, output);
            inBars[writeIndex] = clamp(inConv, 0, 1);
            outBars[writeIndex] = clamp(outConv, 0, 1);
            //inBars[writeIndex] = input;
            //outBars[writeIndex] = output;
            setDirtyWhole();
            counter = 0;
        }
        //inBars[writeIndex] = input;
        //outBars[writeIndex] = output;
        //setDirtyWhole();
    
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }
    
private:
    RGBA _inColor;
    RGBA _outColor;
    float[] inBars;
    float[] outBars;
    
    size_t writeIndex;
    
    uint _size;
    uint _windowSize;

    LogToLinearScale scale = new LogToLinearScale();

    float _sampleRate;
    int counter;
    float speed = 40;

    FloatParameter _param;

    float[] xVals = [1, 0.7079457844, 0.5011872336, 0.2511886432, 0.0630957344, 0.0039810717, 0.0000158489];
    float[] yVals = [1, 0.833333333, 0.666666666, 0.5, 0.333333333, 0.166666666, 0];
}

float interpInput(float[] xVals, float[] yVals, int order, float input) nothrow @nogc
{
    float interp = 0;
    for(int i = order - 1; i > 0; --i)
    {
        if(xVals[i - 1] >= input && xVals[i] < input)
        {
            interp = linearInterp(xVals[i -1], xVals[i], yVals[i - 1], yVals[i], input);
        }
    }
    return interp;
}
