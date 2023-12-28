/**
* Copyright: Guillaume Piolat 2022
* License:   Boost 1.0
*/

// This is the very complicated EQ control in the Lens compressor.
// 2 ideas here:
// - points have a cached local value in case it takes too much to always get the parameter value (perhaps not useful)
// - state enum to match the right end of drag with the onclick
// note: this needs hidden parameter for points being visible, else the problem was 
// that when loading a preset too many points were staying visible.
module eqcontrol;

import core.atomic;
import core.stdc.string;
import core.stdc.stdio;
import std.math;
import dplug.core;
import dplug.gui;
import dplug.client.params;
import dplug.canvas;
import gui;
import auburn.gui;
import eqparams;
import config;

enum float PICKING_DISTANCE_POINT = 10;
enum float FREE_PICKING_TO_CREATE_POINT = 18; // else, too easy to create points

enum CURVE_POINTS = 256;
enum float ARROW_HEIGHT = 0.15f;

// FUTURE: we can't get the information that a ctrl modifier was pressed without mouse move.
// => https://github.com/AuburnSounds/Dplug/issues/667
// Note: loops marked ALL_BANDS_INCLUDING_MIRROR_EQ move 
// points in this EQ control, and in the other one too.
enum ALL_BANDS_INCLUDING_MIRROR_EQ = MAX_EQ_BANDS * 2;


struct BandParams
{
nothrow:
@nogc:

    BoolParameter enable; // Whether the band is active
    FloatParameter hz;
    FloatParameter gain;
    FloatParameter bw;
    BoolParameter visible; // only used by EQ controls, in order to pick a band.

    void addListener(IParameterListener listener)
    {
        enable.addListener(listener);
        hz.addListener(listener);
        gain.addListener(listener);
        bw.addListener(listener);
        visible.addListener(listener);
    }

    void removeListener(IParameterListener listener)
    {
        enable.removeListener(listener);
        hz.removeListener(listener);
        gain.removeListener(listener);
        bw.removeListener(listener);
        visible.removeListener(listener);
    }
}

// Whole state of a band.
struct BandState
{
nothrow:
@nogc:
    BandParams params;

   // bool visible = false;
    bool visibleCache = false;

    bool selected; // If in selection

    float gainAtStartOfArrowDrag = 0.0f;

    // cached param values, read only
    BandSettings cache;

    void pullValues()
    {
        cache.enabled = params.enable.valueAtomic();
        cache.hz = params.hz.valueAtomic();
        cache.gain = params.gain.valueAtomic();
        cache.bw = params.bw.valueAtomic();
        visibleCache = params.visible.valueAtomic();
    }

    void startEdit()
    {
        assert(selected);
        params.hz.beginParamEdit();
        params.gain.beginParamEdit();
        params.bw.beginParamEdit();
    }

    void stopEdit()
    {
        assert(selected);
        params.hz.endParamEdit();
        params.gain.endParamEdit();
        params.bw.endParamEdit();
    }

    void startArrowDragEdit()
    {
        assert(visibleCache && selected);
        params.gain.beginParamEdit();
        gainAtStartOfArrowDrag = cache.gain;
    }

    void stopArrowDragEdit()
    {
        assert(visibleCache && selected);
        params.gain.endParamEdit();
    }

    void toggleEnabled()
    {
        params.enable.beginParamEdit();
        params.enable.toggleFromGUI();
        params.enable.endParamEdit();
    }

    void disableUnselectAndMakeInvisible()
    {
        params.enable.beginParamEdit();
        params.enable.setFromGUI(false);
        params.enable.endParamEdit();

        selected = false;

        params.visible.beginParamEdit();
        params.visible.setFromGUI(false);
        params.visible.endParamEdit();
        visibleCache = false;
    }
}

// Note: each EQControl also has an "arrow control" on its side, which scales 
// selected input from -200% to 200%

final class UIEQControl : UIElement, IParameterListener
{
public:
nothrow:
@nogc: 

    @ScriptProperty
    {
        RGBA selectColor = RGBA(255, 255, 0, 255);
        RGBA selectHintColor = RGBA(255, 255, 255, 255);
        RGBA colorMetering = RGBA(82, 82, 82, 255);
        RGBA colorMeteringFaint = RGBA(82, 82, 82, 255);
        float margin = 12.5;
        float metersLineWidth = 0.4;
        float curveLineWidth = 2.5;
        int bandGradientAlpha1 = 100;
        int bandGradientAlpha2 = 40;
        int bandGradientAlpha3 = 0;

        RGBA curveColor = RGBA(210, 210, 210, 110);
        float pointRadius = 2.3f;
        RGBA pointColor = RGBA(210, 210, 210, 255);
        RGBA pointColorDisabled = RGBA(128, 128, 128, 255);
        RGBA pointColorDoublyDisabled = RGBA(128, 128, 128, 255);
        RGBA pointColorSelected = RGBA(255, 255, 255, 255);
        RGBA pointColorDragged =  RGBA(255, 255, 0, 255);
        RGBA selectionRectangleColor = RGBA(255, 255, 0, 64);
        RGBA selectorColorDisabled = RGBA(128, 128, 128, 255);
        float pointSelectorRadius = 4.0;
        float selectorLineWidth = 1.2;
        float sensitivity = 0.6;
        float sensitivityWheel = 2.5f;

        RGBA highlightColor = RGBA(255, 255, 255, 16);

        RGBA textColor = RGBA(255, 255, 255, 255);
        RGBA textColorDragged = RGBA(255, 255, 255, 255);
        RGBA textOverlayColor = RGBA(0, 0, 0, 64);
        float textLineWidth = 2.5f;
        ubyte textLineAlpha = 128;
        float fontSize = 11.0f;
        float textMargin = 1.0f;

        float showBandTime = 0.5;

        float feedbackLineWidth = 1;
        RGBA colorFeedback = RGBA(255, 82, 82, 255);
        RGBA colorFeedbackDisabled = RGBA(80, 80, 80, 255);
        float feedBackOffsetDb = 36;
        float rmsDecayTime = 0.3f;
        float minimumAnimationDelta = 0.1f;

        RGBA gainReductionColor = RGBA(242, 251, 130, 255);
        float rmsDecayTimeGR = 0.3f;
    }

    // Do not display GR below GR_OFFSET dB
    enum float GR_OFFSET = 1e-2f;

    enum State
    {
        // those state display compressor state
        initial, // default state, just display EQ

        dragPoints, // drag selected bands (the one who have .selected flag in their state)

        dragArrow, // drag scale arrows

        deletePoints, // clicked cross

        mirrorPoints, // clicked mirror icon

        selectPoints, // draw a selection rectangle

        fakeDrag, // A state that does a fake dragging that doesn't modify parameters
    }

    this(UIContext context, 
         Font font,
         float minDisplayableDb, 
         float maxDisplayableDb,
         Parameter enableParam, 
         Parameter tiltParam, 
         Parameter compRatio, // used for mirror EQing
         BandParams[MAX_EQ_BANDS] bandParams,
         bool arrowIsLeftSide,
         UIGlobalHint globHint)
    {
        super(context, flagRaw | flagAnimated);
        _font = font;
        _globHint = globHint;
        _enableParam = cast(BoolParameter) enableParam;
        _enableParam.addListener(this);
        _arrowIsLeftSide = arrowIsLeftSide;
        _compRatio = cast(FloatParameter) compRatio;

        _tiltParam = cast(FloatParameter) tiltParam;
        _tiltParam.addListener(this);

        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            _bands[b].params = bandParams[b];
            _bands[b].params.addListener(this);
            _bands[b].pullValues();
        }
        
        _minDisplayableDb = minDisplayableDb;
        _maxDisplayableDb = maxDisplayableDb;

        float[CURVE_POINTS] binFreq;
        foreach(k; 0..CURVE_POINTS)
        {
            _curveBinFrequencies[k] = logmap!float(k / (CURVE_POINTS - 1.0f), MIN_FREQ, MAX_FREQ);
            _curveBinMIDINotes[k] = convertFrequencyToMIDINote(_curveBinFrequencies[k]);
        }

        _binFrequenciesX[] = 1;
        _binEnergy_dB[] = INVISIBLE_MIN_DB;
        _peak_dB[] = INVISIBLE_MIN_DB;
        _rms_dB[] = INVISIBLE_MIN_DB;
        _binGR_dB[] = 0;
        _GR_dB[] = 0;

        _state = State.initial;

