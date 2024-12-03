/**
Y axis Controller // VERTICAL slider

Copyright: Copyright Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)

Modified by rstephane (SMAO)
*/

/*  --- TUTORIAL BEFORE THE CODE -----

-----
|   |
|   |
|   |
| o |
|   |
|   |
|   |
-----

The user point its mouse on the item area ... 

1- In gui.d, , at the top, declare :

import yaxiscontroller;
...

2- then, in gui.d, write the following code : 
...
this(BlablablablaClient client)
{
  _client = client;
...

  // InputGain Vertical Slider
  UIYAXISController inputGainSlider = mallocNew!UIYAXISController(context(), cast(FloatParameter) _client.param(paramInput));
  addChild(inputGainSlider);
...
}

3- then ,in gui.d, write the following code : 

override void reflow()
{
  super.reflow();
  ...
  
  inputGainSlider.position = box2i(120, 50, 195, 135); //  becarefull of the figures you set here ;)

  ...
}

4- that's all :-)
*/
module yaxiscontroller;

import core.atomic;
import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.client.params;
import utils;
//import interpolation;

/// A control to set two float parameters at once, like in Ableton Live.
/// behaves like and draw an hpf filter...

class UIYAXISController : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    float marginPx = 4.0f;

    RGBA pointColor = RGBA(220, 220, 255, 0);
    float pointRadiusPx = 4.0f;
    float pointAlpha = 0.75f;

    RGBA pointColorRed = RGBA(165, 35, 33, 0);
    RGBA pointColorBlue = RGBA(254, 255, 3, 0);

    ushort backgroundDepth = 10000;

    this(UIContext context, FloatParameter paramY)
    {
        super(context, flagRaw);
        _paramY = paramY;
        _paramY.addListener(this);
    }

    ~this()
    {
        _paramY.removeListener(this);
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (!containsPoint(x, y))
            return Click.unhandled;
        
        float paramValuesY = 1.0f-directMapping(y);

        // double-click => set to default
        if (isDoubleClick || mstate.altPressed)
        {
            _paramY.beginParamEdit();
            if (auto fp = cast(FloatParameter)_paramY)
                fp.setFromGUI(fp.defaultValue());
            else if (auto ip = cast(IntegerParameter)_paramY)
                ip.setFromGUI(ip.defaultValue());
            else
                assert(false);
            _paramY.endParamEdit();
        }

        if (mstate.altPressed)
        {
            paramValuesY = _paramY.getNormalizedDefault();
        }
        _paramY.beginParamEdit();
        _paramY.setFromGUINormalized(paramValuesY);
        _paramY.endParamEdit();
        return Click.startDrag;
    }

    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseY = y;
        //if (mstate.altPressed)
        //    return Click.startDrag;
        float paramValuesY = 1.0f-directMapping(y);
        _paramY.setFromGUINormalized(paramValuesY); 
        //return Click.startDrag;
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

    override void onBeginDrag()
    {
        _paramY.beginParamEdit();
    }

    override void onStopDrag()
    {
        _paramY.endParamEdit();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseY = y;
        setDirtyWhole();
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        foreach(dirtyRect; dirtyRects)
        {
            int dx = dirtyRect.min.x;
            int dy = dirtyRect.min.y;

            int dmx = dirtyRect.max.x; // SMAOLAB
            int dmy = dirtyRect.max.y; // SMAOLAB

            auto cRaw = rawMap.cropImageRef(dirtyRect);

            float valueY = 1.0f-_paramY.getNormalized();
            float pos = inverseMapping(valueY);

            // the main ball :-)
            //cRaw.aaSoftDisc(pos.x - dx, pos.y - dy, 0, pointRadiusPx*5, pointColorRed, pointAlpha * 0.2f);
            //cRaw.softRing(pos - dx, (dmy-dy)/2,pointRadiusPx,pointRadiusPx*2,pointRadiusPx*3, pointColorRed);
            //cRaw.aaSoftDisc(pos - dx, (dmy-dy)/2, pointRadiusPx, pointRadiusPx+1, pointColorBlue, pointAlpha);

            //cRaw.softRing((dmx-dx)/2,pos - dy,pointRadiusPx,pointRadiusPx*2,pointRadiusPx*3, pointColorRed);
            cRaw.aaSoftDisc((dmx-dx)/2,pos - dy, pointRadiusPx, pointRadiusPx+1, pointColorBlue, pointAlpha);

            // draw potential position on mouse movements
            if (isMouseOver && !isDragged && containsPoint(_lastMouseX, _lastMouseY))
            {
                float posMouseY = _lastMouseY;
                float paramValuesY = directMapping(posMouseY);
                float posRemapY = inverseMapping(paramValuesY);
                //cRaw.aaSoftDisc(posRemapX - dx, (dmy-dy)/2, 0, pointRadiusPx*5, pointColor, pointAlpha * 0.2f * 0.5f);
                //cRaw.aaSoftDisc(posRemapX - dx, (dmy-dy)/2, pointRadiusPx, pointRadiusPx+1, pointColor, pointAlpha * 0.5f);
                cRaw.aaSoftDisc((dmx-dx)/2, posRemapY - dy, 0, pointRadiusPx*5, pointColor, pointAlpha * 0.2f * 0.5f);
                cRaw.aaSoftDisc((dmx-dx)/2, posRemapY - dy, pointRadiusPx, pointRadiusPx+1, pointColor, pointAlpha * 0.5f);
            }
        }
    }

        override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

    bool containsPoint(int x, int y, float tolerance = 30) nothrow @nogc
    {
        if (x < 0)
            return false;
        if (y < 0)
            return false;
        if (x > _position.width)
            return false;
        if (y > _position.height)
            return false;
        return true;
    }

private:

    float _y0,_x0,_y1,_x1,_y2,_x2,_y3,_x3;
    float _y10,_x10,_y11,_x11,_y12,_x12,_y13,_x13;

    int _lastMouseX;
    int _lastMouseY;
    FloatParameter _paramX;
    FloatParameter _paramY;

    //HermiteCubicSegment _interpolation;

    /// Get parameters normalized values from pixel coordinates
    final float directMapping(float x)
    {
        int W = position.width;
        float valueX = linmap!float(x, marginPx, W-1-marginPx, 0.0f, 1.0f);
        if (valueX < 0) valueX = 0;
        if (valueX > 1) valueX = 1;
        return valueX;
    }

    /// From normalized parameters, return the pixel position
    final float inverseMapping(float paramXNormalized)
    {
        int W = position.width;
        float minX = marginPx;
        float maxX = W - 1 - marginPx;

        float valueX = linmap!float(paramXNormalized, 0, 1, minX, maxX);
        if (valueX < minX) valueX = minX;
        if (valueX > maxX) valueX = maxX;
        return valueX;
    }

}
