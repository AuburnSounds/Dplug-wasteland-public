/**
Adv. Dynamic text label glue to a parameter UI

Show decimals or not
Easy Resizeable
Fonts
Color
Clickable
...

Note: this is a very bad widget to copy. Obsolete, but works.
In particular, the setters should be script properties.

Copyright: Copyright Auburn Sounds 2015-2024.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat


Modified by SMAOLAB in Oct 2024.
*/

/*  --- TUTORIAL BEFORE THE CODE -----

1- In gui.d, , at the top, declare :

import adv_paramlabel;
...

2- In gui.d, , at the end, in the private section, declare :

Private: 
    UIAdvParamLabel inputLabel;
    ...

3- then, in gui.d, write the following code : 
...
this(BlablablablaClient client)
{
  _client = client;
...

    // input label
    inputLabel = mallocNew!UIAdvParamLabel(context(), cast(FloatParameter) _client.param(param_Input));
    addChild(inputLabel);
    inputLabel.font(_font);
    inputLabel.textSize(36);
    inputLabel.showDecimals(true);
    inputLabel.color(RGBA(10, 10, 10, 255));
...
}

4- then ,in gui.d, write the following code : 

override void reflow()
{
  super.reflow();

        int W = position.width;
        int H = position.height;

        float _textresizefactor, _textspacingresizefactor; // important, declare this

        float S = W / cast(float)(context.getDefaultUIWidth()); // important, declare this
        _textresizefactor= 32*S;                                // important, declare this
        _textspacingresizefactor = 2.0f *S;                     // important, declare this
        // Note : you can change the resize factor 
        // _textresizefactor= 32*S; BIG
        // _textresizefactor= 16*S; MEDIUM
        // _textresizefactor= 12*S; SMALL
        // etc. 
        
        ...

        inputLabel.position = rectangle(970, 100, 110, 110).scaleByFactor(S);
        inputLabel.textSize= _textresizefactor;                 // important, declare this
        inputLabel.letterSpacing = _textspacingresizefactor;    // important, declare this
  ...
}

5- that's all :-)
*/
module adv_paramlabel;

import core.stdc.string;
import core.atomic;

import std.math;
import std.conv;
import std.algorithm;

import dplug.core;
import dplug.gui.element;
import dplug.client.params;

/// Simple area with text.
class UIAdvParamLabel : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    bool _showDecimals = false;  // if set to false -> can't display correctly my default value :()

    /// Sets to true if this is clickable
    @ScriptProperty bool clickable = false;
    string targetURL = "http://example.com";

    this(UIContext context, Parameter param)
    {
        super(context, flagRaw);//flagPBR); 
        _param = param;
        _param.addListener(this);
        setDirtyWhole();
    }

    ~this()
    {
        _param.removeListener(this);
    }

    // Get the UI parameter value
    const(char)[] paramString() nothrow @nogc
    {
        if(!_showDecimals)
        {
            _param.toDisplayN(_pParamStringBuffer.ptr, 128);
            size_t len = strlen(_pParamStringBuffer.ptr);
            string label = _param.label();
            assert(label.length < 127);
            _pParamStringBuffer[len - 3] = ' ';
            size_t totalLength = len + 1 + label.length;
            _pParamStringBuffer[len - 2..totalLength - 3] = label[];
            return _pParamStringBuffer[0..totalLength - 3];
        }
        else
        {
            _param.toDisplayN(_pParamStringBuffer.ptr, 128);
            size_t len = strlen(_pParamStringBuffer.ptr);
            string label = _param.label();
            assert(label.length < 127);
            _pParamStringBuffer[len] = ' ';
            size_t totalLength = len + 1 + label.length;
            _pParamStringBuffer[len+1..totalLength] = label[];
            return _pParamStringBuffer[0..totalLength];
        }
    }

    /// showDecimals 
    bool showDecimals(bool showDecimals_)
    {
        _lastParamString = paramString();
        setDirtyWhole();
        return _showDecimals = showDecimals_;
    }

    void settextresizefactor(int S)
    {
        _textSize= 16*S;
        _letterSpacing = 2.0f *S;
    }

    /// text color
    RGBA color(RGBA color_)
    {
        setDirtyWhole();
        return _color = color_;
    }


    /// Returns: Font used.
    Font font()
    {
        return _font;
    }

    /// Sets text size.
    Font font(Font font_)
    {
        _lastParamString = paramString(); // usefull ?
        setDirtyWhole();
        return _font = font_;
    }

    /// Returns: Displayed text.
    string text()
    {
        return _text;
    }

    /// Sets displayed text.
    string text(string text_)
    {
        _lastParamString = paramString();
        setDirtyWhole();
        return _text = text_;
    }

    /// Returns: Size of displayed text.
    float textSize()
    {
        return _textSize;
    }

    /// Sets size of displayed text.
    float textSize(float textSize_)
    {
        _lastParamString = paramString();
        setDirtyWhole();
        return _textSize = textSize_;
    }

    float letterSpacing()
    {
        return _letterSpacing;
    }

    float letterSpacing(float letterSpacing_)
    {
        _lastParamString = paramString();
        setDirtyWhole();
        return _letterSpacing = letterSpacing_;
    }

    /// Returns: Diffuse color of displayed text.
    RGBA textColor()
    {
        return _textColor;
    }

    /// Sets diffuse color of displayed text.
    RGBA textColor(RGBA textColor_)
    {
        setDirtyWhole();
        return _textColor = textColor_;
    }


    // Warning: this routine assume parameter hints are top-level and doesn't respect dirtyRects
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) nothrow @nogc
    {
        float textPosx = position.width * 0.5f;
        float textPosy = position.height * 0.5f;

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = rawMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(textPosx, textPosy) - dirtyRect.min;
            croppedDiffuse.fillText(_font, _lastParamString, _textSize, _letterSpacing, _color, positionInDirty.x, positionInDirty.y);
        }
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float textPosx = position.width * 0.5f;
        float textPosy = position.height * 0.5f;
        // only draw text which is in dirty areas

        RGBA diffuse = _textColor;
        int emissive = _textColor.a;
        bool underline = false;

        if (clickable && isMouseOver)
        {
            emissive += 40;
            underline = true;
        }
        else if (clickable && isDragged)
        {
            emissive += 80;
            underline = true;
        }
        if (emissive > 255)
            emissive = 255;
        diffuse.a = cast(ubyte)(emissive);

        // MAYDO: implement underline?

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(textPosx, textPosy) - dirtyRect.min;
            croppedDiffuse.fillText(_font, _lastParamString, _textSize, _letterSpacing, diffuse, positionInDirty.x, positionInDirty.y);
        }
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        _lastParamString = paramString();
        setDirtyWhole();
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        _lastParamString = paramString();
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }

    override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }

protected:

    /// The font used for text.
    Font _font;

    /// Text to draw
    string _text;

    /// Size of displayed text in pixels.
    float _textSize = 16.0f;

    /// Additional space between letters, in pixels.
    float _letterSpacing = 0.0f;

    /// Diffuse color of displayed text.
    RGBA _textColor = RGBA(0, 0, 0, 0);

    Parameter _param;

    const(char)[] _lastParamString;
    const(char)[] _tempParamString;

    RGBA _color;

    char[256] _pParamStringBuffer;
}