        _defaultBandBW = arrowIsLeftSide ? DEFAULT_BAND_BW_SC : DEFAULT_BAND_BW_OUT;
    }

    enum INVISIBLE_MIN_DB = -110;

    void setOther(UIEQControl other, bool otherIsSidechain)
    {
        _other = other;
        _otherIsSidechain = otherIsSidechain;
    }

    ~this()
    {
        _enableParam.removeListener(this);
        _tiltParam.removeListener(this);
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            _bands[b].params.removeListener(this);
        }
    }

    void sendFeedback(float sampleRate, int numBins, 
                      float* binFrequencies, float* binEnergy,
                      float* binGR)
    {
        _drawFeedback = true;        
        _numBins = numBins;

        for (int k = 0; k < numBins; ++k)
        {
            _binFrequenciesX[k] = mapFreqToX(binFrequencies[k]);
        }

        if (binGR)
        {
            _drawGR = true;
            for (int k = 0; k < numBins; ++k)
            {
                _binGR_dB[k] = convertLinearGainToDecibel(binGR[k]);
            }
        }

        for (int k = 0; k < numBins; ++k)
        {
            _binEnergy_dB[k] = convertLinearGainToDecibel(binEnergy[k]);
            if (_binEnergy_dB[k] < INVISIBLE_MIN_DB)
                _binEnergy_dB[k] = INVISIBLE_MIN_DB;
        }

        for (int k = 0; k < numBins; ++k)
        {
            _binEnergy_dB[k] = convertLinearGainToDecibel(binEnergy[k]);
            if (_binEnergy_dB[k] < INVISIBLE_MIN_DB)
                _binEnergy_dB[k] = INVISIBLE_MIN_DB;
        }
        for (int k = numBins; k < MAX_BINS; ++k)
            _binEnergy_dB[k] = INVISIBLE_MIN_DB;
    }

    // return true if dirty
    bool rateLimiteAnimation(double dt)
    {
        bool dirty = false;

        // progress LFO of selected point alpha
        _selectPointHighlightPhase += dt;
        while(_selectPointHighlightPhase >= 32 * PI)
            _selectPointHighlightPhase -= 32 * PI;

        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (_bands[b].selected)
            {
                dirty = true;
            }
        }

        // Animate peak and RMS display
        {
            bool volumeIsLow = true;

            if (dt < 0.0001) dt = 0.0001;
            double alpha = 1.0 - expDecayFactor(rmsDecayTime, 1 / (dt));            

            for (int k = 0; k < MAX_BINS; ++k)
            {
                _rms_dB[k]  = alpha * _rms_dB[k]  + (1 - alpha) * _binEnergy_dB[k];
                _peak_dB[k] = alpha * _peak_dB[k] + (1 - alpha) * _binEnergy_dB[k];
                if (_peak_dB[k] < _binEnergy_dB[k])
                    _peak_dB[k] = _binEnergy_dB[k];

                // If silent or very faint, do not update widget.
                if (_peak_dB[k] > -90 && k < _numBins)
                {
                    volumeIsLow = false;
                }
            }

            if (!volumeIsLow)
                dirty = true;

            if (_drawGR)
            {
                int thereIsNoGR = 1;

                if (volumeIsLow)
                {
                    for (int k = 0; k < MAX_BINS; ++k)
                    {
                        _GR_dB[k] = 0;
                    }
                }
                else
                {
                    
                    double alphaGR = 1.0 - expDecayFactor(rmsDecayTimeGR, 1 / (dt));

                    for (int k = 0; k < MAX_BINS; ++k)
                    {
                        _GR_dB[k]  = alphaGR * _GR_dB[k]  + (1 - alphaGR) * _binGR_dB[k];
                        if (_GR_dB[k] < -GR_OFFSET)
                            thereIsNoGR = 0;
                    }
                }

                if (thereIsNoGR != _thereIsNoGR)
                {
                    dirty = true;
                    _thereIsNoGR = thereIsNoGR;
                }
            }
        }
        return dirty;
    }

    

    override void onAnimate(double dt, double time)
    {
        // dirty if any point selected (they are animated)

        // Some parts of the animation are slower
        _rateLimitDt += dt;
        if (_rateLimitDt > minimumAnimationDelta)
        {
            bool dirty = rateLimiteAnimation(_rateLimitDt);
            if (dirty)
                setDirtyWhole();
            _rateLimitDt = 0;
        }

        int bandUnderMouse = bandPointedTo(_lastMouseX, _lastMouseY, PICKING_DISTANCE_POINT);
        if (bandUnderMouse != -1 && bandUnderMouse == _lastBandUnderMouse)
        {
            _mouseHasBeenStaticFor += dt;
            if (_mouseHasBeenStaticFor > 10)
                _mouseHasBeenStaticFor = 10;
        }
        else
        {
            _mouseHasBeenStaticFor = 0;
        }

        // Mouse wheel reset text display, so as not to pollute the view.
        if (cas(&_seenMouseWheel, true, false))
            _mouseHasBeenStaticFor = 0;

        _lastBandUnderMouse = bandUnderMouse;
        setAllowShowBandText(_mouseHasBeenStaticFor > showBandTime);        
    }

    void setAllowShowBandText(bool allow)
    {
        if (allowShowBandText != allow)
        {
            allowShowBandText = allow;
            setDirtyWhole();
        }
    }

    void pullValues()
    {
        // update all bands local state
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            _bands[b].pullValues();
        }

        // Get compressor threshold, compute _otherDbFactor the dB conversion factor between the two EQ.
        float compRatio = _compRatio.value();
        if (compRatio > 4) compRatio = 4; // Do not compensate too much either. Limit to be found maybe.
        _otherDbFactor = _otherIsSidechain ? compRatio : (1.0f / compRatio);
    }

    void updateCurveIfNeeded()
    {
        if (!cas(&_curveNeedUpdate, 1, 0))
            return;

        // from cached values, display curve.
        CompanderEQParams eqParams;
        eqParams.enableEQ = true;
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
            eqParams.bands[b] = _bands[b].cache;
        eqParams.tilt = _tiltParam.value();

        _currentCurve[] = 1.0f;

        computeEQWeights(eqParams, 
                         CURVE_POINTS,
                         _currentCurve.ptr,
                         _curveBinMIDINotes[0..CURVE_POINTS]);

        // Convert back to dB
        for (int k = 0; k < CURVE_POINTS; ++k)
        {
            _currentCurve[k] = convertLinearGainToDecibel(_currentCurve[k]);

            /// Update bins X
            _curveX[k] = mapFreqToX(_curveBinFrequencies[k]);

            _curveY[k] = mapDBToY(_currentCurve[k]);
        }
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        bool eqEnabled = _enableParam.value();
        bool mouseOnArrow = isPointOnArrow(_lastMouseX, _lastMouseY);
        bool eqCouldBeEnabledOnClick = !eqEnabled && isMouseOver && !mouseOnArrow && !otherIsDragged;

        pullValues();
        updateCurveIfNeeded();

        float selectorHintSize = pointSelectorRadius*2 * _S;

        int bandUnderMouse = bandPointedTo(_lastMouseX, _lastMouseY, PICKING_DISTANCE_POINT);
        int bandAlmostUnderMouse = bandPointedTo(_lastMouseX, _lastMouseY, FREE_PICKING_TO_CREATE_POINT);

        box2f unclippedSelRect = selectionRectangle();

        ubyte alphaSelected = cast(ubyte)(240.5f + 15.0f * sin(12*_selectPointHighlightPhase));

        float mLeft = marginPxLeft;
        float mRight = marginPxRight;
        float mTop = marginPxTop;
        float mBottom = marginPxBottom;

        // Find if just one band is selected in this EQ, and which one.
        // If so, it will display text about it.
        int numSelectedHere = 0;
        int onlyBandSelectedIndex = -1;
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (getBand(b).selected) 
            {
                onlyBandSelectedIndex = b;
                numSelectedHere++;
            }
        }
        if (numSelectedHere != 1)
            onlyBandSelectedIndex = -1;

        foreach(dirtyRect; dirtyRects)
        {
            // Small margin top and bottom
            int topmargin = cast(int)(0.5f + 4 * _S);
            box2i canvasRect = dirtyRect.intersection(box2i.rectangle(0, topmargin, position.width, position.height - 2 * topmargin));
            if (canvasRect.empty)
                continue;

            // crop the dirty rect more

            auto cRaw = rawMap.cropImageRef(canvasRect);
            canvas.initialize(cRaw);
            canvas.translate(-canvasRect.min.x, -canvasRect.min.y);

            // draw horz meters
            for (int dB = -30; dB <= 30 ;  dB += 6)
            {
                RGBA col = (dB % 12 == 0) ? colorMetering : colorMeteringFaint;
                col.a -= std.math.abs(dB) * 5;
                canvas.fillStyle = col;
                canvas.fillHorizontalLine(mLeft, _W - mRight, mapDBToY(dB), metersLineWidth * _S);
            }

            // Draw feedback lines
            if (_drawFeedback)
            {
                float gain = 0;
                float Y0 = mapDBToY(-100 + feedBackOffsetDb);

                RGBA feedCol = eqEnabled ? colorFeedback : colorFeedbackDisabled;
                float lw = feedbackLineWidth * _S * 0.5f;

                canvas.fillStyle = feedCol;
                canvas.beginPath();
                for(int k = 0; k < _numBins; ++k)
                {
                    float X = _binFrequenciesX[k];
                    float peakY = mapDBToY(_peak_dB[k] + feedBackOffsetDb);
                    float rmsY = mapDBToY(_rms_dB[k] + feedBackOffsetDb);
                    canvas.moveTo(X - lw, rmsY);
                    canvas.lineTo(X + lw, rmsY);
                    canvas.lineTo(X + lw, Y0);
                    canvas.lineTo(X - lw, Y0);
                }
                canvas.fill();

                feedCol.a /= 2;
                canvas.fillStyle = feedCol;
                canvas.beginPath();
                for(int k = 0; k < _numBins; ++k)
                {
                    float X = _binFrequenciesX[k];
                    float peakY = mapDBToY(_peak_dB[k] + feedBackOffsetDb);
                    float rmsY = mapDBToY(_rms_dB[k] + feedBackOffsetDb);
                    canvas.moveTo(X - lw, rmsY);
                    canvas.lineTo(X + lw, rmsY);
                    canvas.lineTo(X + lw, peakY);
                    canvas.lineTo(X - lw, peakY);
                }
                canvas.fill();

                // draw GR
                if (_drawGR)
                {
                    RGBA grCol = eqEnabled ? gainReductionColor : colorFeedbackDisabled;
                    canvas.fillStyle = grCol;
                    canvas.beginPath();
                    float Ytop = 6 * _S;

                    float A = _minDisplayableDb;
                    float B = _maxDisplayableDb;
                    float C = _H-marginPxBottom + (Ytop - marginPxTop);
                    float D = Ytop;
                    float DC_BA = (D - C) / (B - A);

                    for(int k = 0; k < _numBins; ++k)
                    {
                        if ( _GR_dB[k] < -GR_OFFSET)
                        {
                            float X = _binFrequenciesX[k];
                            float value = _maxDisplayableDb + _GR_dB[k];
                            float GR_Y = C + DC_BA * (value - A);
                            canvas.moveTo(X - lw, Ytop);
                            canvas.lineTo(X + lw, Ytop);
                            canvas.lineTo(X + lw, GR_Y);
                            canvas.lineTo(X - lw, GR_Y);
                        }
                    }
                    canvas.fill();
                }

                // GR feedback
            }

            // Draw curve
            {
                float lw = curveLineWidth * 0.5f;
                RGBA curveCol = curveColor;
                if (!eqEnabled) curveCol = pointColorDisabled;
                canvas.fillStyle = curveCol;


                vec2f start = vec2f(_curveX[0], _curveY[0]);
                vec2f stop = vec2f(_curveX[CURVE_POINTS-1], _curveY[CURVE_POINTS-1]);

                canvas.beginPath();
                canvas.moveTo(start);

                for (int k = 1; k + 1 < CURVE_POINTS; ++k)
                { 
                    // Pa and Pb are the line cap points.
                    //
                    //   Pb--Pa-----------
                    //  /  P--------------A
                    // /  /
                    //   /
                    //  B
                    vec2f B = vec2f(_curveX[k-1], _curveY[k-1]);
                    vec2f P = vec2f(_curveX[k]  , _curveY[k]  );
                    vec2f A = vec2f(_curveX[k+1], _curveY[k+1]);
                    vec2f PA = (A - P).fastNormalized;
                    vec2f PB = (B - P).fastNormalized;

                    canvas.lineTo(P + vec2f(-PB.y*lw, PB.x*lw)); // Pb
                    canvas.lineTo(P + vec2f(PA.y*lw, -PA.x*lw)); // Pa
                }
                canvas.lineTo(stop);
                for (int k = CURVE_POINTS - 2; k > 0; --k)
                {  
                    vec2f B = vec2f(_curveX[k-1], _curveY[k-1]);
                    vec2f P = vec2f(_curveX[k]  , _curveY[k]  );
                    vec2f A = vec2f(_curveX[k+1], _curveY[k+1]);
                    vec2f PA = (A - P).fastNormalized;
                    vec2f PB = (B - P).fastNormalized;

                    canvas.lineTo(P - vec2f(PA.y*lw, -PA.x*lw)); // Pa2
                    canvas.lineTo(P - vec2f(-PB.y*lw, PB.x*lw)); // Pb2
                }
                canvas.fill();
            }

            // Draw bands
            for (int b = 0; b < MAX_EQ_BANDS; ++b)
            {
                bool bandEnabled = _bands[b].cache.enabled;
                bool enabled = eqEnabled && bandEnabled;
                bool doubleDisabled = !eqEnabled && !bandEnabled;
                bool visible = _bands[b].visibleCache;
                bool selected = _bands[b].selected;
                float hz = _bands[b].cache.hz;
                float bw = _bands[b].cache.bw;
                float gain = _bands[b].cache.gain;

                //       Q           <-- actual curve point, corrected gain
                //       P           <-- shown point
                //      / \
                //     C   D         <-- point intersecting with margin
                // ----A   B----     <-- curve points at 0dB
                //

                vec2f Q = bandPointScaledGain(_bands[b]);
                vec2f P = bandPoint(_bands[b]);
                vec2f A = bandPointLow(_bands[b]);
                vec2f B = bandPointHigh(_bands[b]);
                vec2f C = A;
                vec2f D = B;
                float mleft = mLeft;
                float mright = mRight;
                // clip to borders
                if (A.x < mleft)
                {
                    float t = (mleft - Q.x) / (A.x - Q.x);
                    float y = Q.y + (A.y - Q.y) * t;
                    C = vec2f(mleft, y);
                    A.x = C.x;
                }
                if (B.x > _W - mright)
                {
                    float t = (_W - mright - Q.x) / (B.x - Q.x);
                    float y = Q.y + (B.y - Q.y) * t;
                    D = vec2f(_W - mright, y);
                    B.x = D.x;
                }

                if (visible)
                {
                    bool bandIsDragged = ((_state == State.dragPoints || _state == State.dragArrow
                                           || _other._state == State.dragPoints || _other._state == State.dragArrow) && selected);

                    bool bandIsDraggedVertically = bandIsDragged && (_dragLocksFrequency || _other._dragLocksFrequency);
                    bool bandIsDraggedByArrow = bandIsDragged && (_state == State.dragArrow || _other._state == State.dragArrow);

                    bool bandIsSelected = selected;
                    bool bandIsOnlyOneSelected = (onlyBandSelectedIndex == b);

                    bool bandCouldBeSelectedByMouse = (_state == State.initial && b == bandUnderMouse);
                    bool bandCouldBeSelected = bandCouldBeSelectedByMouse
                                            || (_state == State.selectPoints && unclippedSelRect.contains(P) && (bandEnabled || _selectionRectAdd));
                    if (otherIsDragged)
                        bandCouldBeSelected = false;

                    // Draw points. Color of point and its selector are intertwined,
                    // but when a point is disabled it is always displayed grey and has no band gradient.
                    // `color` is reused for point color, selector, and band gradient

                    // Main color, from which are derived others
                    RGBA color = pointColor;
                    if (!enabled) color = pointColorDisabled;
                    if (bandIsSelected) color = pointColorSelected;
                    if (bandIsDragged) color = pointColorDragged;                    

                    // Color of center point
                    RGBA pcolor = color;
                    if (!enabled) pcolor = pointColorDisabled;
                    if (doubleDisabled) pcolor = pointColorDoublyDisabled;
                    if (selected) pcolor.a = alphaSelected; // if a point is selected, it's alpha value is a sinusoid

                    // draw band gradient
                    if (enabled)
                    {
                        auto gradient = canvas.createLinearGradient(P.x, P.y, P.x, A.y);
                        gradient.addColorStop(0.0f, RGBA(color.r, color.g, color.b, cast(ubyte)bandGradientAlpha1));
                        gradient.addColorStop(0.5f, RGBA(color.r, color.g, color.b, cast(ubyte)bandGradientAlpha2));
                        gradient.addColorStop(1.0f, RGBA(color.r, color.g, color.b, cast(ubyte)bandGradientAlpha3));
                        canvas.fillStyle = gradient;
                        canvas.beginPath;
                        canvas.moveTo(A);
                        canvas.lineTo(C);
                        canvas.lineTo(Q);
                        canvas.lineTo(D);
                        canvas.lineTo(B);
                        canvas.fill();
                    }                   

                    // If band is dragged vertically, draw vertical grey line
                    if (bandIsDragged || bandIsDraggedVertically)
                    {
                        float gradientExtent = 70;
                        RGBA curveColor1 = color;
                        RGBA curveColor2 = color;
                        curveColor1.a = 128;
                        curveColor2.a = 0;

                        if (!bandIsDraggedByArrow)
                        {
                            auto gradient = canvas.createLinearGradient(P.x, P.y - gradientExtent, P.x, P.y + gradientExtent);
                            gradient.addColorStop(0.0f, curveColor2);
                            gradient.addColorStop(0.5f, curveColor1);
                            gradient.addColorStop(1.0f, curveColor2);
                            canvas.fillStyle = gradient;

                            float y1 = P.y - gradientExtent;
                            float y2 = P.y + gradientExtent;
                            if (y1 < mTop) y1 = mTop;
                            if (y2 > _H - mBottom) y2 = _H - mBottom;
                            canvas.fillVerticalLine(P.x, y1, y2, metersLineWidth * _S);
                        }
                        else
                        {
                            float y0 = mapDBToY(0);
                            auto gradient = canvas.createLinearGradient(P.x, P.y, P.x, y0);
                            gradient.addColorStop(0.0f, curveColor1);
                            gradient.addColorStop(1.0f, curveColor2);
                            canvas.fillStyle = gradient;
                            float y1 = P.y;
                            if (y1 < mTop) y1 = mTop;
                            if (y1 > _H - mBottom) y1 = _H - mBottom;
                            canvas.fillVerticalLine(P.x, y1, y0, metersLineWidth * _S);
                        }

                        if (!bandIsDraggedVertically && !bandIsDraggedByArrow)
                        {
                            auto gradientH = canvas.createLinearGradient(P.x - gradientExtent, P.y, P.x + gradientExtent, P.y);
                            gradientH.addColorStop(0.0f, curveColor2);
                            gradientH.addColorStop(0.5f, curveColor1);
                            gradientH.addColorStop(1.0f, curveColor2);
                            canvas.fillStyle = gradientH;
                            float x1 = P.x - gradientExtent;
                            float x2 = P.x + gradientExtent;
                            if (x1 < mLeft) x1 = mLeft;
                            if (x2 > _W - mRight) x2 = _W - mRight;
                            canvas.fillHorizontalLine(x1, x2, P.y, metersLineWidth * _S);
                        }
                    }

                    // Display frequency if being dragged, and only one selected.
                    // Draw text if band is dragged but not with arrow
                    bool allowShowBandTextCurrently = isDragged ? allowShowBandTextAtDragStart : allowShowBandText;
                    bool dragAndNeedFrequencyDisplay = bandIsOnlyOneSelected && (bandIsDragged && !bandIsDraggedByArrow && !bandIsDraggedVertically);
                    bool displayFreqText = (allowShowBandTextCurrently && (bandCouldBeSelectedByMouse || dragAndNeedFrequencyDisplay));
                    bool dragAndNeedGainDisplay = bandIsOnlyOneSelected && bandIsDragged;
                    bool displayGainText = (allowShowBandTextCurrently && (bandCouldBeSelectedByMouse || dragAndNeedGainDisplay));
                    RGBA textCol = bandIsDragged ? textColorDragged : textColor;
                    RGBA textLineCol = textCol;
                    textLineCol.a = textLineAlpha;

                    if (displayFreqText)
                    {
                        canvas.fillStyle = textLineCol;
                        canvas.fillVerticalLine(P.x, marginPxTop, _H - marginPxBottom, textLineWidth*_S);
                    }

                    if (displayGainText)
                    {
                        canvas.fillStyle = textLineCol;
                        canvas.fillHorizontalLine(marginPxLeft, _W - marginPxRight, P.y, textLineWidth*_S);
                    }

                    // DRAW POINT
                    canvas.fillStyle = pcolor;
                    canvas.fillCircle(P, pointRadius * _S);
                    
                    // If band is dragged, draw selector around its point
                    if (bandIsDragged)
                    {
                        canvas.fillStyle = color;
                        canvas.fillSquare(P.x, P.y, selectorHintSize + selectorLineWidth * _S, selectorHintSize);
                    }

                    // If band is selected thanks to selection rectangle
                    else if (bandIsSelected)
                    {
                        canvas.fillStyle = color;
                        canvas.fillSquare(P.x, P.y, selectorHintSize + selectorLineWidth * _S, selectorHintSize);
                    }

                    // If band could be selected by clicking there, or is in selection rectangle, draw selector
                    else if (bandCouldBeSelected)
                    {
                        canvas.fillStyle = selectorColorDisabled;
                        canvas.fillSquare(P.x, P.y, selectorHintSize + selectorLineWidth * _S, selectorHintSize);
                    }

                 
                    if (displayFreqText)
                    {
                        char[16] str;
                        convertFrequencyToStringN(hz, str.ptr, 16);
                        const(char)[] pstr = str[0..strlen(str.ptr)];

                        float fontSizePx = fontSize * _S;
                        float letterSpacingPx = 0.0f;
                        box2i extent = _font.measureText(pstr, fontSizePx, letterSpacingPx);
                        float twidth = extent.width * 0.5f;
                        float theight = _font.getHeightOfx(fontSizePx);                        
                        
                        float textX = P.x;
                        if (textX < marginPxLeft + twidth)
                        {
                            textX = marginPxLeft + twidth;
                        }
                        if (textX > _W - marginPxRight - twidth)
                        {
                            textX = _W - marginPxRight - twidth;
                        }
                        float textY = (gain > _minDisplayableDb * 0.6f) ? (_H - marginPxBottom - theight) : marginPxTop + theight;

                        canvas.fillStyle = textOverlayColor;
                        canvas.fillRect(textX - twidth - _S * textMargin, 
                                        textY - theight - _S * textMargin, 
                                        twidth * 2 + 2 * _S * textMargin,
                                        theight * 2 + 2 * _S * textMargin);                        
                        cRaw.fillText(_font, pstr, fontSizePx, 0.0f, textCol, textX - canvasRect.min.x, textY - canvasRect.min.y);
                    }

                    if (displayGainText)
                    {                        
                        char[16] str;
                        if (_lastCTRLPressed)
                        {
                            convertBWToStringN(bw, str.ptr, 16);
                        }
                        else
                        {
                            convertGainToStringN(gain, str.ptr, 16);
                        }
                        const(char)[] pstr = str[0..strlen(str.ptr)];

                        float fontSizePx = fontSize * _S;
                        float letterSpacingPx = 0.0f;
                        box2i extent = _font.measureText(pstr, fontSizePx, letterSpacingPx);
                        float twidth = extent.width * 0.5f;
                        float theight = _font.getHeightOfx(fontSizePx);

                        float textY = P.y;
                        if (textY < marginPxTop + theight)
                        {
                            textY = marginPxTop + theight;
                        }
                        if (textY > _H - marginPxBottom - theight)
                        {
                            textY = _H - marginPxBottom - theight;
                        }
                        float textX = (hz < 5200) ? (_W - marginPxRight - twidth) : marginPxLeft + twidth;
                        canvas.fillStyle = textOverlayColor;
                        canvas.fillRect(textX - twidth - _S * textMargin, 
                                        textY - theight - _S * textMargin, 
                                        twidth * 2 + 2 * _S * textMargin,
                                        theight * 2 + 2 * _S * textMargin);                        
                        cRaw.fillText(_font, pstr, fontSizePx, 0.0f, textCol, textX - canvasRect.min.x, textY - canvasRect.min.y);
                    }
                }
            }

            // Draw band that could be created by clicking on curve.
            bool canCreateOnCurve = (_state == State.initial)
                                  && isPointOnCurve(_lastMouseX, _lastMouseY) 
                                  && !otherIsDragged
                                  && (getFirstInvisibleBand() != -1)
                                  && (bandUnderMouse == -1 && bandAlmostUnderMouse == -1);
            if (canCreateOnCurve)
            {
                vec2f pointToCreate = suggestedPointOnCurve(_lastMouseX, _lastMouseY);
                canvas.fillStyle = pointColor;
                canvas.fillCircle(pointToCreate, pointRadius * _S);
            }

            // Draw arrow
            if (arrowShouldBeShown) 
            {
                RGBA arrowColor = pointColorDisabled;
                if (isPointOnArrow(_lastMouseX, _lastMouseY) && arrowCanBeDragged) arrowColor = pointColorSelected;
                if (_state == State.dragArrow) arrowColor = pointColorDragged;

                float midH = _H * 0.5f;

                float crossDistanceX = 11.5f;
                float crossWidthX = 0.75f * 1.3f;
                float crossExtentX = 2.5f * 1.3f;
                float crossCap = 0.15f * 1.3f;

                // Draw this:
                //
                // htop -------
                //
                //   x0 x1x2x3 x4
                // y0      A
                //        / \
                //       /   \
                //      /     \
                // y1  B--D C--G
                //        | |
                // y2  H--I J--K
                //      \     /
                //       \   /
                //        \ /
                // y3      E
                //  
                //
                // hbottom -----

                float x2 = 25 * _S - crossDistanceX * _S;

                if (!_arrowIsLeftSide)
                {
                    x2 = _W - x2;
                }

                float x0 = x2 - crossExtentX*_S;
                float x4 = x2 + crossExtentX*_S;
                float x1 = x2 - crossWidthX*_S;
                float x3 = x2 + crossWidthX*_S;

                float HH = (_H - mTop-mBottom);
                float htop = midH - HH * ARROW_HEIGHT;
                float hbottom = midH - HH * -ARROW_HEIGHT;

                float y0 = midH - HH * ARROW_HEIGHT * _arrowDragState;
                float y1 = midH - HH * ARROW_HEIGHT * _arrowDragState * (1 - crossCap);
                float y2 = midH - HH * ARROW_HEIGHT * _arrowDragState * crossCap;
                float y3 = midH;

                vec2f A = vec2f(x2, y0);
                vec2f B = vec2f(x0, y1);
                vec2f D = vec2f(x1, y1);
                vec2f I = vec2f(x1, y2);
                vec2f H = vec2f(x0, y2);
                vec2f E = vec2f(x2, y3);
                vec2f K = vec2f(x4, y2);
                vec2f J = vec2f(x3, y2);
                vec2f C = vec2f(x3, y1);
                vec2f G = vec2f(x4, y1);

                RGBA markColor = pointColorDisabled;
                markColor.a = 100;
                canvas.fillStyle = markColor;
                canvas.fillLine(vec2f(x0, htop), vec2f(x4, htop), 1.3 * _S);
                canvas.fillLine(vec2f(x0, hbottom), vec2f(x4, hbottom), 1.3 * _S);

                canvas.fillStyle = arrowColor;
                canvas.beginPath();
                canvas.moveTo(A);
                canvas.lineTo(B);
                canvas.lineTo(D);
                canvas.lineTo(I);
                canvas.lineTo(H);
                canvas.lineTo(E);
                canvas.lineTo(K);
                canvas.lineTo(J);
                canvas.lineTo(C);
                canvas.lineTo(G);
                canvas.fill();
            }

            // Draw cross
            if (crossShouldBeShown) 
            {
                RGBA crossColor = pointColorDisabled;
                if (isPointOnCross(_lastMouseX, _lastMouseY) && crossCanBeDragged) crossColor = pointColorSelected;
                if (_state == State.deletePoints) crossColor = pointColorDragged;

                float fx7 = 0.68;
                float fx = 13.5;
                float fy = 18.0;
                float fc = 2.3;
                float fx8 = 0.25;
                
                float X = fx * _S;
                if (!_arrowIsLeftSide)
                {
                    X = _W - X;
                }

                float Y = fy * _S;

                float t = _S*fc;

                float x0 = X - 2*t;
                float x1 = X -   t;
                float x5 = X + 3*t*fx7;

                float ym1 = Y - 3*t*fx7;
                float y0 = Y - 2*t;
                float y1 = Y -   t;
                float y3 = Y +   t;
                float y4 = Y + 2*t;
                float y5 = Y + 3*t*fx7;
                //          m
                //   b  
                // a   
                //   
                // k  
                //   j   
                //          n
                vec2f a = vec2f(x0, y1);
                vec2f b = vec2f(x1, y0);
                vec2f j = vec2f(x1 + fx8*t, y4);
                vec2f k = vec2f(x0 + fx8*t, y3);
                vec2f m = vec2f(x5 + fx8*t, ym1);
                vec2f n = vec2f(x5, y5);

                canvas.fillStyle = crossColor;
                canvas.beginPath();
                canvas.moveTo(a);
                canvas.lineTo(b);
                canvas.lineTo(n);
                canvas.fill();

                canvas.fillStyle = crossColor;
                canvas.beginPath();
                canvas.moveTo(k);
                canvas.lineTo(j);
                canvas.lineTo(m);
                canvas.fill();
            }

            // Draw mirror
            if (mirrorShouldBeShown) 
            {
                RGBA mirrorColor = pointColorDisabled;
                if (isPointOnMirror(_lastMouseX, _lastMouseY) && mirrorCanBeDragged) mirrorColor = pointColorSelected;
                if (_state == State.mirrorPoints) mirrorColor = pointColorDragged;

                float fx = 13.5f;
                float fy = 18.0f;
                float fc = 2.9f;
                float fx1 = 0.8f;
                float fx2 = 2.8f;
                float fx3 = 0.8f;
                float fx4 = 2.3f;
                float X = fx * _S;
                if (!_arrowIsLeftSide)
                {
                    X = _W - X;
                }

                float Y = _H - fy * _S;

                float t = _S*fc*fx1;

                float x0 = X - fx4*t;
                float x2 = X; 
                float x4 = X + fx4*t;
                float y0 = Y - 2*t;
                float y2 = Y; 
                float y4 = Y + 2*t;

                //     a  
                //
                //   d   c
                //
                //     b  
                vec2f a = vec2f(x2, y0);
                vec2f b = vec2f(x2, y4);
                vec2f c = vec2f(x4, y2);
                vec2f d = vec2f(x0, y2);

                canvas.fillStyle = mirrorColor;
                canvas.fillLine(a, b, _S * fx2);

                // draw two little triangles
                void fillTriangle(ref Canvas canvas, vec2f center, float radius, float fx) nothrow @nogc
                {
                    enum float SQRT_0_75 = sqrt(0.75f);
                    enum float D = cos(PI / 3) / 2;
                    canvas.beginPath();
                    canvas.moveTo(center.x + ( (SQRT_0_75 - D)*fx)*radius*2, center.y +      0); 
                    canvas.lineTo(center.x + ( -D*fx             )*radius*2, center.y +  radius );
                    canvas.lineTo(center.x + ( -D*fx             )*radius*2, center.y +  -radius );
                    canvas.fill();
                }
                fillTriangle(canvas, c, t * fx3, -1.0f);
                fillTriangle(canvas, d, t * fx3,  1.0f);
            }

            // Draw selection rectangle
            if (_state == State.selectPoints)
            {
                // clip selection rectangles to valid positions
                vec2f origin = clipSelectionPoint(_selRectOrigin);
                vec2f target = clipSelectionPoint(_selRectTarget);
                canvas.fillStyle = selectionRectangleColor;
                canvas.beginPath();
                canvas.moveTo(origin);
                canvas.lineTo(origin.x, target.y);
                canvas.lineTo(target);
                canvas.lineTo(target.x, origin.y);
                canvas.closePath();
                canvas.fill();
            }

            // Draw highligt rectangle, that says EQ could be enabled if we click
            if (eqCouldBeEnabledOnClick)
            {
                vec2f topLeft = clipSelectionPoint( vec2f(0, 0) );
                vec2f bottomRight = clipSelectionPoint( vec2f(_W, _H) );
                canvas.fillStyle = highlightColor;
                canvas.fillRect(box2f(topLeft, bottomRight));
            }
        } 
    }

    vec2f bandPointScaledGain(ref BandState band)
    {
        float X = mapFreqToX(band.cache.hz);
        float Y = mapDBToY(band.cache.scaledGain);
        return vec2f(X, Y);
    }

    vec2f bandPoint(ref BandState band)
    {
        float X = mapFreqToX(band.cache.hz);
        float Y = mapDBToY(band.cache.gain);
        return vec2f(X, Y);
    }

    vec2f bandPointLow(ref BandState band)
    {
        float X = mapFreqToX(band.cache.lowCrossPointHz());
        float Y = mapDBToY(0);
        return vec2f(X, Y);
    }

    vec2f bandPointHigh(ref BandState band)
    {
        float X = mapFreqToX(band.cache.highCrossPointHz());
        float Y = mapDBToY(0);
        return vec2f(X, Y);
    }

    bool isPointInSideMargin(float x, float y)
    {
        if (x == AUBURN_MOUSE_TOO_FAR)
            return false;
        return (_arrowIsLeftSide && (x < 25 * _S)) || (!_arrowIsLeftSide && (x >= _W - 25 * _S));
    }

    bool isPointOnCurve(float x, float y)
    {
        return distanceToCurve(x, y) < 10 * _S;
    }

    bool isPointOnArrow(float x, float y)
    {
        bool isOnArrowY = fast_fabs(y - _H * 0.5f) < ARROW_HEIGHT * 2 * (_H - marginPxTop-marginPxBottom);
        return isPointInSideMargin(x, y) && isOnArrowY;
    }

    bool isPointOnCross(float x, float y)
    {
        bool isOnCrossY = y < _H * 0.5f - ARROW_HEIGHT * 2 * (_H - marginPxTop-marginPxBottom);
        return isPointInSideMargin(x, y) && isOnCrossY;
    }

    bool isPointOnMirror(float x, float y)
    {
        bool isPointOnMirrorY = y > _H * 0.5f + ARROW_HEIGHT * 2 * (_H - marginPxTop-marginPxBottom);
        return isPointInSideMargin(x, y) && isPointOnMirrorY;
    }

    // If we are dragging the other EQ, do not highlight things in this EQ.
    bool otherIsDragged()
    {
        return context.dragged is _other;
    }

    bool mirrorShouldBeShown()
    {
        if (_state == State.mirrorPoints)
            return true;
        return onePointIsSelected();
    }

    bool crossShouldBeShown()
    {
        if (_state == State.deletePoints)
            return true;
        return onePointIsSelected();
    }

    bool arrowShouldBeShown()
    {
        if (_state == State.dragArrow)
            return true;
        return onePointIsSelected();
    }

    bool mirrorCanBeDragged()
    {
        if (!mirrorShouldBeShown)
            return false;
        if (otherIsDragged())
            return false;
        return _state == State.initial;
    }

    bool crossCanBeDragged()
    {
        if (!crossShouldBeShown)
            return false;
        if (otherIsDragged())
            return false;
        return _state == State.initial;
    }

    bool arrowCanBeDragged()
    {
        if (!arrowShouldBeShown)
            return false;
        if (otherIsDragged())
            return false;
        return _state == State.initial;
    }

    bool onePointIsSelected()
    {
        int numSelected = 0;
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (_bands[b].selected)
            {
                numSelected++;
            }
        }
        return numSelected >= 1;
    }

    override bool onKeyDown(Key key)
    {
        // So that we can't delete or unselect point in the middle of a drag.
        if (isDragged)
            return false;

        pullValues();
        _other.pullValues();

        assert(_state == State.initial);

        if (key == Key.escape)
        {
            unselectAllBandsincludingMirrorEQ();
            setDirtyWhole();
            return true;
        }
        else if (key == Key.backspace || key == Key.suppr)
        {
            deleteSelectedPoints();
            setDirtyWhole();
            return true;
        }
        else if (key == Key.m || key == Key.M)
        {
            if (mirrorCanBeDragged())
            {
                mirrorSelectedPoints();
                return true;
            }
        }
        else if (key == Key.d || key == Key.D)
        {
            toggleSelectedPoints();
            return true;
        }

        return false;
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        _lastCTRLPressed = mstate.ctrlPressed;

        if (_state != State.initial)
            return Click.unhandled;

        allowShowBandTextAtDragStart = allowShowBandText;

        pullValues();
        _other.pullValues();
        bool eqEnabled = _enableParam.value();

        bool rightClick = (button == MouseButton.right);
        bool middleClick = (button == MouseButton.middle); // shortcut for "delete"
        bool leftClick = !rightClick && !middleClick;

        bool isOnArrow = isPointOnArrow(x, y);
        bool isOnCross = isPointOnCross(x, y);
        bool isOnMirror = isPointOnMirror(x, y);
        int band = bandPointedTo(x, y, PICKING_DISTANCE_POINT);
        int bandAlmost = bandPointedTo(_lastMouseX, _lastMouseY, FREE_PICKING_TO_CREATE_POINT);
        bool onCurve = isPointOnCurve(x, y);

        if (isOnCross)
        {
            if (crossCanBeDragged())
            {
                deleteSelectedPoints();
                _state = State.deletePoints;
                return Click.startDrag;
            }
            else
                return Click.unhandled;
        }
        else if (isOnMirror)
        {
            if (mirrorCanBeDragged())
            {
                mirrorSelectedPoints();
                _state = State.mirrorPoints;
                return Click.startDrag;
            }
            else
                return Click.unhandled;
        }
        else if (isOnArrow)
        {
            if (arrowCanBeDragged())
            {
                // Start an arrow drag.
                enableWholeEQIfDisabled();
                _state = State.dragArrow;
                _arrowDragState = 1.0f;
                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    if (getBand(b).selected)
                    {
                        getBand(b).startArrowDragEdit();
                    }
                }
                return Click.startDrag; // Start edit of every band paramater that is selected.
            }
            else
                return Click.unhandled;
        }
        else if (band == -1)
        {
            bool createOnCurve = (onCurve && bandAlmost == -1);
            if (createOnCurve || isDoubleClick || (leftClick && mstate.ctrlPressed))
            {
                float px = x;
                float py = y;
                
                // Create it on curve, in the case of on-curve creation.
                if (createOnCurve)
                {
                    vec2f pt = suggestedPointOnCurve(x, y);
                    px = pt.x;
                    py = pt.y;
                }

                // Find the first invisible band, create a point there.
                // Make the band visible.
                int firstInvisibleBand = getFirstInvisibleBand();
                if (firstInvisibleBand == -1)
                {
                    _globHint.displayErrorMessage("No more bands available.", 1500);
                    return Click.unhandled; // No more available bands.
                }

                enableWholeEQIfDisabled();
                if (!mstate.shiftPressed)
                    unselectAllBandsincludingMirrorEQ();

                // Activate this one band, and start a dragging operations in dragPoints state.
                with(_bands[firstInvisibleBand])
                {
                    selected = true;
                    params.enable.beginParamEdit();
                    params.enable.setFromGUI(true);
                    params.enable.endParamEdit();
                }

                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    if (getBand(b).selected)
                    {
                        getBand(b).startEdit();
                    }
                }

                // Setup new band position
                with(_bands[firstInvisibleBand])
                {
                    float hz = mapXToFreq(px);
                    float gain = mapYToDB(py);
                    _bands[firstInvisibleBand].params.hz.setFromGUI(hz);
                    _bands[firstInvisibleBand].params.gain.setFromGUI(gain);
                    _bands[firstInvisibleBand].params.bw.setFromGUI(_defaultBandBW);
                }

                _state = State.dragPoints;
                _dragLocksFrequency = rightClick;

                // Make the band visible
                with(_bands[firstInvisibleBand])
                {
                    params.visible.beginParamEdit();
                    params.visible.setFromGUI(true);
                    params.visible.endParamEdit();
                    visibleCache = true;
                }

                return Click.startDrag;
            }
            else if (leftClick)
            {
                enableWholeEQIfDisabled();
                _selRectTarget = _selRectOrigin = vec2f(x, y);
                _state = State.selectPoints;
                _selectionRectAdd = mstate.shiftPressed;
                return Click.startDrag;
            }
        }
        else if ( mstate.altPressed && band != -1 )
        {
            // Delete selected points => disable them and make them invisible
            assert(_bands[band].visibleCache);
            if (!_bands[band].selected)
            {
                if (!mstate.shiftPressed)
                    unselectAllBandsincludingMirrorEQ();
                _bands[band].selected = true;
            }
            deleteSelectedPoints();
            _state = State.fakeDrag;
            return Click.startDrag;
        }
        else if (isDoubleClick && band != -1)
        {
            assert(_bands[band].visibleCache);
            enableWholeEQIfDisabled();

            // Clicking on point band, start a drag operation.
            // Select this band if it's not already.
            if (!_bands[band].selected)
            {
                if (!mstate.shiftPressed)
                    unselectAllBandsincludingMirrorEQ();
                _bands[band].selected = true;
            }

            // What we do: toggle "enabled" and then finish with a dragPoints state of all selected bands.

            toggleSelectedPoints();

            _dragLocksFrequency = false;
            goto startDragPoints;            
        }
        else if ((leftClick || rightClick) && band != -1)
        {
            assert(_bands[band].visibleCache);
            enableWholeEQIfDisabled();      

            _dragLocksFrequency = rightClick;

            // Clicking on point band, start a drag operation.
            // Select this band if it's not already.
            if (!_bands[band].selected)
            {
                if (!mstate.shiftPressed)
                    unselectAllBandsincludingMirrorEQ();
                _bands[band].selected = true;
            }

            startDragPoints:

            _state = State.dragPoints;
            for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
            {
                if (getBand(b).selected)
                    getBand(b).startEdit();
            }
            
            return Click.startDrag; // Start edit of every band paramater that is selected.
        }
        return Click.unhandled;
    }

    override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY, MouseState mstate)
    {
        atomicStore(_seenMouseWheel, true);
        _lastMouseX = x;
        _lastMouseY = y;
        _lastCTRLPressed = mstate.ctrlPressed;
        pullValues();
        _other.pullValues();


        float modifier = sensitivityWheel;
        if (mstate.shiftPressed)
            modifier *= 0.1f;
        float amountOfChange = -wheelDeltaY * modifier;

        if (_state == State.initial)
        {
            int bandUnderMouse = bandPointedTo(_lastMouseX, _lastMouseY, PICKING_DISTANCE_POINT);
            
            if (bandUnderMouse == -1 && !isAnyBandSelected()) 
                return true; // nothing to do, handled

            // now we know some bands have to apply this change => enable EQ if needed
            enableWholeEQIfDisabled();

            for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
            {
                if (getBand(b).selected || b == bandUnderMouse)
                {
                    getBand(b).params.bw.beginParamEdit();
                    float bw = getBand(b).cache.bw;
                    bw += amountOfChange;
                    getBand(b).params.bw.setFromGUI(bw);
                    getBand(b).params.bw.endParamEdit();
                }
            }
        }
        else if (_state == State.dragPoints)
        {
            for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
            {
                if (getBand(b).selected)
                {
                    float bw = getBand(b).cache.bw;
                    bw += amountOfChange;
                    getBand(b).params.bw.setFromGUI(bw);
                }
            }
        }
        
        return true; // Always handled by this widget.
    }

    void enableWholeEQIfDisabled()
    {
        // Enable EQ if not enabled already.
        if (!_enableParam.value())
        {
            _enableParam.beginParamEdit();
            _enableParam.setFromGUI(true);
            _enableParam.endParamEdit();
        }
    }

    void mirrorSelectedPoints()
    {
        _other.enableWholeEQIfDisabled();

        // For each selected local point, create a point in the mirror

        // Unselect every band in the other EQ
        // After the operation, only newly created points will be selected.
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            _other._bands[b].selected = false;
        }

        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (_bands[b].selected)
            {
                _bands[b].selected = false;

                // Create similar point on the other side EQ
                int firstInvisibleBand = _other.getFirstInvisibleBand();
                if (firstInvisibleBand == -1)
                {
                    _other._globHint.displayErrorMessage("No more bands available.", 1500);
                    break; // No more available bands.
                }

                // On the other EQ: activate this one band, make it visible, 
                // and start a dragging operations in dragPoints state.
                with(_other._bands[firstInvisibleBand])
                {
                    params.visible.beginParamEdit();
                    params.visible.setFromGUI(true);
                    params.visible.endParamEdit();
                    visibleCache = true;
                    selected = true;

                    // Basically make a copy of this band point on the other EQ.                    

                    float hz = _bands[b].cache.hz;

                    // Note: creating new points must be aligned somehow.
                    // Convert gain so that they are.
                    float gainConversion = OUTPUT_EQ_EXTENT_DB / cast(float)SIDECHAIN_EQ_EXTENT_DB ;
                    if (_otherIsSidechain)
                        gainConversion = 1.0f / gainConversion;

                    float gain = _bands[b].cache.gain * gainConversion;
                    float bw = _bands[b].cache.bw;
                    bool enabled = _bands[b].cache.enabled;

                    params.enable.beginParamEdit();
                    params.enable.setFromGUI(enabled);
                    params.enable.endParamEdit();

                    startEdit();
                    params.hz.setFromGUI(hz);
                    params.gain.setFromGUI(gain);
                    params.bw.setFromGUI(bw);
                    stopEdit();
                }
            }
        }
        setDirtyWhole();
        _other.setDirtyWhole();
    }

    void deleteSelectedPoints()
    {
        enableWholeEQIfDisabled();

        for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
        {
            if (getBand(b).selected)
            {
                getBand(b).disableUnselectAndMakeInvisible();
            }
        }
    }

    void toggleSelectedPoints()
    {
        for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
        {
            if (getBand(b).selected)
            {
                getBand(b).toggleEnabled();
            }
        }
    }

    bool isAnyBandSelected()
    {
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (_bands[b].selected)
                return true;
        }
        return false;
    }
    
    void unselectAllBandsincludingMirrorEQ()
    {
        for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
        {
            getBand(b).selected = false;
        }
        _other.setDirtyWhole();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        _lastCTRLPressed = mstate.ctrlPressed;
        setDirtyWhole();
    }

    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseX = x;
        _lastMouseY = y;
        _lastCTRLPressed = mstate.ctrlPressed;
        pullValues();
        _other.pullValues();


        // SHIFT click for 10x more precise points
        float modifier = 1.0f;
        if (mstate.shiftPressed)
            modifier *= 0.1f;

        bool locksFrequency = _dragLocksFrequency;
        
        final switch (_state)
        {
            case State.initial: assert(false);
            case State.fakeDrag: break;
            case State.deletePoints: break;
            case State.mirrorPoints: break;
            case State.dragPoints: 
                // Set every dragged points
                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    BandState* bnd = getBand(b);
                    if (bnd.selected)
                    {
                        float bw = bnd.cache.bw;
                        float hz = bnd.cache.hz;
                        float gain = bnd.cache.gain;
                        float xInPixels = mapFreqToX(hz);
                        float yInPixels = mapDBToY(gain);
                        float finalFactor = modifier * sensitivity / _S;
                        float finalFactorVert = mirrorSensitivity(b) * finalFactor;
                        xInPixels += dx * finalFactor;
                        yInPixels += dy * finalFactorVert;
                        if (!locksFrequency)
                            bnd.params.hz.setFromGUI( mapXToFreq(xInPixels) );

                        if (mstate.ctrlPressed)
                        {
                            bw += dy * finalFactor; // Annoying, but multiple selection gets awkward without.
                            bnd.params.bw.setFromGUI(bw);
                        }
                        else
                        {
                            // Move gain.
                            bnd.params.gain.setFromGUI( mapYToDB(yInPixels) );
                        }
                    }
                }
                break;

            case State.dragArrow: 
            {
                float finalFactor = 0.02f * modifier * sensitivity / _S;
                _arrowDragState -= dy * finalFactor;
                if (_arrowDragState < -2.0f) _arrowDragState = -2.0f;
                if (_arrowDragState > 2.0f) _arrowDragState = 2.0f;
                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    BandState* bnd = getBand(b);
                    if (bnd.selected)
                    {
                        float gain = bnd.gainAtStartOfArrowDrag * _arrowDragState;
                        bnd.params.gain.setFromGUI(gain);
                    }
                }
                break;
            }

            case State.selectPoints:
                _selRectTarget.x += dx;
                _selRectTarget.y += dy;
                setDirtyWhole();
                break;
        }
    }

    override void onMouseExit()
    {
        _lastMouseX = AUBURN_MOUSE_TOO_FAR;
        _lastMouseY = AUBURN_MOUSE_TOO_FAR;
        _lastCTRLPressed = false;
        setDirtyWhole();
    }

    override void onFocusExit()
    {
        // Clicking elsewhere unselect every selected points,
        // unless if it's the other EQ.

        if (context.focused is _other)
            return;

        for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
        {
            getBand(b).selected = false;
        }
        setDirtyWhole();
        _other.setDirtyWhole();
    }

    override void onParameterChanged(Parameter sender)
    {
        atomicStore(_curveNeedUpdate, 1);
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


    override void onBeginDrag()
    {
        // Need to be recorded so that subsequent onStopDrag modify the right 
        // parameters.
        _stateWhenDraggingBegan = _state;
    }

    override void onStopDrag()
    {
        _mouseHasBeenStaticFor = 0;
        final switch (_stateWhenDraggingBegan)
        {
            case State.initial: assert(false);
            case State.fakeDrag: break;
            case State.deletePoints: break;
            case State.mirrorPoints: break;
            case State.dragArrow: 
                // Stop edit of every dragged point
                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    if (getBand(b).selected)
                        getBand(b).stopArrowDragEdit();
                }
                _arrowDragState = 1.0f; // reset arrow drag position
                break;

            case State.dragPoints:
                // Stop edit of every dragged point
                for (int b = 0; b < ALL_BANDS_INCLUDING_MIRROR_EQ; ++b)
                {
                    if (getBand(b).selected)
                        getBand(b).stopEdit();
                }
                break;

            case State.selectPoints:
            {
                // Select all band points that are visible and enabled and inside the selection rectangle.
                box2f selRect = selectionRectangle();

                int bandAddedHere = 0;

                for (int b = 0; b < MAX_EQ_BANDS; ++b) 
                {
                    if (!_selectionRectAdd) 
                        _bands[b].selected = false;

                    // shift + rectangle adds to selection
                    if (_bands[b].visibleCache && (_bands[b].cache.enabled || _selectionRectAdd))
                    {
                        vec2f pt = bandPoint(_bands[b]);
                        if (selRect.contains(pt))
                        {
                            bandAddedHere++;
                            _bands[b].selected = true;
                        }
                    }
                }
                setDirtyWhole();
                
                if (bandAddedHere == 0)
                {
                    // no band added, we probably want to clear selection in the mirror EQ too.
                    for (int b = MAX_EQ_BANDS; b < 2*MAX_EQ_BANDS; ++b) 
                    {
                        if (!_selectionRectAdd) 
                            getBand(b).selected = false;
                    }
                    _other.setDirtyWhole();
                }
                break;
            }
        }

        _dragLocksFrequency = false;
        _state = State.initial;
        setDirtyWhole();
    }

    float marginPxLeft() pure nothrow const @safe
    {
        float m = margin * _S;
        if (_arrowIsLeftSide)
            m += 25 * _S;
        return m;
    }

    float marginPxRight() pure nothrow const @safe
    {
        float m = margin * _S;
        if (!_arrowIsLeftSide)
            m += 25 * _S;
        return m;
    }

    float marginPxTop() pure nothrow const @safe
    {
        return margin * _S;
    }

    float marginPxBottom() pure nothrow const @safe
    {
        return margin * _S;
    }

    override void reflow()
    {
        atomicStore(_curveNeedUpdate, 1);
        _W = position.width;
        _H = position.height;
        _S = (_W / 325);
        _RADIUS = _S * pointRadius;
    }     

