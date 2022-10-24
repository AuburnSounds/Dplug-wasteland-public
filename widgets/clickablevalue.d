/**
Click on a circle => a FloatParameter get set to a predefined value.

Copyright: Copyright Guillaume Piolat 2015-2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.clickablevalue;

import dplug.gui.element;
import dplug.client.params;

/// Useful for big knobs with some significant values you want to highlight.
/// Click on a circle => a FloatParameter get set to a predefined value.
/// Note: _position is for the clickable area, the circle itself can be smaller.
class UIClickableValue : UIElement
{
public:
nothrow:
@nogc:

    enum Style
    {
        dot,
        square
    }
    RGBA diffuseOff = RGBA(80, 80, 80, 0);
    RGBA diffuseOver = RGBA(80, 255, 80, 100);
    float pointRadius = 3.0f;
    float alpha = 1.0f;
    bool visibleOnlyWhenMouseOver = false;
    Style style = Style.dot;

    /// Params:
    ///     mappedValue the parameter value to set.
    this(UIContext context, FloatParameter param, float mappedValue)
    {
        super(context, flagPBR);
        _param = param;
        _value = mappedValue;
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        _param.beginParamEdit();
        _param.setFromGUI(_value);
        _param.endParamEdit();
        return true;
    }

    override void onMouseEnter()
    {
        setDirtyWhole();
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        int width = _position.width;
        int height = _position.height;

        float centerX = (width-1) * 0.5f;
        float centerY = (height-1) * 0.5f;

        bool mouseOver = isMouseOver();
        if (visibleOnlyWhenMouseOver && !mouseOver)
            return;

        RGBA diffuse = isMouseOver() ? diffuseOver : diffuseOff;        

        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA cDiffuse = diffuseMap.cropImageRef(dirtyRect);
            float pointPosX = centerX - dirtyRect.min.x;
            float pointPosY = centerY - dirtyRect.min.y;
            final switch(style) with (Style)
            {
                case dot: cDiffuse.aaSoftDisc(pointPosX, pointPosY, pointRadius-1, pointRadius, diffuse, alpha); break;
                case square: cDiffuse.aaFillRectFloat(pointPosX - pointRadius, pointPosY - pointRadius, 
                                                 pointPosX + pointRadius, pointPosY + pointRadius, diffuse, alpha); break;
            }
        }
    }

private:
    FloatParameter _param;
    float _value;
}
