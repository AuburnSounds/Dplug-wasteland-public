/**
XY Controller

Copyright: Copyright Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.xycontroller;

import core.atomic;
import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.pbrwidgets.knob;
import dplug.client.params;


/// A control to set two float parameters at once, like in Ableton Live.
class UIXYController : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    float marginPx = 4.0f; 

    RGBA pointColor = RGBA(220, 220, 255, 0);
    float pointRadiusPx = 3.0f;
    float pointAlpha = 0.75f;

    ushort backgroundDepth = 10000;

    this(UIContext context, FloatParameter paramX, FloatParameter paramY)
    {
        super(context, flagRaw);
        _paramX = paramX;
        _paramY = paramY;
        _paramX.addListener(this);
        _paramY.addListener(this);
    }

    ~this()
    {
        _paramX.removeListener(this);
        _paramY.removeListener(this);
    }    

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        vec2f paramValues = directMapping(x, y);
        if (mstate.altPressed)
        {
            paramValues.x = _paramX.getNormalizedDefault();
            paramValues.y = _paramY.getNormalizedDefault();
        }
        _paramX.beginParamEdit();
        _paramY.beginParamEdit();
        _paramY.setFromGUINormalized(paramValues.y);
        _paramX.setFromGUINormalized(paramValues.x);        
        _paramX.endParamEdit();
        _paramY.endParamEdit();
        return true;
    }

    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        if (mstate.altPressed)
            return;
        vec2f paramValues = directMapping(x, y);
        _paramY.setFromGUINormalized(paramValues.y);
        _paramX.setFromGUINormalized(paramValues.x);        
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
        _paramX.beginParamEdit();
        _paramY.beginParamEdit();
    }

    override void onStopDrag()
    {
        _paramX.endParamEdit();
        _paramY.endParamEdit();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
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
            auto cRaw = rawMap.cropImageRef(dirtyRect);

            float valueX = _paramX.getNormalized();
            float valueY = _paramY.getNormalized();
            vec2f pos = inverseMapping(valueX, valueY);

            cRaw.aaSoftDisc(pos.x - dx, pos.y - dy, 0, pointRadiusPx*5, pointColor, pointAlpha * 0.2f);
            cRaw.aaSoftDisc(pos.x - dx, pos.y - dy, pointRadiusPx, pointRadiusPx+1, pointColor, pointAlpha);

            // draw potential position on mouse movements
            if (isMouseOver && !isDragged && containsPoint(_lastMouseX, _lastMouseY))
            {
                vec2f posMouse = vec2f(_lastMouseX, _lastMouseY);
                vec2f paramValues = directMapping(posMouse.x, posMouse.y);
                vec2f posRemap = inverseMapping(paramValues.x, paramValues.y);
                cRaw.aaSoftDisc(posRemap.x - dx, posRemap.y - dy, 0, pointRadiusPx*5, pointColor, pointAlpha * 0.2f * 0.5f);
                cRaw.aaSoftDisc(posRemap.x - dx, posRemap.y - dy, pointRadiusPx, pointRadiusPx+1, pointColor, pointAlpha * 0.5f);
            }
        }           
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

    int _lastMouseX;
    int _lastMouseY;
    FloatParameter _paramX;
    FloatParameter _paramY;

    /// Get parameters normalized values from pixel coordinates
    final vec2f directMapping(float x, float y)
    {
        int W = position.width;
        int H = position.height;
        float valueX = linmap!float(x, marginPx, W-1-marginPx, 0.0f, 1.0f);
        float valueY = linmap!float(y, marginPx, H-1-marginPx, 1.0f, 0.0f); // high mouse => high values of the parameter
        if (valueX < 0) valueX = 0;
        if (valueX > 1) valueX = 1;
        if (valueY < 0) valueY = 0;
        if (valueY > 1) valueY = 1;
        return vec2f(valueX, valueY);
    }

    /// From normalized parameters, return the pixel position
    final vec2f inverseMapping(float paramXNormalized, float paramYNormalized)
    {
        int W = position.width;
        int H = position.height;
        float minX = marginPx;
        float minY = marginPx;
        float maxX = W - 1 - marginPx;
        float maxY = W - 1 - marginPx;

        float valueX = linmap!float(paramXNormalized, 0, 1, minX, maxX);
        float valueY = linmap!float(paramYNormalized, 1, 0, minX, maxX);
        if (valueX < minX) valueX = minX;
        if (valueY < minY) valueY = minY;
        if (valueX > maxX) valueX = maxX;
        if (valueY > maxY) valueY = maxY;
        return vec2f(valueX, valueY);
    }
}
