module rawslider;

import core.atomic;
import std.math;

import dplug.core;
import dplug.gui;
import dplug.canvas;
import dplug.client;

import auburn.gui;
import gui;

/// A simple raw-layer slider in Lens, quite reusable for flat UIs
class UIRawSlider : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    enum Type
    {
        disc      = 0,  // a filled disc of radius given by `handleRadius`
        rectangle = 1,  // a filled rectangle of size:
                        //    * `handleRadius` x `handleRectRatio` in the main dimension
                        //    * `handleRadius` in the alternative dimension
    }

    @ScriptProperty Type type = Type.disc;

    /// If `true`, this is a vertical slider. Else, it is a horizontal slider.
    @ScriptProperty bool vertical = true;

    /// Color of the whole trail line.
    @ScriptProperty RGBA colorOff = RGBA(90, 90, 90, 255);

    /// Color of the trail line and handle in normal conditions.
    @ScriptProperty RGBA colorTrail = RGBA(90, 90, 120, 255);

    /// Color of the trail line and handle, when dragged.
    @ScriptProperty RGBA colorDragged = RGBA(255, 255, 0, 255);

    /// Color of the trail line and handle, when hovered.
    @ScriptProperty RGBA colorHovered = RGBA(255, 255, 255, 255);

    /// Color of the trail line and handle, when disabled.
    @ScriptProperty RGBA colorDisabled = RGBA(65, 65, 65, 255);

    /// Color of the potential handle to show what a click would do.
    @ScriptProperty RGBA colorPotentialHandle = RGBA(65, 65, 65, 255);

    /// Where the beginning of the trail is (0 = start, 1 = end)
    /// In a vertical slider, position 0 is bottom.
    /// In a horizontal slider, position 0 is left.
    @ScriptProperty float trailBase = 0.0f;

    /// Sensitivity of the slider, in fraction of the dominant dimension, given by `vertical`.
    @ScriptProperty float sensivity = 1.0f;  

    /// Width of the trail line, in fraction of the alternate dimension, given by `vertical`.
    @ScriptProperty float trailWidth = 0.1f;

    /// Size of the handle shape, in fraction of the alternative dimension, given by `vertical`.
    @ScriptProperty float handleRadius = 0.3f;

    // 1.0 => square handle   above => increasingly rectangular handle.
    // Only used if type is Type.rectangle.
    @ScriptProperty float handleRectRatio = 1.7f;

    // Width of the single line that strikes the handle, in ratio of the handle main axis dimension.
    @ScriptProperty float handleMarkWidth = 0.0f;

    // the color of that mark
    @ScriptProperty RGBA colorHandleMark = RGBA(255, 255, 255, 255); 
    @ScriptProperty RGBA colorHandleMarkDragged = RGBA(255, 255, 255, 255); 

    /// Do not show potential handle shape if it is too near to the original from this distance.
    /// In fraction of the alternative dimension, given by `vertical`.
    /// Below this margin, clicking without moving mouse doesn't change the parameter.
    @ScriptProperty float marginPotentialHandle = 0.6f;

    /// Size of the handle shape, when the mouse is over (this is animated).
    @ScriptProperty float handleRadiusHighlighted = 0.3f;

    /// Speed of radius growing for the handle.
    @ScriptProperty float animationSpeed = 8.0f;

    /// Not: `enableParam` can be `null`.
    this(UIContext context, Parameter param, Parameter enableParam)
    {
        super(context, flagRaw | flagAnimated);
        _param = cast(FloatParameter) param;
        _param.addListener(this);

        _enableParam = cast(BoolParameter) enableParam;
        if (_enableParam) _enableParam.addListener(this);
        clearCrosspoints();
    }

    ~this()
    {
        if (_enableParam) _enableParam.removeListener(this);
        _param.removeListener(this);
    }   
  
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        bool enabled = _enableParam ? _enableParam.value() : true;
        bool isVertical = vertical;

        float W = position.width;
        float H = position.height;

        float widthDimension = isVertical ? W : H;
        //float radiusPx = widthDimension * handleRadiusHighlighted;

        float M = mainAxisMargin(); // main axis margin


        /// Where the trail base is.
        vec2f A = trailStartPoint();
        vec2f B = trailStopPoint();
        vec2f Current = handlePoint(A, B);
        vec2f Base = trailBasePoint(A, B);
        vec2f PotentialHandle = potentialHandlePoint(A, B, _lastMouseX, _lastMouseY);

        // vector in width dimension

        vec2f widthV = isVertical ? vec2f(W * 0.5f, 0) : vec2f(0, H * 0.5f);

        float value = _param.getNormalized(); // 0 to 1

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);
            canvas.initialize(cRaw);
            canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);

            // Draw full "off" trail
            canvas.fillStyle = colorOff;
            canvas.beginPath();
            canvas.moveTo(A + widthV * trailWidth);
            canvas.lineTo(A - widthV * trailWidth);
            canvas.lineTo(B - widthV * trailWidth);
            canvas.lineTo(B + widthV * trailWidth);
            canvas.closePath();
            canvas.fill();

            // Draw "on" trail.
            RGBA color = colorTrail;
            if (isMouseOver) color = colorHovered;
            if (isDragged) color = colorDragged;
            if (!enabled) color = colorDisabled;
            canvas.fillStyle = color;
            canvas.beginPath();
            canvas.moveTo(Base + widthV * trailWidth);
            canvas.lineTo(Base - widthV * trailWidth);
            canvas.lineTo(Current - widthV * trailWidth);
            canvas.lineTo(Current + widthV * trailWidth);
            canvas.closePath();
            canvas.fill();

            // Draw potential handle, if we click.
            if (sliderCouldStartDragOnClick)
            {
                float potentialRadiusPx = widthDimension * handleRadius;
                
                if (!mouseTooCloseFromHandle(Current, PotentialHandle))
                {
                    drawHandle(canvas, PotentialHandle.x, PotentialHandle.y, potentialRadiusPx, handleRectRatio, colorPotentialHandle, true);
                }
            }

            // Draw actual handle.
            {
                float actualRadiusPx = widthDimension * (handleRadius + _animation * (handleRadiusHighlighted - handleRadius));
                drawHandle(canvas, Current.x, Current.y, actualRadiusPx, handleRectRatio, color, false);
            }
        }
    }

    final void drawHandle(ref Canvas canvas, float x, float y, float radius, float handleRectRatio, RGBA color, bool potential)
    {
        switch (type)
        {
            case Type.disc:
                canvas.fillStyle = color;
                canvas.fillCircle(x, y, radius);
                break;

            case Type.rectangle:
                float extentX = vertical ? radius : radius * handleRectRatio;
                float extentY = vertical ? radius * handleRectRatio : radius;
                canvas.fillStyle = color;
                canvas.fillRect(x - extentX, y - extentY, extentX*2, extentY*2);

                if (!potential)
                {
                    canvas.fillStyle = isDragged ? colorHandleMarkDragged : colorHandleMark;
                    canvas.fillRect(x - extentX, y - extentY * handleMarkWidth, extentX*2, extentY*2 * handleMarkWidth);
                }
                break;

            default:
                break;
        }
    }

    override void onParameterChanged(Parameter sender)
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
        setDirtyWhole();
    }

    override void onEndParameterEdit(Parameter sender)
    {
        setDirtyWhole();
    }
    override void onBeginParameterHover(Parameter sender){}
    override void onEndParameterHover(Parameter sender){}

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        enableSectionIfDisabled();
        _param.beginParamEdit();

        if (isDoubleClick || mstate.altPressed)
        {
            // double-click or ALT => set to default
            _param.setFromGUI(_param.defaultValue());
        }
        else
        {
            // Move value where we clicked, unless we are in the area where it's too close.

            vec2f A = trailStartPoint();
            vec2f B = trailStopPoint();
            vec2f Current = handlePoint(A, B);
            vec2f PotentialHandle = potentialHandlePoint(A, B, x, y);
            bool tooClose = mouseTooCloseFromHandle(Current, PotentialHandle);
            if (!tooClose)
                _param.setFromGUINormalized( convertPointToNormalizedValue(x, y) );
        }
        return Click.startDrag; // to initiate dragging
    }

    override void onBeginDrag()
    {
    }

    override void onStopDrag()
    {
        _param.endParamEdit();
    }

    override void onMouseEnter()
    {
        _param.beginParamHover();
        setDirtyWhole();        
    }

    override void onMouseExit()
    {
        _lastMouseX = AUBURN_MOUSE_TOO_FAR;
        _lastMouseY = AUBURN_MOUSE_TOO_FAR;
        setDirtyWhole();
        _param.endParamHover();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        setDirtyWhole();
    }

    override void onAnimate(double dt, double time)
    {
        float target = (isMouseOver() || isDragged()) ? 1 : 0;
        float newAnimation = lerp(_animation, target, 1.0 - exp(-dt * animationSpeed));
        if (abs(newAnimation - _animation) > 0.001f)
        {
            _animation = newAnimation;
            setDirtyWhole();
        }
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;

        float displacement = vertical ? (cast(float)(dy) / _position.height) : (cast(float)(-dx) / _position.width);
        float coord = vertical ? y : ( _position.width - x);

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        double oldParamValue = _param.getNormalized();
        double newParamValue = oldParamValue - displacement * modifier * sensivity;
        if (mstate.altPressed)
            newParamValue = _param.getNormalizedDefault();

        if (coord > _mousePosOnLast0Cross)
            return;
        if (coord < _mousePosOnLast1Cross)
            return;

        if (newParamValue <= 0 && oldParamValue > 0)
            _mousePosOnLast0Cross = coord;

        if (newParamValue >= 1 && oldParamValue < 1)
            _mousePosOnLast1Cross = coord;

        if (newParamValue < 0)
            newParamValue = 0;
        if (newParamValue > 1)
            newParamValue = 1;

        if (newParamValue > 0)
            _mousePosOnLast0Cross = float.infinity;

        if (newParamValue < 1)
            _mousePosOnLast1Cross = -float.infinity;

        if (newParamValue != oldParamValue)
        {
            if (auto p = cast(FloatParameter)_param)
            {
                p.setFromGUINormalized(newParamValue);
            }
            else
                assert(false); // only float parameters supported
        }
    }

    final void enableSectionIfDisabled()
    {
        // Enable the section rather than move it silently
        bool enabled = _enableParam ? _enableParam.value() : true;
        if (!enabled)
        {
            _enableParam.beginParamEdit();
            _enableParam.setFromGUI(true);
            _enableParam.endParamEdit();
        }
    }

    final bool mouseTooCloseFromHandle(vec2f handlePoint, vec2f potentialHandlePoint)
    {
        float W = position.width;
        float H = position.height;
        float widthDimension = vertical ? W : H;
        float rectRatio;
        if (type == Type.rectangle)
            rectRatio = handleRectRatio;
        else
            rectRatio = 1.0f;
        float radiusPx = widthDimension * handleRadiusHighlighted * rectRatio;
        float potentialDistPx = widthDimension * marginPotentialHandle;
        return (potentialHandlePoint.squaredDistanceTo(handlePoint) < potentialDistPx * potentialDistPx);
    }

