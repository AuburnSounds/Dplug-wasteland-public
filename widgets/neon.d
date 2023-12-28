module neon;

import gui;
import core.atomic;
import dplug.core;
import dplug.gui;
import dplug.canvas;
import dplug.client;

// Just a rectangular shiny rectangle, that can be enabled or disabled but is not a switch.
final class UINeon : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    @ScriptProperty
    {
        RGBA diffuseOn = RGBA(255, 0, 255, 128);
        RGBA diffuseOff = RGBA(255, 0, 255, 0);
        RGBA material = RGBA(defaultRoughness, defaultMetalnessDielectric, defaultSpecular, 255);
    }
    
    this(UIContext context, Parameter enable)
    {
        super(context, flagPBR);
        if (enable !is null)
        {
            _enable = cast(BoolParameter) enable;
            _enable.addListener(this);
        }
    }

    ~this()
    {
        if (_enable !is null)
            _enable.removeListener(this);
    }
  
    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        bool enabled = (_enable is null) ? true : _enable.value();
        RGBA diffuseColor = enabled ? diffuseOn : diffuseOff;
        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA cDiffuse = diffuseMap.cropImageRef(dirtyRect);
            cDiffuse.fillAll(diffuseColor);
            materialMap.cropImageRef(dirtyRect).fillAll(material);
        }
    }

    override void onParameterChanged(Parameter sender)
    {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender)
    {
    }

    override void onEndParameterEdit(Parameter sender)
    {
    }
    override void onBeginParameterHover(Parameter sender){}
    override void onEndParameterHover(Parameter sender){}

    debug
    {
        // Note sure why here, probably for interactive placement
        override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
        {
            return Click.startDrag;
        }
    }

private:
    BoolParameter _enable;
}