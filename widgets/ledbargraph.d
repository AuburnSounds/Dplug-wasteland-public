/**
LED BARGRAPH Widget

Copyright: SMAOLAB 2025
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Author:   Stephane Ribas

Note 1 : This is a very naive and simple LED BARGRAPH
Note 2 : part of the code is inspired by Guillaume Piolat

  --- TUTORIAL BEFORE THE CODE -----

1- In gui.d, , at the top, declare :

...
import ledbargraph;
...

2- In gui.d, , at the end, in the private section, declare :

Private: 
    ...
    UILEDBargraph inputBargraph, outputBargraph; // we declare a bargraph for the input osund and the output sound...
    ...

3- then, in gui.d, in the THIS function, write the following code : 

...
class AkiraTubeGUI : FlatBackgroundGUI!("new-akiratubebck.jpg") 
{
public:
nothrow:
@nogc:

    ...

    this(AkiraTubeClient client)
    {
        ...
        _client = client; // important !
        ...
        // we declare the LED bargraph widgetS
        addChild(inputBargraph = mallocNew!UILEDBargraph(context(), 2, -119.0f, 6.0f)); // -119 MIN DB AND MAX 6DB...
        addChild(outputBargraph = mallocNew!UILEDBargraph(context(), 2, -119.0f, 12.0f));
        ...
    }
...

4- then ,in gui.d, in the 'reflow' function, write the following code : 

override void reflow()
    {
        super.reflow();

        int W = position.width;
        int H = position.height;

        float _textresizefactor, _textspacingresizefactor;

        float S = W / cast(float)(context.getDefaultUIWidth());
        _textresizefactor= 20*S; // 20 or 32 ... depends on your fonts :-)
        _textspacingresizefactor = 2.0f *S;
        ...

        // bar graph
        inputBargraph.position = rectangle(18, 45, 20, 540).scaleByFactor(S);
        outputBargraph.position = rectangle(75, 45, 20, 540).scaleByFactor(S);
    ...
    }

5- then ,in gui.d, after the 'reflow' function, write the following code : 
// LED BARS 
void sendoutputBargraphLinearValueToUI(float* signal,int frames, float sampleRate)
{
    outputBargraph.sendLinearValueToUI(signal, frames, sampleRate);
}
void sendinputBargraphLinearValueToUI(float* signal,int frames, float sampleRate)
{
    inputBargraph.sendLinearValueToUI(signal, frames, sampleRate);
}

// Very important to add those functions as ... from the main.d, we are going to pass the sound buffers (input and output) 
// to those functions that are belonging to the bargraph widget and the bargraph widget calculates the sound level to 
// create the led level :-)

// Note that sendlinearValue expect a linear buffer not in DECIBELS ! If you want to send a buffer that contains Decibels Value 
// you need to change the function and use instead "sendValueToUI" 

6 - in main.d, complete the following code : 

...
        // Get access to the GUI
        // --------------------------------------------
        if (AkiraLeadGUI gui = cast(AkiraLeadGUI) graphicsAcquire())
        {
                gui.sendinputBargraphLinearValueToUI(input_sound_buffer.ptr, frames, _sampleRate); // input_sound_buffer is the inoput sound that you are manipulating
                gui.sendoutputBargraphLinearValueToUI(outputs[0], frames, _sampleRate);// output leds bargraph :-)
                graphicsRelease();
        }
...

7- that's all :-)
*/

module ledbargraph;

import std.math;

import dplug.gui;
import dplug.canvas;
//import dplug.core.unchecked_sync;
import dplug.core;
import std.algorithm.comparison; // clamp
import dplug.client; // for timeinfo

// Vertical bargraphs made of LEDs
class UILEDBargraph : UIElement
{
public:
nothrow:
@nogc:

    // FIFO 
    enum READ_OVERSAMPLING = 2048;//512; impact the refresh rate
    enum INPUT_SUBSAMPLING = 512;//128; impact the refresh rate
    enum SAMPLES_IN_FIFO = 2048; //needed at start to fill the buffer 

    /// How to fill pixels.
    struct LED
    {
        RGBA diffuse;
    }