protected:
    FloatParameter _param;
    BoolParameter _enableParam;

private:
    Canvas canvas;   

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    int _lastMouseX = AUBURN_MOUSE_TOO_FAR;
    int _lastMouseY = AUBURN_MOUSE_TOO_FAR;
    float _animation = 0.0f;

    final float mainAxisMargin()
    {
        float W = position.width;
        float H = position.height;
        float rectRatio;
        if (type == Type.rectangle)
            rectRatio = handleRectRatio;
        else
            rectRatio = 1.0f;

        float widthDimension = vertical ? W : H;
        return widthDimension * handleRadiusHighlighted * rectRatio;
    }

    final vec2f trailStartPoint()
    {
        float W = position.width;
        float H = position.height;
        float M = mainAxisMargin(); // main axis margin
        vec2f A = vertical ? vec2f(W*0.5f, M)   : vec2f(M,     H*0.5f); // start point of the trail line
        vec2f B = vertical ? vec2f(W*0.5f, H-M) : vec2f(W-M, H*0.5f);   // stop point of the trail line
        vec2f Start = vertical ? B : A;
        return Start;
    }

    final vec2f trailStopPoint()
    {
        float W = position.width;
        float H = position.height;        
        float M = mainAxisMargin(); // main axis margin
        vec2f A = vertical ? vec2f(W*0.5f, M)   : vec2f(M,     H*0.5f); // start point of the trail line
        vec2f B = vertical ? vec2f(W*0.5f, H-M) : vec2f(W-M, H*0.5f); // stop point of the trail line
        vec2f Start = vertical ? A : B;
        return Start;
    }

    /// Where the trail base is.
    final vec2f trailBasePoint(vec2f trailStart, vec2f trailStop)
    {
        return trailStart + trailBase * (trailStop - trailStart);
    }

    /// Where the handle is.
    final vec2f handlePoint(vec2f trailStart, vec2f trailStop)
    {
        return trailStart + _param.getNormalized() * (trailStop - trailStart);
    }

    /// Where the potential handle is.
    final vec2f potentialHandlePoint(vec2f trailStart, vec2f trailStop, float mousex, float mouseY)
    {
        float paramIfWeClick = convertPointToNormalizedValue(mousex, mouseY);
        return trailStart + paramIfWeClick * (trailStop - trailStart);
    }

    final void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }

    // Convert local coord to parameter value.
    final float convertPointToNormalizedValue(float x, float y)
    {
        float W = position.width;
        float H = position.height;
        float M = mainAxisMargin(); // main axis margin

        float R;
        if (vertical)
            R = linmap!float(y, M, H - M, 1.0f, 0.0f);
        else
            R = linmap!float(x, M, W - M, 0.0f, 1.0f);
        if (R < 0) R = 0;
        if (R > 1) R = 1;
        return R;
    }

    final bool sliderCouldStartDragOnClick()
    {
        return isMouseOver && !isDragged;
    }
}