private:

    BoolParameter _enableParam;
    FloatParameter _tiltParam;
    FloatParameter _compRatio;

    BandState[MAX_EQ_BANDS] _bands;

    // Accessor for this EQ bands, or the mirror bands.
    // For every loop that is "mirrored" on the other EQ side.
    BandState* getBand(int n)
    {
        if (n < MAX_EQ_BANDS)
            return &_bands[n];
        else
            return &(_other._bands[n - MAX_EQ_BANDS]);
    }

    float mirrorSensitivity(int n)
    {
        return (n < MAX_EQ_BANDS) ? 1.0f : _otherDbFactor;
    }

    float _minDisplayableDb;
    float _maxDisplayableDb;

    State _state, _stateWhenDraggingBegan;

    UIEQControl _other; // The EQ control from the other side of the UI.
    UIGlobalHint _globHint; // for reporting error messages
    bool _otherIsSidechain; // In order to manage compensation in both sides.
    float _otherDbFactor;

    bool _dragLocksFrequency; // this drag doesn't allow changing freq
    bool _selectionRectAdd; // shift + selection rectangle adds to the selection, also selects disabled bands in this mode

    float _W, _H, _S;
    float _RADIUS;

    bool _arrowIsLeftSide;
    float _arrowDragState = 1.0f; // from -2 to +2, amount of drag change from initial values.

    Canvas canvas;
    Font _font;

    int _lastMouseX = AUBURN_MOUSE_TOO_FAR;
    int _lastMouseY = AUBURN_MOUSE_TOO_FAR;
    shared(bool) _lastCTRLPressed = false;

    float _dragBothExpMinDb;
    float _dragBothCompMaxDb;
    float _selectPointHighlightPhase = 0.0f;

    vec2f _selRectOrigin;
    vec2f _selRectTarget;

    bool _drawFeedback = false;
    bool _drawGR = false;
    int _numBins = 0;
    float[MAX_BINS] _binFrequenciesX;
    float[MAX_BINS] _binEnergy_dB;
    float[MAX_BINS] _binGR_dB;

    float _defaultBandBW;

    // A peak and "RMS" process for the incoming energy, which is varying too quickly
    // and is distracting.
    float[MAX_BINS] _peak_dB;
    float[MAX_BINS] _rms_dB;

    // Smoothed GR
    float[MAX_BINS] _GR_dB;

    shared(bool) _seenMouseWheel;

    // -1 => uninitialized
    //  0 => there is some GR going on, last we checked
    //  1 => last GR was all very low
    int _thereIsNoGR = -1;

    shared(int) _curveNeedUpdate = 1;
    float[CURVE_POINTS] _curveBinFrequencies;
    float[CURVE_POINTS] _curveBinMIDINotes;
    float[CURVE_POINTS] _currentCurve;
    float[CURVE_POINTS] _curveX, _curveY;

    int _lastBandUnderMouse = -1;
    double _mouseHasBeenStaticFor = 0;
    bool allowShowBandText = false;
    bool allowShowBandTextAtDragStart = false;
    
    double _rateLimitDt = 0;

    vec2f nearestPointOnCurve(float x, float y)
    {
        float bestDist = 1e6f;
        vec2f bestPt = vec2f(0, 0);
        for (int n = 0; n < CURVE_POINTS; ++n)
        {
            vec2f pt = vec2f(_curveX[n], _curveY[n]);
            float dist = pt.squaredDistanceTo(vec2f(x, y));
            if (dist < bestDist)
            {
                bestDist = dist;
                bestPt = pt;
            }
        }
        return bestPt;
    }

    vec2f suggestedPointOnCurve(float x, float y)
    {
        vec2f near = nearestPointOnCurve(x, y);
        return vec2f(near.x, near.y);
    }

    float distanceToCurve(float x, float y)
    {
        return nearestPointOnCurve(x, y).distanceTo(vec2f(x, y));
    }

    int getFirstInvisibleBand()
    {
        int firstInvisibleBand = -1;
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            if (!_bands[b].visibleCache)
            {
                firstInvisibleBand = b;
                break;
            }
        }
        return firstInvisibleBand;
    }

    box2f selectionRectangle() // in pixels
    {
        float xmin = _selRectOrigin.x  < _selRectTarget.x ? _selRectOrigin.x : _selRectTarget.x;
        float xmax = _selRectOrigin.x >= _selRectTarget.x ? _selRectOrigin.x : _selRectTarget.x;
        float ymin = _selRectOrigin.y  < _selRectTarget.y ? _selRectOrigin.y : _selRectTarget.y;
        float ymax = _selRectOrigin.y >= _selRectTarget.y ? _selRectOrigin.y : _selRectTarget.y;
        return box2f(xmin, ymin, xmax, ymax);
    }

    // clip selection rectangle bounds so that it is displayed
    vec2f clipSelectionPoint(vec2f pt) pure nothrow @nogc @safe
    {        
        float GAP = 9;
        float minx = marginPxLeft - GAP * _S;
        float maxx = _W - marginPxRight + GAP * _S;
        float miny = marginPxTop - GAP * _S;
        float maxy = _H - marginPxBottom + GAP * _S;
        if (pt.x < minx) pt.x = minx;
        if (pt.y < miny) pt.y = miny;
        if (pt.x > maxx) pt.x = maxx;
        if (pt.y > maxy) pt.y = maxy;
        return pt;
    }

    float mapDBToY(float dB) pure nothrow @nogc @safe
    {
        return linmap!float(dB, _minDisplayableDb, _maxDisplayableDb, _H-marginPxBottom, marginPxTop);
    }

    float mapYToDB(float Y) pure nothrow @nogc @safe
    {
        return linmap!float(Y, _H-marginPxBottom, marginPxTop, _minDisplayableDb, _maxDisplayableDb);
    }

    float mapFreqToX(float hz)
    {
        // Convert to normalized frequency.
        float nhz = log(hz / MIN_FREQ) / log(MAX_FREQ / MIN_FREQ);
        return linmap!float(nhz, 0, 1, marginPxLeft, _W - marginPxRight);
    }

    float mapXToFreq(float X)
    {
        float nhz = linmap!float(X, marginPxLeft, _W - marginPxRight, 0, 1);
        return logmap!float(nhz, MIN_FREQ, MAX_FREQ);
    }

    // Return: the nearest band from the point x,y
    //         -1 if none found.
    // Search can up to maxPossibleDistance * _S pixels far.
    int bandPointedTo(int x, int y, float maxPossibleDistance)
    {
        vec2f mouse = vec2f(x, y);
        float bestDist = maxPossibleDistance * _S;
        int bestBand = -1;
        for (int b = 0; b < MAX_EQ_BANDS; ++b)
        {
            vec2f point = bandPoint(_bands[b]);
            if (_bands[b].visibleCache) // can't click on invisible bands
            {
                float dist = point.distanceTo(mouse);
                if (dist < bestDist)
                {
                    bestBand = b;
                    bestDist = dist;
                }
            }
        }
        return bestBand;
    }
}

