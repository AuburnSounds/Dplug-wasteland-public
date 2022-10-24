/**
A Parameter value hint, but for all parameters at once.

Copyright: Copyright Guillaume Piolat 2019
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.globalhint;

import core.stdc.string;
import core.stdc.stdio;
import core.atomic;

import core.stdc.stdlib: free;
import std.math;
import std.conv;
import std.algorithm.comparison;

import dplug.core;
import dplug.gui.element;
import dplug.client.params;


/// Widget that monitors the value of all parameters and display a string representation of the latest user-touched.
/// Can also use it for error messages.
class UIGlobalHint : UIElement, IParameterListener
{
public:
nothrow:
@nogc:

    @ScriptProperty double holdDuration = 4.0f;
    @ScriptProperty float textSizePx = 15.0f;
    @ScriptProperty float textOffsetX = 0.0f;
    @ScriptProperty float textOffsetY = 0.0f;
    @ScriptProperty float letterSpacingPx = 0.0f;
    @ScriptProperty RGBA textColor = RGBA(200, 200, 210, 200);
    @ScriptProperty RGBA textColorError = RGBA(200, 100, 100, 200);

    this(UIContext context, Parameter[] allParameters, Font font)
    {
        super(context, flagRaw | flagAnimated);

        _mutex = makeMutex();

        _font = font;

        _parameterIsEdited = mallocSlice!(shared(bool))(allParameters.length);
        _parameterIsEdited[] = false;

        _parameters = mallocDup(allParameters);
        foreach(param; _parameters)
        {
            // For now: do not display non-automatable parameters, since they are currently used to hold state in Lens
            if (param.isAutomatable)
                param.addListener(this);
        }
    }

    ~this()
    {
        foreach(param; _parameters)
        {
            if (param.isAutomatable)
                param.removeListener(this);
        }

        free(_parameters.ptr);
        free(cast(bool*)(_parameterIsEdited.ptr));
    }

    /// Override text display and display `msg` for `ms` milliseconds.
    void displayErrorMessage(const(char)[] msg, int ms)
    {
        // local copy
        size_t len = msg.length;
        if (len > 256) len = 256;
        _errorStringBuffer[0..len] = msg[0..len]; // racey here
        _errorString = _errorStringBuffer[0..len];
        atomicStore(_errorDisplayTime, ms * 0.001);
        atomicStore(_mustDisplayError, ms > 0);
        setDirtyWhole();
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        bool displayErr = atomicLoad(_mustDisplayError);
        if (!_lastVisibility && !displayErr)
            return;

        // empty by default, meaning this UIElement does not draw on the Raw layer

        float centerX = position.width * 0.5f;
        float centerY = position.height * 0.5f;        

        foreach (dirtyRect; dirtyRects)
        {
            int dx = dirtyRect.min.x;
            int dy = dirtyRect.min.y;
            auto croppedRaw = rawMap.cropImageRef(dirtyRect);
            const(char)[] text = displayErr ? _errorString : _lastParamString;
            RGBA color = displayErr ? textColorError : textColor;
            croppedRaw.fillText(_font, text, textSizePx, letterSpacingPx, color, 
                                centerX - dx + textOffsetX, centerY - dy + textOffsetY,
                                HorizontalAlignment.center,
                                VerticalAlignment.baseline);
        }
    }    

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        // check for messages from listener
        bool needRedraw = false;
        {
            _mutex.lock();
            scope(exit) _mutex.unlock();

            if (_oneParameterWasChanged)
            {
                _oneParameterWasChanged = false;
                needRedraw = true;
            }
        }
       
        bool visibility = _timeSinceEdit < holdDuration;
        bool visibilityChanged = false;
        if (visibility != _lastVisibility)
        {
            visibilityChanged = true;
            _lastVisibility = visibility;
        }

        // error message disappeared?
        // local copy
        bool errMsgDisappear = false;
        float errorTime = atomicLoad(_errorDisplayTime);
        if (errorTime > 0)
        {
            errorTime -= dt;
            if (errorTime < 0) 
            {
                errorTime = 0;
                errMsgDisappear = true;
            }
            atomicStore(_errorDisplayTime, errorTime);
            atomicStore(_mustDisplayError, errorTime > 0);            
        }

        // redraw if parameter changed and was being edited
        // or if error message disappeared
        if (needRedraw || visibilityChanged || errMsgDisappear)
            setDirtyWhole();

        _timeSinceEdit += dt;
    }

    override void onParameterChanged(Parameter sender) nothrow @nogc
    {
        foreach(size_t i, p; _parameters) // PERF: quadratic in number of parameters, but well...
        {
            if (p is sender)
            {
                // algorithm: if one parameter is edited and changed (by the user), then we take the lock, 
                // and mention "this is the last parameter that was changed"
                if (atomicLoad(_parameterIsEdited[i]))
                {
                    _mutex.lock();
                    scope(exit) _mutex.unlock();

                    _oneParameterWasChanged = true;
                    int whichParameter = cast(int)i;
                    _timeSinceEdit = 0;
                    if (_lastParameterChanged != whichParameter)
                    {
                        _previousParameter = _lastParameterChanged;
                        _lastParameterChanged = whichParameter;
                    }
                    _lastParamString = computeParamString(whichParameter, _previousParameter);             
                }
                break;
            }
        }
    }

    override void onBeginParameterEdit(Parameter sender)
    {
        foreach(size_t i, p; _parameters) // PERF: quadratic in number of parameters, but well...
        {
            if (p is sender)
            {
                atomicStore(_parameterIsEdited[i], true);
                break;
            }
        }
    }

    override void onEndParameterEdit(Parameter sender)
    {
        foreach(size_t i, p; _parameters) // PERF: quadratic in number of parameters, but well...
        {
            if (p is sender)
            {
                atomicStore(_parameterIsEdited[i], false);
                break;
            }
        }
    }

private:
    shared(bool)[] _parameterIsEdited; // access to this is through atomic ops
    
    UncheckedMutex _mutex;

    Font _font;
    Parameter[] _parameters; // local ref copy of parameters

    // <protected by _mutex>
    bool _oneParameterWasChanged; // one edited parameter has changed it's value
    int _previousParameter = -1; // former parameter that was changed, necessary because pair of edited params could still send AABB
    int _lastParameterChanged = -1;  // parameter at the last onParameterChanged
    const(char)[] _lastParamString; // only valid if _lastVisibility == true    
    const(char)[] _errorString;
    char[256] _paramStringBuffer;
    char[256] _valueStringBuffer;
    char[256] _valueStringBuffer2;
    double _timeSinceEdit = double.infinity;
    // </protected by _mutex>
    
    bool _lastVisibility = false;
    shared(bool) _mustDisplayError = false; // true => display error at next draw, false => display params.                                        
    char[256] _errorStringBuffer;
    shared(double) _errorDisplayTime = 0;

    // Compute next string to display
    const(char)[] computeParamString(int whichParam, int previousParam) nothrow @nogc
    {       
        Parameter param =_parameters[whichParam];
        param.toDisplayN(_valueStringBuffer.ptr, _valueStringBuffer.length);

        // special case: if two parameters are edited at once, display them both!
        if ((previousParam != -1) 
            && atomicLoad(_parameterIsEdited[previousParam]))
        {
            Parameter param2 =_parameters[previousParam];
            param2.toDisplayN(_valueStringBuffer2.ptr, _valueStringBuffer2.length);
            snprintf(_paramStringBuffer.ptr, 
                     _paramStringBuffer.length,
                     "%s = %s%s   %s = %s%s", 
                     assumeZeroTerminated(param.name), _valueStringBuffer.ptr, assumeZeroTerminated(param.label),
                     assumeZeroTerminated(param2.name), _valueStringBuffer2.ptr, assumeZeroTerminated(param2.label));

        }
        else
        {
            // one parameter case
            snprintf(_paramStringBuffer.ptr, 
                     _paramStringBuffer.length,
                     "%s = %s%s", 
                     assumeZeroTerminated(param.name), _valueStringBuffer.ptr, assumeZeroTerminated(param.label));
        }
        // DigitalMars's snprintf doesn't always add a terminal zero
        _paramStringBuffer[$-1] = '\0';
        return _paramStringBuffer[0..strlen(_paramStringBuffer.ptr)];
    }
}

