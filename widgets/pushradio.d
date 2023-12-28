/**
Radio button.

Copyright: Copyright Guillaume Piolat 2015-2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.pushradio;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.client.params;


/// Rectangle buttons that only write to Depth and Emissive
class UIPushRadio : UIElement, IParameterListener
{
public:
nothrow:
@nogc:
    /// Quantity of emitted light if under mouse
    ubyte emissiveMouseOver = 20;
    
    /// Quantity of emitted light if currently selected
    ubyte emissiveSelected = 60;

    /// Displacement in height when one item is selected
    int depthOffset = -40000;

    /// Animation speed constant.
    double animationTimeConstant = 30.0f;

    /// Construct a `UIPushRadio`.
    /// Params:
    ///     param Can be an integer parameter or bool parameter.
    ///     paramEnabled Can be used to enable this widget selectively.
    this(UIContext context, 
         Parameter param, 
         BoolParameter paramEnabled) // can be null
    {
        super(context, flagPBR | flagAnimated);

        _param = param;
        _paramEnabled = paramEnabled;

        if (auto p = cast(IntegerParameter)param)
            _numValues = p.numValues();
        else if (auto p = cast(BoolParameter)param)
            _numValues = 2;
        else
            assert(false);
        
        _param.addListener(this);
        if (_paramEnabled !is null)
            _paramEnabled.addListener(this);

        _lastPointedValue = -1;        
    }

    /// Construct a `UIPushRadio`.
    /// Params:
    ///     param Can be an integer parameter or bool parameter.
    ///     paramEnabled Can be used to enable this widget selectively.
    /// Note: this call `setButtonPositions` addionally. This is for non-resizeable legacy UIs.
    this(UIContext context, 
         Parameter param, 
         BoolParameter paramEnabled,     // can be null
         const(box2i)[] buttonPositions) // can be a temporary
    {
        this(context, param, paramEnabled);
        setButtonsPositions(buttonPositions);
    }

    /// Sets button positions. Call this in `reflow` after recomputing where the push buttons are.
    void setButtonsPositions(const(box2i)[] buttonPositions)
    {
        if (_buttonPositions == buttonPositions)
            return;

        // Should be given as much rectangles as possible parameter values
        assert(_numValues == buttonPositions.length);

        if (_buttonPositions is null)
        {
            _buttonPositions = mallocSlice!box2i(buttonPositions.length);
            _buttonPositionsClamped = mallocSlice!box2i(buttonPositions.length);
        }
        
        // copy internally
        _buttonPositions[] = buttonPositions[];
        
        if (_pushedAnimations is null)
        {
            _pushedAnimations.reallocBuffer(_numValues);
            _pushedAnimations[] = 0.0f;
        }
        updateButtonsPositionClamped();
        setDirtyWhole();
    }

    ~this()
    {
        _param.removeListener(this);
        if (_paramEnabled !is null)
            _paramEnabled.removeListener(this);
        if (_buttonPositions !is null) 
        {
            freeSlice(_buttonPositions);
            freeSlice(_buttonPositionsClamped);
        }
        _pushedAnimations.reallocBuffer(0);
    }

    void updateMouse(int x, int y)
    {
        int newPointedValue = convertXYToItem(x, y);
        if (newPointedValue != _lastPointedValue)
        {
            setDirtyButton(newPointedValue);
            setDirtyButton(_lastPointedValue);
            _lastPointedValue = newPointedValue;
        }
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        updateMouse(x, y);
    }

    override void onMouseExit()
    {
        setDirtyWhole();
        _lastPointedValue = -1;
    }

    /// Returns: Index of clicked value, or -1.
    final int convertXYToItem(int x, int y)
    {
        if (_buttonPositions is null)
            return -1;
        int ix = x;
        int iy = y;
        for (int i = 0; i < _numValues; ++i)
        {
            box2i bp = _buttonPositions[i];
            if (bp.contains(vec2i(ix, iy)))
            {
                return i;
            }
        }
        return -1;
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        int itemClicked = convertXYToItem(x, y);
        int current = currentValue();
        if (_numValues == 2 && itemClicked == current)
        {
            assert(current >= 0 && current <= 1);
            itemClicked = 1 - current;
        }

        if (itemClicked == -1)
            return false;

        _param.beginParamEdit();

        if (auto p = cast(IntegerParameter)_param)
        {
            int value = p.minValue() + itemClicked;
            if (mstate.altPressed)
                p.setFromGUI(p.defaultValue);
            else
                p.setFromGUI(value);
        }
        else if (auto p = cast(BoolParameter)_param)
        {
            bool value = itemClicked != 0; 
            if (mstate.altPressed)
                p.setFromGUI(p.defaultValue);
            else
                p.setFromGUI(value);
        }
        else
            assert(false);

        _param.endParamEdit();
        return true;
    }

    int currentValue()
    {
        int res = -1;
        if (auto p = cast(IntegerParameter)_param)
        {
            res = p.valueAtomic() - p.minValue();
        }
        else if (auto p = cast(BoolParameter)_param)
        {
            res = p.valueAtomic() ? 1 : 0;
        }
        else
            assert(false);
        return res;
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        int width = _position.width;
        int height = _position.height;

        bool mouseOver = isMouseOver();
        int itemPointed = _lastPointedValue; // can be -1

        int current = currentValue();

        // Only display light if enabled
        bool enabled = _paramEnabled ? _paramEnabled.valueAtomic() : true;
        

        foreach(dirtyRect; dirtyRects)
        {
            auto cDiffuse = diffuseMap.cropImageRef(dirtyRect);
            auto cDepth = depthMap.cropImageRef(dirtyRect);

            for (int i = 0; i < _numValues; ++i)
            {
                // Note: this will crash if you haven't called `setButtonsPositions()` in `reflow()` or at creation time.
                assert(_buttonPositions !is null);
                assert(_pushedAnimations !is null);

                box2i rect = _buttonPositions[i]; 

                // This option cannot be accessed through this PushRadio
                if (rect.empty) 
                    continue;
                int rx = rect.min.x - dirtyRect.min.x;
                int ry = rect.min.y - dirtyRect.min.y;

                box2i itemRect = box2i(rx, ry, rx + rect.width, ry + rect.height);
                
                bool thisItemMouseOver = mouseOver && ( itemPointed == i );
                bool thisItemSelected = (current == i);

                // because clicking on them would do nothing
                if (thisItemSelected)
                    thisItemMouseOver = false;

                float pushAnimation = _pushedAnimations[i];
                int depthOffsetAnimated = cast(int)(depthOffset * pushAnimation);

                if (depthOffsetAnimated != 0)
                {
                    cDepth.addRectAlpha(itemRect.min.x, itemRect.min.y, itemRect.max.x, itemRect.max.y, depthOffsetAnimated);
                }

                if (thisItemSelected)
                {
                    if (enabled)
                        cDiffuse.fillRectAlpha(itemRect.min.x, itemRect.min.y, itemRect.max.x, itemRect.max.y, emissiveSelected);
                }
                else if (thisItemMouseOver)
                {
                    if (enabled)
                        cDiffuse.fillRectAlpha(itemRect.min.x, itemRect.min.y, itemRect.max.x, itemRect.max.y, emissiveMouseOver);
                }
            }
        }
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

    override void reflow()
    {
        updateButtonsPositionClamped();
    }

    void setDirtyButton(int which)
    {
        if (which == -1)
            return;
        box2i rect = _buttonPositionsClamped[which];
        if (!rect.empty) 
        {
            // If you fail inside this setDirty, the button position was badly set
            // it should be a super-set of rectangles, and push rectangles are expressed
            // in widgets coordinates.
            setDirty(rect);
        }
    }

    void updateButtonsPositionClamped()
    {
        if (_buttonPositions is null)
            return;

        _buttonPositionsClamped[] = _buttonPositions[];
        if (position.empty)
            return;

        int W = position.width;
        int H = position.height;
        box2i validPos = rectangle(0, 0, W, H);
        
        foreach(ref rect; _buttonPositionsClamped[])
        {
            // Note: when resizing such a widget, it can happen that `scaleByFactor` leads to a size smaller than the 
            // buttons positions, since the round(scale * x) will happen in different referential, thus rounding in different directions.
            // avoid that by clamping buttons positions to a valid one.
            if (rect.max.x > W) rect.max.x = W;
            if (rect.max.y > H) rect.max.y = H;
            if (rect.min.x > W) rect.min.x = W;
            if (rect.min.y > H) rect.min.y = H;
            assert(validPos.contains(rect));
        }
    }
    
    override void onAnimate(double dt, double time) nothrow @nogc
    {
        if (_pushedAnimations is null)
            return;
        int current = currentValue();

        double factor = 1.0 - exp(-dt * animationTimeConstant);

        for (int choice = 0; choice < _numValues; ++choice)
        {
            float target = (choice == current) ? 1 : 0;
            float newAnimation = lerp(_pushedAnimations[choice], target, factor);

            if (abs(newAnimation - _pushedAnimations[choice]) > 0.001f)
            {
                _pushedAnimations[choice] = newAnimation;
                setDirtyButton(choice);
            }
        }
    }

private:
    Parameter _param;
    BoolParameter _paramEnabled;

    int _numValues;

    int _lastPointedValue;

    box2i[] _buttonPositions;
    box2i[] _buttonPositionsClamped; // same but clamped to a valid position

    float[] _pushedAnimations;
}

void addRectAlpha(bool CHECKED=true, V)(auto ref V v, int x1, int y1, int x2, int y2, int offset) nothrow @nogc
if (isWritableView!V && is(L16 : ViewColor!V))
{
    sort2(x1, x2);
    sort2(y1, y2);
    static if (CHECKED)
    {
        if (x1 >= v.w || y1 >= v.h || x2 <= 0 || y2 <= 0 || x1==x2 || y1==y2) return;
        if (x1 <    0) x1 =   0;
        if (y1 <    0) y1 =   0;
        if (x2 >= v.w) x2 = v.w;
        if (y2 >= v.h) y2 = v.h;
    }

    foreach (y; y1..y2)
    {
        L16[] scan = v.scanline(y);
        foreach (x; x1..x2)
        {
            scan[x].l += offset;
        }
    }
}

void fillRectAlpha(bool CHECKED=true, V)(auto ref V v, int x1, int y1, int x2, int y2, ubyte alpha) nothrow @nogc
if (isWritableView!V && is(RGBA : ViewColor!V))
{
    sort2(x1, x2);
    sort2(y1, y2);
    static if (CHECKED)
    {
        if (x1 >= v.w || y1 >= v.h || x2 <= 0 || y2 <= 0 || x1==x2 || y1==y2) return;
        if (x1 <    0) x1 =   0;
        if (y1 <    0) y1 =   0;
        if (x2 >= v.w) x2 = v.w;
        if (y2 >= v.h) y2 = v.h;
    }

    foreach (y; y1..y2)
    {
        RGBA[] scan = v.scanline(y);
        foreach (x; x1..x2)
        {
            scan[x].a = alpha;
        }
    }
}