    /// Creates a new bargraph.
    /// [minValue .. maxValue] is the interval of values that will span [0..1] once remapped.
    this(UIContext context, int numChannels, float minValue, float maxValue,
         int redLeds = 7, int orangeLeds = 15, int yellowLeds = 23, int magentaLeds = 63)
    {
        super(context, flagRaw | flagPBR | flagAnimated);

        //_values.length = 2;//numChannels;
        _values[] = 0;

        _minValue = minValue;
        _maxValue = maxValue;

        foreach (i; 0..redLeds)
            _leds[i] = LED(RGBA(192, 32, 32, 255));
        foreach (i; redLeds+1..orangeLeds)
            _leds[i] = LED(RGBA(0, 255, 32, 255)); 
        foreach (i; orangeLeds+1..yellowLeds)
            _leds[i] = LED(RGBA(48, 128, 32, 255)); 
        foreach (i; yellowLeds+1..magentaLeds)
            _leds[i] = LED(RGBA(96, 64, 32, 255));

        _redLeds = redLeds;
        _orangeLeds = orangeLeds;//redLeds+orangeLeds;
        _yellowLeds = yellowLeds;//orangeLeds+yellowLeds;
        _magentaLeds = magentaLeds;//yellowLeds+magentaLeds;

        // FIFO 
        _timedFIFO.initialize(SAMPLES_IN_FIFO, INPUT_SUBSAMPLING);
        _stateToDisplay[] = minValue;
    }

    ~this()
    {
    }

    // FIFO
    override void onAnimate(double dt, double time)
    {
        bool needRedraw = false;
        // Note that readOldestDataAndDropSome return the number of samples
        // stored in _stateToDisplay[0..ret].
        if (_timedFIFO.readOldestDataAndDropSome(_stateToDisplay[], dt, READ_OVERSAMPLING))
        {
            needRedraw = false; //true; // I inverse...
            //debugLogf("-- redraw TRUE ---%d",_timedFIFO.readOldestDataAndDropSome(_stateToDisplay[], dt, READ_OVERSAMPLING));
        } else 
        {
            needRedraw = true; // false; I inverse
            // debugLogf("-- redraw --false----- %d",_timedFIFO.readOldestDataAndDropSome(_stateToDisplay[], dt, READ_OVERSAMPLING));

        }

        // Only redraw the Raw layer. This is key to have low-CPU UI widgets that can
        // still render on the PBR layer.
        // Note: You can further improve CPU usage by not redrawing if the displayed data
        // has been only zeroes for a while.
        if (needRedraw)
            setDirtyWhole(UILayer.rawOnly);


    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        int numLeds = cast(int)_leds.length;
        int numChannels = cast(int)_values.length;
        int width = _position.width;
        int height = _position.height;
        float borderw = width * 0.06f;
        float borderh = height* 0.06f;

       // box2f available = box2f(borderw, borderw, width - borderw, height - borderw);
        box2f available = box2f(borderw, borderh, width - borderw, height - borderh);

        float heightPerLed = cast(float)(available.height) / cast(float)numLeds;
        float widthPerLed = cast(float)(available.width) / cast(float)numChannels;

        float tolerance = 1.0f / numLeds;
        float x0,x1;

        foreach(channel; 0..numChannels)
        {
            float value = getValue(channel);

            x0 = borderw + widthPerLed * (channel + 0.15f);
            x1 = x0 + widthPerLed * 0.7f;    
            
            foreach(dirtyRect; dirtyRects)
            {
                auto cRaw = rawMap.cropImageRef(dirtyRect);
                canvas.initialize(cRaw);
                canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);
            }

            foreach(i;0.._redLeds)
            {
                float y0 = borderw + heightPerLed * (i + 0.1f); // original
                float y1 = y0 + heightPerLed * 0.8f; // original
        
                float ratio = 1 - i / cast(float)(numLeds - 1);

                ubyte shininess = cast(ubyte)(0.5f + 160.0f * (1 - smoothStep(value - tolerance, value, ratio)));

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * (255 + shininess) + 255) / 510;
                color.g = (color.g * (255 + shininess) + 255) / 510;
                color.b = (color.b * (255 + shininess) + 255) / 510;
                color.a = shininess;
                
                // bar level
                canvas.fillStyle = color;
                canvas.fillCircle(x1, y1,  _circlesize);
            }

            foreach(i;_redLeds+1.._orangeLeds)
            {
                float y0 = borderw + heightPerLed * (i + 0.1f); // original
                float y1 = y0 + heightPerLed * 0.8f; // original
        
                float ratio = 1 - i / cast(float)(numLeds - 1);

                ubyte shininess = cast(ubyte)(0.5f + 160.0f * (1 - smoothStep(value - tolerance, value, ratio)));

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * (255 + shininess) + 255) / 510;
                color.g = (color.g * (255 + shininess) + 255) / 510;
                color.b = (color.b * (255 + shininess) + 255) / 510;
                color.a = shininess;
                