private:

void convertGainToStringN(float gain_dB, char* buffer, size_t numBytes) nothrow @nogc
{
    snprintf(buffer, numBytes, "%2.1f dB", gain_dB);
    version(DigitalMars)
        if (numBytes > 0)
        {
            buffer[numBytes-1] = '\0';
        }
}

void convertBWToStringN(float bw, char* buffer, size_t numBytes) nothrow @nogc
{
    snprintf(buffer, numBytes, "%2.1f ERB", bw);
    version(DigitalMars)
        if (numBytes > 0)
        {
            buffer[numBytes-1] = '\0';
        }
}

void convertFrequencyToStringN(float inFrequencyHz, char* buffer, size_t numBytes) nothrow @nogc
{        
    float v = inFrequencyHz;

    int decimal = 0;
    bool kHz;
    float factor;
    string unit;
    // 0 to 10 hz => 2 decimals
    if (v < 10)
    {
        factor = 1;
        decimal = 2;
        unit = " Hz";
    }
    else if (v >= 10 && v < 100)
    {
        factor = 1;
        decimal = 1;
        unit = "Hz";
    }
    else if (v >= 100 && v < 1000)
    {
        factor = 1;
        decimal = 0;
        unit = "Hz";
    }
    else if (v >= 1000 && v < 10000)
    {
        factor = 0.001f;
        decimal = 2;
        unit = "kHz";
    }
    else if (v >= 10000)
    {
        factor = 0.001f;
        decimal = 1;
        unit = "kHz";
    }
    else if (v >= 10000)
    {
        factor = 0.001f;
        decimal = 0;
        unit = "kHz";
    }
    else
        assert(false);

    char[9] format;
    format[0..8] = "%2.2f %s"[0..8];
    format[3] = cast(char)('0' + decimal);
    format[8] = '\0';
        
    snprintf(buffer, numBytes, format.ptr, v * factor, unit.ptr);

    // DigitalMars's snprintf doesn't always add a terminal zero
    version(DigitalMars)
        if (numBytes > 0)
        {
            buffer[numBytes-1] = '\0';
        }
}