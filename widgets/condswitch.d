/**
Conditional switch.

Copyright: Copyright Guillaume Piolat 2015-2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)

*/
module auburn.gui.condswitch;

import core.atomic;
import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.pbrwidgets.onoffswitch;
import dplug.client.params;

/// Switch that have a "disabled" state depending on a condition
class UICondSwitch : UIOnOffSwitch
{
public:
nothrow:
@nogc:

    this(UIContext context, BoolParameter param)
    {
        super(context, param);
    }    

    // MAYDO: different colors for disabled ON and disabled OFF

    @ScriptProperty bool enableSectionOnUse = false;
    @ScriptProperty RGBA diffuseDisabledOn = RGBA(128, 128, 128, 0);
    @ScriptProperty RGBA diffuseDisabledOff = RGBA(128, 128, 128, 0);
    
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

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // override parent members just for redraw
        bool enabled = (1 == atomicLoad(lastCond));
        if (!enabled)
        {
            RGBA savedDiffuseOn = diffuseOn;
            RGBA savedDiffuseOff = diffuseOff;
            diffuseOn = diffuseDisabledOn;
            diffuseOff = diffuseDisabledOff;
            super.onDrawPBR(diffuseMap, depthMap, materialMap, dirtyRects);
            diffuseOn = savedDiffuseOn;
            diffuseOff = savedDiffuseOff;
        }
        else
        {
            super.onDrawPBR(diffuseMap, depthMap, materialMap, dirtyRects);
        }
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
