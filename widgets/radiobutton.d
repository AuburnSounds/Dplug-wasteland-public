/**
Radio button.

Copyright: Auburn Sounds 2015-2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.radiobutton;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.client.params;

deprecated("Use UIRadioButtonSet instead") alias AuburnRadioButtonSet = UIRadioButtonSet;

class UIRadioButtonSet : UIElement, IParameterListener
{
public:
nothrow:
@nogc:
    RGBA LEDDiffuse = RGBA(200, 230, 255, 0);
    float LEDRadius = 5.0f; // in pixels

    RGBA holeDiffuse = RGBA(120,135,148, 0);

    ushort depthOff = 30000;
    ushort depthOn = 18000;

    this(UIContext context, IntegerParameter param)
    {
        super(context, flagPBR | flagAnimated);

        _param = param;
        _param.addListener(this);

        _pushedAnimations = mallocSlice!float(_param.numValues());
        _pushedAnimations[] = 0.0f;
    }

    ~this()
    {
        _param.removeListener(this);
        _pushedAnimations.freeSlice();
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

    final int convertYToItem(float y)
    {
        int res = cast(int)(y / getHeightByItem());
        int N = _param.numValues();
        if (res < 0)
            res = 0;
        if (res > N)
            res = N;

        return res;
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        if (y >= getHeightByItem() * _param.numValues())
            return false; // out of bounds

        int itemClicked = _param.minValue() + convertYToItem(y);
        int max =  _param.maxValue();
        if (itemClicked > max)
            itemClicked = max;

        _param.beginParamEdit();
        _param.setFromGUI(itemClicked);
        _param.endParamEdit();
        return true;
}

    int getHeightByItem() pure const nothrow @nogc
    {
        return _position.height / _param.numValues();
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        int width = _position.width;
        int height = _position.height;

        int heightByItem = getHeightByItem();
        int numChoices = _param.numValues();

        bool mouseOver = isMouseOver();
        int itemPointed = _lastMouseY / heightByItem;
        int currentValue = _param.valueAtomic();

        foreach(dirtyRect; dirtyRects)
        {
            auto cDiffuse = diffuseMap.cropImageRef(dirtyRect);
            auto cMaterial = materialMap.cropImageRef(dirtyRect);
            auto cDepth = depthMap.cropImageRef(dirtyRect);

            for (int i = 0; i < numChoices; ++i)
            {
                int rx = 0 - dirtyRect.min.x;
                int ry = i * heightByItem - dirtyRect.min.y;

                box2i itemRect = box2i(rx, ry, rx + width, ry + heightByItem);


                bool thisItemMouseOver = mouseOver && ( itemPointed == i );
                bool thisItemSelected = (currentValue == i);

                // because clicking on them would do nothing
                if (thisItemSelected)
                    thisItemMouseOver = false;

                ubyte alpha = thisItemMouseOver ? 30 : 0;

                cDiffuse.fillRectAlpha(rx, ry, rx + width, ry + heightByItem, alpha);

                // LED
                {
                    float LEDmargin = heightByItem * 0.5f;
                    float LEDx = rx + LEDmargin * 0.85f;
                    float LEDy = ry + LEDmargin;

                    float smallRadius = LEDRadius * 0.7f;
                    float largerRadius = LEDRadius;

                    RGBA ledDiffuseAnimated = LEDDiffuse;
                    ledDiffuseAnimated.a = cast(ubyte)(20 + _pushedAnimations[i] * 225);

                    cDepth.aaSoftDisc(LEDx, LEDy, 0, largerRadius, L16(40000), 0.5f);
                    cDiffuse.aaSoftDisc(LEDx, LEDy, largerRadius-1, largerRadius, holeDiffuse);
                    cDiffuse.aaSoftDisc(LEDx, LEDy-1, smallRadius-1, smallRadius, ledDiffuseAnimated);
                    cMaterial.aaSoftDisc(LEDx, LEDy, largerRadius-1, largerRadius, RGBA(0, 40, 40, 255));
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

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        int currentValue = _param.valueAtomic();
        int numChoices = _param.numValues();

        bool wasAnimated = false;

        double animationTimeConstant = 15.0f;
        double factor = 1.0 - exp(-dt * animationTimeConstant);

        for (int choice = 0; choice < numChoices; ++choice)
        {
            float target = (choice == currentValue) ? 1 : 0;
            float newAnimation = lerp(_pushedAnimations[choice], target, factor);

            if (abs(newAnimation - _pushedAnimations[choice]) > 0.001f)
            {
                _pushedAnimations[choice] = newAnimation;
                wasAnimated = true;
            }
        }
        if (wasAnimated)
            setDirtyWhole();
    }

private:
    IntegerParameter _param;
    int _lastMouseY;

    float[] _pushedAnimations;
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