                // bar level
                canvas.fillStyle = color;
                canvas.fillCircle(x1, y1,  _circlesize);
            }

            foreach (i; _orangeLeds+1.._yellowLeds)
            {
                float y0 = borderw + heightPerLed * (i + 0.1f); // original
                float y1 = y0 + heightPerLed * 0.8f; // original
        
                float ratio = 1 - i / cast(float)(numLeds - 1);

                ubyte shininess = cast(ubyte)(0.5f + 160.0f * (1 - smoothStep(value - tolerance, value, ratio)));

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * (255 + shininess) + 255) / 510;
                color.g = (color.g * (255 + shininess) + 255) / 510;
                color.b = (color.b * (255 + shininess) + 255) / 510;
                color.a = shininess;
                
                // bar level
               canvas.fillStyle = color;
               canvas.fillCircle(x1, y1,  _circlesize);
            }

            foreach (i; _yellowLeds+1.._magentaLeds)
            {
                float y0 = borderw + heightPerLed * (i + 0.1f); // original
                float y1 = y0 + heightPerLed * 0.8f; // original
        
                float ratio = 1 - i / cast(float)(numLeds - 1);

                ubyte shininess = cast(ubyte)(0.5f + 160.0f  * (1 - smoothStep(value - tolerance, value, ratio)));

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * (255 + shininess) + 255) / 510;
                color.g = (color.g * (255 + shininess) + 255) / 510;
                color.b = (color.b * (255 + shininess) + 255) / 510;
                color.a = shininess;
                
                // bar level
                canvas.fillStyle = color;
                canvas.fillCircle(x1, y1,  _circlesize);
            }
            
        }
    }

    void setValues(float[] values, float peak) nothrow @nogc
    {
        assert(values.length == _values.length);

        // remap all values
        foreach(i; 0..values.length)
        {
            _values[i] =convertLinearGainToDecibel(peak);
            _values[i] = linmap!float(values[i], _minValue, _maxValue, 0, 1);
            _values[i] = clamp!float(_values[i], 0, 1);
        }
        setDirtyWhole();
    }
    
    void setValuesinDb(float[] values, float peak) nothrow @nogc
    {
        assert(values.length == _values.length);

        // remap all values
        foreach(i; 0..values.length)
        {
            _values[i] = convertLinearGainToDecibel(peak);
            _values[i] = linmap!float(values[i], _minValue, _maxValue, 0, 1);
            _values[i] = clamp!float(_values[i], 0, 1);
        }
        setDirtyWhole();
    }

    float getValue(int channel) nothrow @nogc
    {
        return _values[channel];
    }

    // FIFO
    void sendValueToUI(float* measuredLevel_dB,
                          int frames,
                          float sampleRate) nothrow @nogc
    {
        peak = fast_fabs(measuredLevel_dB[0]);
        if (_storeTemp.length < frames)
            _storeTemp.reallocBuffer(frames);

        for(int n = 0; n < frames; ++n)
        {
            _storeTemp[n] = measuredLevel_dB[n];
            if (_storeTemp[n]>peak)
                peak = _storeTemp[n];
        }

        setValuesinDb(_values, peak);
        _timedFIFO.pushData(_storeTemp[0..frames], sampleRate);
    }

    // FIFO
    void sendLinearValueToUI(float* measuredLevel,
                          int frames,
                          float sampleRate) nothrow @nogc
    {
        peak = fast_fabs(measuredLevel[0]);

        if (_storeTemp.length < frames)
            _storeTemp.reallocBuffer(frames);

        for(int n = 0; n < frames; ++n)
        {
            _storeTemp[n] = fast_fabs(measuredLevel[n]);
            if (_storeTemp[n]>peak)
                peak = _storeTemp[n];
        }

        setValues(_values, peak);

        _timedFIFO.pushData(_storeTemp[0..frames], sampleRate);
    }

    override void reflow()
    {
        int W = position.width;
        _circlesize = _circlesize * W / 20;
        if (_circlesize<=3) _circlesize =3;
    }

protected:
    LED[64] _leds;
    int _redLeds; 
    int _orangeLeds;
    int _yellowLeds; 
    int _magentaLeds;

    float[2] _values;
    float _minValue;
    float _maxValue;

    int _circlesize = 3; // led size

    Canvas canvas;

    // FIFO
    TimedFIFO!float _timedFIFO;
    float[READ_OVERSAMPLING] _stateToDisplay; // samples, integrated for drawing
    float[] _storeTemp; // used for gathering input
    float absval, peak;
}

// end
