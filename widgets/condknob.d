/**
Radio button.

Copyright: Copyright Guillaume Piolat 2019-2022
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.condknob;

import core.atomic;
import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.pbrwidgets.knob;
import dplug.client.params;


/// Knob which have a "disabled" state depending on a condition
class UICondKnob : UIKnob
{
public:
nothrow:
@nogc:

    this(UIContext context, Parameter param)
    {
        super(context, param);
    }    

    @ScriptProperty bool legacy = true; // if true = just desaturate the colors if disabled, else use other properties
    @ScriptProperty bool enableSectionOnUse = false;

    // <Used when legacy == false>
    @ScriptProperty RGBA trailDisabled = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA LEDDiffuseDisabled = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA litTrailDiffuseDisabled = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA unlitTrailDiffuseDisabled = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA litTrailDiffuseAltDisabled = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA knobDiffuseDisabled = RGBA(128, 128, 128, 0);
    // </Used when legacy == false>
    
    void addCondition(Parameter masterParam, int enableValue)
    {
        addConditionParam(masterParam, enableValue);
        recomputeCondition();
    }

    ~this()
    {
        foreach(icond; 0..MAX_CONDITION)
        {
            if (_condParam[icond])
            {
                _condParam[icond].removeListener(this);
                _condParam[icond] = null;
            }
        }
    }

    void blockClicksUnlessEnabled()
    {
        _strictMovement = true;
    }

    override bool contains(int x, int y)
    {
        if (_strictMovement)
        {
            bool enabled = (1 == atomicLoad(lastCond));
            if (!enabled)
                return false;
        }
        return super.contains(x, y); // disabld knob cannot be dragged or mouseOver
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        foreach(icond; 0..MAX_CONDITION)
        {
            if (sender is _condParam[icond])
            {
                recomputeCondition();
                return;
            }
        }
        super.onParameterChanged(sender);
    }    

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        bool result = super.onMouseClick(x, y, button, isDoubleClick, mstate);

        if (result == true)
        {
            if (enableSectionOnUse)
            {
                enableAllConditions();
            }
        }
        return result;
    }

    override void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        bool enabled = (1 == atomicLoad(lastCond));
        if (enabled)
            return super.drawKnob(diffuseMap, depthMap, materialMap, dirtyRects);
        else
        {
            auto savedknobDiffuse =        knobDiffuse;

            if (legacy)
            {
                static RGBA darken(RGBA source) nothrow @nogc
                {
                    return RGBA(cast(ubyte)(source.r * 0.9f), 
                                cast(ubyte)(source.g * 0.9f), 
                                cast(ubyte)(source.b * 0.9f), 
                                source.a);
                }
                knobDiffuse = darken(knobDiffuse);
            }
            else
                knobDiffuse = knobDiffuseDisabled;

            super.drawKnob(diffuseMap, depthMap, materialMap, dirtyRects);
            knobDiffuse        = savedknobDiffuse;
        }

    }

    override void drawTrail(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        bool enabled = (1 == atomicLoad(lastCond));
        if (enabled)
            return super.drawTrail(diffuseMap, depthMap, materialMap, dirtyRects);
        else
        {
            auto savedLEDDiffuseLit      = LEDDiffuseLit;
            auto savedLEDDiffuseUnlit    = LEDDiffuseUnlit;
            auto savedLEDMaterial        = LEDMaterial;
            auto savedlitTrailDiffuse    = litTrailDiffuse;
            auto savedunlitTrailDiffuse  = unlitTrailDiffuse;
            auto savedlitTrailDiffuseAlt = litTrailDiffuseAlt;

            static RGBA desaturate(RGBA source) nothrow @nogc
            {
                ubyte grey = cast(ubyte)((source.r + source.g + source.b + 1)/4);
                return RGBA(grey,grey,grey, source.a);
            }

            if (legacy)
            {
                LEDDiffuseLit = desaturate(LEDDiffuseLit);
                LEDDiffuseUnlit = desaturate(LEDDiffuseUnlit);
                LEDMaterial = desaturate(LEDMaterial);
                litTrailDiffuse = desaturate(litTrailDiffuse);
                unlitTrailDiffuse = desaturate(unlitTrailDiffuse);
                litTrailDiffuseAlt = desaturate(litTrailDiffuseAlt);
            }
            else
            {
                LEDDiffuseLit = LEDDiffuseDisabled;
                LEDDiffuseUnlit = LEDDiffuseDisabled;
                litTrailDiffuse = litTrailDiffuseDisabled;
                unlitTrailDiffuse = unlitTrailDiffuseDisabled;
                litTrailDiffuseAlt = litTrailDiffuseAltDisabled;
            }

            super.drawTrail(diffuseMap, depthMap, materialMap, dirtyRects);
            LEDDiffuseLit      = savedLEDDiffuseLit;
            LEDDiffuseUnlit    = savedLEDDiffuseUnlit;
            LEDMaterial        = savedLEDMaterial;
            litTrailDiffuse    = savedlitTrailDiffuse;
            unlitTrailDiffuse  = savedunlitTrailDiffuse;
            litTrailDiffuseAlt = savedlitTrailDiffuseAlt;
        }
    }

private:

    // if true, can only be dragged when enabled
    bool _strictMovement = false;
    
    enum MAX_CONDITION = 2;

    Parameter[MAX_CONDITION] _condParam;
    int[MAX_CONDITION] _valueToEnable;

    shared(int) lastCond = -1;

    // recompute condition, and dirty the knob if appropriate
    void recomputeCondition()
    {
        int newCond = 1;

        foreach(icond; 0..MAX_CONDITION)
        {
            Parameter p = _condParam[icond];
            if (p !is null)
            {
                if (auto pi = cast(IntegerParameter)p)
                    newCond = pi.value() == _valueToEnable[icond];
                else if (auto pb = cast(BoolParameter)p)
                    newCond = cast(int)(pb.value()) == _valueToEnable[icond];
                else
                    assert(false); // support IntegerParameter or BoolParameter
            }
            if (newCond == 0)
                break;
        }

        int current = atomicLoad(lastCond);       
        if (current != newCond)
        {
            atomicStore(lastCond, newCond);
            setDirtyWhole();
        }
    }    

    void addConditionParam(Parameter masterParam, int enableValue)
    {
        foreach(icond; 0..MAX_CONDITION)
        {
            if (_condParam[icond] is null)
            {
                _valueToEnable[icond] = enableValue;
                _condParam[icond] = masterParam;
                masterParam.addListener(this);
                return;
            }
        }

        assert(false); // not enough condition slots
    }

    void enableAllConditions()
    {
        foreach(icond; 0..MAX_CONDITION)
        {
            Parameter p = _condParam[icond];
            if (p !is null)
            {
                if (auto pi = cast(IntegerParameter)p)
                {
                    if (pi.value() != _valueToEnable[icond])
                    {
                        pi.beginParamEdit();
                        pi.setFromGUI(_valueToEnable[icond]);
                        pi.endParamEdit();
                    }
                }
                else if (auto pb = cast(BoolParameter)p)
                {
                    assert(_valueToEnable[icond] == 0 || _valueToEnable[icond] == 1);
                    if (pb.value() != _valueToEnable[icond])
                    {
                        pb.beginParamEdit();
                        pb.setFromGUI(_valueToEnable[icond] > 0);
                        pb.endParamEdit();
                    }
                }
                else
                    assert(false); // support IntegerParameter or BoolParameter
            }            
        }
        // no dirtying there, considering this might be set elsewhere (not sure)
    }
}
