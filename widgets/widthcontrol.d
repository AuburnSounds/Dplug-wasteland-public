module widthcontrol;

import gui;
import core.atomic;
import dplug.core;
import dplug.gui;
import dplug.canvas;
import dplug.client;

/// A stereo width control, 
/// takes one parameter that goes 0 to 200%
/// This is a relatively simple widget to show how to use dplug:canvas in custom widgets
final class UIWidthControl : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    @ScriptProperty RGBA colorOn = RGBA(90, 90, 90, 200);
    @ScriptProperty RGBA colorOff = RGBA(65, 65, 65, 200);
    @ScriptProperty RGBA colorDragged = RGBA(255, 255, 0, 255);
    @ScriptProperty RGBA colorHovered = RGBA(255, 255, 255, 255);
    @ScriptProperty RGBA colorDisabled = RGBA(65, 65, 65, 200);
    @ScriptProperty float sensivity = 0.06f;

    // This expects a FloatParameter `param` that speaks in percentage % (eg: 0 to 200%).
    this(UIContext context, Parameter param, Parameter enableParam)
    {
        super(context, flagRaw);
        _param = cast(FloatParameter) param;
        _param.addListener(this);

        _enableParam = cast(BoolParameter) enableParam;
        _enableParam.addListener(this);

        clearCrosspoints();
    }

    ~this()
    {
        _enableParam.removeListener(this);
        _param.removeListener(this);
    }
  
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        bool enabled = _enableParam.value();

        float W = position.width;
        float H = position.height;

        float center = W * 0.5f;
        float extent = W * 0.49f * 0.8f; // more esthetic to leave a bit of secondary color
        float baseExtent = W * 0.03f; // so that a line does appear for 0% width

        float width = _param.value() * 0.01; // can be 0 to 1, 0 to 2, 0 to 4, etc.
        float widthNormCapped = (width >= 2) ? 1.0f : width * 0.5f;

        // Points:
        //
        //   L--A-----------B--R
        //    \               /
        //     \             /
        //      \  Ea E Eb  /
        //       \         /
        //        \       /
        //         \     /
        //        Ca\_C_/Cb
        //
        //
       

        vec2f L = vec2f(0, 0);
        vec2f R = vec2f(W, 0);
        vec2f C = vec2f(center, H);
        vec2f Ca = vec2f(center - baseExtent, H);
        vec2f Cb = vec2f(center + baseExtent, H);
        vec2f A = vec2f(center - extent*widthNormCapped - baseExtent, 0);
        vec2f B = vec2f(center + extent*widthNormCapped + baseExtent, 0);

        vec2f E = C;
        vec2f Ea = Ca;
        vec2f Eb = Cb;

        // Note: E is separate from C if width > 200%, and we need to represent larger width.
        // To avoid taking to much horizontal space, move E to the top of the widget.
        if (width > 2.0)
        {
            E.y = H / (width / 2.0);
            Ea.y = E.y;
            Eb.y = E.y;
        }

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);
            canvas.initialize(cRaw);
            canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);

            // Fill with off color
            canvas.fillStyle = colorOff;
            canvas.beginPath();
            canvas.moveTo(L);
            canvas.lineTo(R);
            canvas.lineTo(Cb);
            canvas.lineTo(Ca);
            canvas.closePath();
            canvas.fill();

            // Fill with on color
            RGBA color = colorOn;
            if (!enabled) color = colorDisabled;
            if (isMouseOver) color = colorHovered;
            if (isDragged) color = colorDragged;

            canvas.fillStyle = color;
            canvas.beginPath();
            canvas.moveTo(A);
            canvas.lineTo(B);
            canvas.lineTo(Eb);
            canvas.lineTo(Ea);
            canvas.closePath();
            canvas.fill();
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
        // Enable EQ if not enabled already.
        if (!_enableParam.value())
        {
            _enableParam.beginParamEdit();
            _enableParam.setFromGUI(true);
            _enableParam.endParamEdit();
        }

        // double-click => set to default
        if (isDoubleClick || mstate.altPressed)
        {
            _param.beginParamEdit();
            _param.setFromGUI(_param.defaultValue());
            _param.endParamEdit();
        }
        return Click.startDrag;
    }

    override void onBeginDrag()
    {
        _param.beginParamEdit();
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
        _param.endParamHover();
        setDirtyWhole();
    }

    // Called when mouse drag this Element.
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        // FUTURE: replace by actual trail height instead of total height
        float displacementInHeight = cast(float)(dy) / _position.height;

        float modifier = 1.0f;
        if (mstate.shiftPressed || mstate.ctrlPressed)
            modifier *= 0.1f;

        double oldParamValue = _param.getNormalized();
        double newParamValue = oldParamValue - displacementInHeight * modifier * sensivity;
        if (mstate.altPressed)
            newParamValue = _param.getNormalizedDefault();

        if (y > _mousePosOnLast0Cross)
            return;
        if (y < _mousePosOnLast1Cross)
            return;

        if (newParamValue <= 0 && oldParamValue > 0)
            _mousePosOnLast0Cross = y;

        if (newParamValue >= 1 && oldParamValue < 1)
            _mousePosOnLast1Cross = y;

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

private:
    Canvas canvas;
    FloatParameter _param;
    BoolParameter _enableParam;

    float _mousePosOnLast0Cross;
    float _mousePosOnLast1Cross;

    void clearCrosspoints()
    {
        _mousePosOnLast0Cross = float.infinity;
        _mousePosOnLast1Cross = -float.infinity;
    }
}