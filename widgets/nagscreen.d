/**
Tells the user to buy.

Copyright: Copyright Guillaume Piolat 2015-2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.nagscreen;

import dplug.core;
import dplug.gui;

// Note: should replace by UINagScreen when possible
class NagScreen : UIBufferedElementPBR
{
public:
nothrow:
@nogc:

    RGBA textDiffuse = RGBA(255, 255, 255, 10);
    RGBA panelDiffuse = RGBA(0, 0, 0, 0);
    ubyte opacityDragged = 128;
    ubyte opacity = 64;
    float fontSize = 16.0f; // in pixels

    this(UIContext context, Font font, string message)
    {
        super(context, flagPBR);
        _font = font;
        _message = message;
    }

    ~this()
    {
    }

    override void onDrawBufferedPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap,
                                 ImageRef!L8 diffuseOpacity, ImageRef!L8 depthOpacity, ImageRef!L8 materialOpacity)
    {

        diffuseMap.fillAll(panelDiffuse);

        if (isDragged())
        {
            vec2i textPos = center();
            diffuseMap.fillText(_font, _message, fontSize, 0, textDiffuse, textPos.x, textPos.y);
        }

        ubyte opacity = isDragged() ? opacityDragged : opacity;

        diffuseOpacity.fillAll(L8(opacity));
        depthOpacity.fillAll(L8(0));
        materialOpacity.fillAll(L8(0));
    }

    // where the text will be drawn
    vec2i center()
    {
        return vec2i( _position.width() / 2, _position.height() / 2 );
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) 
    {
        // absorb all clicks to avoid dragging LFO stuff
        return true;
    }   

    override void onBeginDrag() 
    {
        setDirtyWhole();
    }

    override void onStopDrag() 
    {
        setDirtyWhole();
    }
 
private:
    Font _font;
    string _message;
}



class UINagScreen : UIBufferedElementRaw
{
public:
nothrow:
@nogc:

    @ScriptProperty
    {
        RGBA textColor = RGBA(210, 210, 210, 255);
        RGBA panelColor = RGBA(13, 10, 7, 255);
        ubyte opacityClicked = 200;
        ubyte opacity = 80;
        float fontSize = 16.0f; // in pixels
    }
    vec2f textOffset = vec2f(0, 0);

    this(UIContext context, Font font, string message)
    {
        super(context, flagRaw);
        _font = font;
        _message = message;
    }

    ~this()
    {
    }

    override void onDrawBufferedRaw(ImageRef!RGBA rawMap,ImageRef!L8 opacityMap) 
    {
        rawMap.fillAll(panelColor);

        if (isDragged())
        {
            vec2i textPos = center();
            rawMap.fillText(_font, _message, fontSize, 0, textColor, textPos.x + textOffset.x, textPos.y + textOffset.y);
        }

        ubyte opacityUsed = isDragged() ? opacityClicked : opacity;
        opacityMap.fillAll(L8(opacityUsed));
    }

    // where the text will be drawn
    vec2i center()
    {
        return vec2i( _position.width() / 2, _position.height() / 2 );
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) 
    {
        // absorb all clicks to avoid dragging stuff below
        return true;
    }   

    override void onBeginDrag() 
    {
        setDirtyWhole();
    }

    override void onStopDrag() 
    {
        setDirtyWhole();
    }

private:
    Font _font;
    string _message;
}
