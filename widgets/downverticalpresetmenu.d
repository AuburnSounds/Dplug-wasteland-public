/**
Drop down PRESET BANK menu.
Internal Presets

Copyright: SMAOLAB 2025
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Author:   Stephane Ribas

Note 1 : This is a very naive and simple INTERNAL PRESET algo.
Note 2 : part of the code is inspired by Guillaume Piolat

  --- TUTORIAL BEFORE THE CODE -----

1- In gui.d, , at the top, declare :

...
import downverticalpresetmenu;
...

2- In gui.d, , at the end, in the private section, declare :

Private: 
    ...
    UIDownVerticalpresetmenu _presets;
    /// name of internal presets.
    enum presets_index {
        INIT,
        ENHANCE,
        GUITAR,
        BASS,
        DRUM,
    }
    static immutable presetsNameArray = [__traits(allMembers, presets_index)];
    ...

3- then, in gui.d, in the THIS function, write the following code : 

...
class AkiraTubeGUI : FlatBackgroundGUI!("new-akiratubebck.jpg") 
{
public:
nothrow:
@nogc:

    ...

    this(AkiraTubeClient client)
    {
        ...
        _client = client; // important !
        ...
        // PRESETS
        _presets= mallocNew!UIDownVerticalpresetmenu(context(), _font, cast(IntegerParameter) _client.param(param_Presets), presetsNameArray, _client);
        addChild(_presets);
        _presets.textSize(18); 
        _presets.font(_font); // optional 
        _presets.color(paramTextColor);// optional
        ...
    }
...

4- then ,in gui.d, in the 'reflow' function, write the following code : 

override void reflow()
    {
        super.reflow();

        int W = position.width;
        int H = position.height;

        float _textresizefactor, _textspacingresizefactor;

        float S = W / cast(float)(context.getDefaultUIWidth());
        _textresizefactor= 20*S; // 20 or 32 ... depends on your fonts :-)
        _textspacingresizefactor = 2.0f *S;
        ...

        // PRESETS 
        _presets.position = rectangle(20, 20, 90, 520).scaleByFactor(S); // <----- height=((80/3)*nbrofitems)
        _presets.textSize= _textresizefactor; 
        _presets.letterSpacing = _textspacingresizefactor;
    ...
    }

5 - in main.d, complete the following code : 

mixin(pluginEntryPoints!AkiraTubeClient);

enum : int
{ 
    param_Presets, // <------  important !!
    param_Input,
    param_moogLPFFrequency,
    param_moogLPFResonance,
    param_moogLPFDrive,
    param_Mix,
    param_Output,
}
...

6 - in main.d, complete the following code : 

...
final class AkiraBlaBlaClient : dplug.client.Client
{
public:
nothrow:
@nogc:
...

override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params.pushBack(mallocNew!EnumParameter(param_Presets, "Presets",presetsArray, 0) ); // <--- important !
        params.pushBack(mallocNew!GainParameter(param_Input, "Input gain", 0.0f, -4.0f) );
        ...
    }

...
}

7 - in main.d, at the end of the program, in the 'private' section, write the following code : 

private:     
...
/// name of the presets (the same declaration you wrote in the gui.d).
  enum presets_index {
    INIT,
    ENHANCE,
    GUITAR,
    BASS,
    DRUM,
  }
  static immutable presetsArray = [__traits(allMembers, presets_index)];
...

6- open the downverticalpresetmenu.d file, go down to the file :

// you will find, in the PROTECTED section, the bank !
// the value for each preset is right there
// I use an excel file to create my presets, 
// then I export it as a CSV file and re import as an "array" :-)

...
protected :
// float[23][5] --> NUMBER OF PARAMETERS FOLLOWED BY NUMBER OF PRESETS
float[23][5] presetvalues_row1=[
[1,-4,1,1,20,1,20,0,15,0,0,0,2200,0,0,0,1,12050,2,32,0,80,0],
[2,-4,1,1,25,1,20,0,15,1,1,5,8000,4,2,0,1,12050,2,32,0,100,0],
[3,-4,1,1,20,1,20,0,10,0,0,-12,4000,0,-6,1,1,3700,1.5,30,1,80,0],
[4,-4,1,1,50,1,65,0,20,1,0,-12,7200,-4,0,0,1,3300,2,32,1,80,0],
[5,-4,1,1,20,1,25,0,15,1,1,2,350,2,2,1,1,12050,1.75,30,1,100,0],
];
...

5- that's all :-)
*/
module downverticalpresetmenu;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.gui.bufferedelement;
import dplug.client.params;
import dplug.graphics.resizer;

import dplug.client.client;
import dplug.client.params;
import dplug.core.nogc; // for debug message in the stdio

class UIDownVerticalpresetmenu : UIBufferedElementRaw, IParameterListener
{
public:
nothrow:
@nogc:

    RGBA menuColor = RGBA(13, 10, 7, 240);
    RGBA menuColorSelected = RGBA(145, 127, 104, 240);
    RGBA menuColorCurrent = RGBA(100, 87, 68, 240);

    bool textEnabled = true;
    float textSizePx = 24.0f;
    RGBA textColor = RGBA(230, 230, 230, 230);
    //RGBA textColorSelected = RGBA(210, 210, 210, 240);

    this(UIContext context, Font font, IntegerParameter param0, const(string[]) labels, Client client) 
    {
        super(context, flagRaw);

        _presetnumber = param0; // The menu ! 
        _presetnumber.addListener(this);
        _pluginparametersarray = client.params();
        _font = font;
        _labels = labels;
        assert(_presetnumber.numValues() == labels.length);
    }

    void settextresizefactor(int S)
    {
        textSizePx= 16*S;
        _letterSpacing = 2.0f * S;
    }

    /// Returns: Size of displayed text.
    float textSize()
    {
        return textSizePx;
    }

    /// Sets size of displayed text.
    float textSize(float textSize_)
    {
        //setDirtyWhole();
        return textSizePx = textSize_;
    }

    float letterSpacing(float letterSpacing_)
    {
            //setDirtyWhole();
            return _letterSpacing = letterSpacing_;
    }

    float letterSpacing()
    {
        return _letterSpacing;
    }

    /// Make this `UIDropdown` work with this image as background.
    /// `image` becomes owned by the UIDropdown.
    /// This also disable text display.
    /// Should be called just after construction.
    void setImage(OwnedImage!RGBA image)
    {
        _imageEnabled = true;
        textEnabled = false;
        _image = image;
        _imageResized = mallocNew!(OwnedImage!RGBA);
    }

    ~this()
    {
        if (_image !is null)
        {
            destroyFree(_image);
            _image = null;
        }
        if (_imageResized !is null)
        {
            destroyFree(_imageResized);
            _imageResized = null;
        }
        _presetnumber.removeListener(this);

    }

    override void onFocusExit()
    {        
        // close when clicking elsewhere
        setOpened(false);
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseY = y;
        setDirtyWhole(); // in case hovered element has changed
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override bool contains(int x, int y)
    {
        return super.contains(x, y) && (itemAtPoint(y) != -1);
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        int itemClicked = itemAtPoint(y);
        bool someItemWasClicked = itemClicked != -1;
        string s;

        // ALT+click => set to default
        if (mstate.altPressed)
        {            
            if (someItemWasClicked)
            {
                _presetnumber.beginParamEdit();
                _presetnumber.setFromGUI(_presetnumber.defaultValue());
                _presetnumber.endParamEdit();
                setOpened(false);
                return Click.startDrag;
            }
        }

        if (_opened)
        {
            // click on value => close menu and set parameter
            if (itemClicked != -1)
            {
                // select/highlight the menu item selected
                _presetnumber.beginParamEdit();
                _presetnumber.setFromGUI(itemClicked + _presetnumber.minValue());
                _presetnumber.endParamEdit();
                // we could use the array to put the preset name as well ?
                // nope (a pitty) as we have to convert float to string :-(
                
                // set the values for each parameters given by _pluginparametersarray
                int j = itemClicked + _presetnumber.minValue();
                for (int i = 1; i < _pluginparametersarray.length; ++i)  // 0 is the preset menu itself :)
                {
                    // preset loads (the 1 in the brackest should set to i and move from 1 to maxnbrofparameters)
                    s = typeid(_pluginparametersarray[i]).name; // 10 cortex on/off 
                    //debugLogf("-- %d --- %s",itemClicked,s.ptr);
                
                    if ((s=="dplug.client.params.GainParameter")||
                        (s=="dplug.client.params.LinearFloatParameter")||
                        (s=="dplug.client.params.LogFloatParameter"))
                    {    
                        FloatParameter _paramgeneric = cast(FloatParameter)_pluginparametersarray[i];  
                        _paramgeneric.addListener(this);
                        _paramgeneric.beginParamEdit();
                        float pvalue = cast(float)presetvalues_row1[j][i]; 
                        _paramgeneric.setFromGUI(pvalue); 
                        _paramgeneric.endParamEdit();
                        _paramgeneric.removeListener(this);
                    } else 
                    if (s=="dplug.client.params.BoolParameter")
                    {    
                        BoolParameter _paramgeneric = cast(BoolParameter)_pluginparametersarray[i];
                        _paramgeneric.addListener(this);
                        _paramgeneric.beginParamEdit();
                        bool pvalue = cast(bool)presetvalues_row1[j][i];  
                        _paramgeneric.setFromGUI(pvalue); 
                        _paramgeneric.endParamEdit();
                        _paramgeneric.removeListener(this);
                    }
                    else 
                    if (s=="dplug.client.params.EnumParameter")
                    {    
                        EnumParameter _paramgeneric = cast(EnumParameter)_pluginparametersarray[i];
                        _paramgeneric.addListener(this);
                        _paramgeneric.beginParamEdit();
                        int pvalue = cast(int)presetvalues_row1[j][i]; 
                        _paramgeneric.setFromGUI(pvalue); 
                        _paramgeneric.endParamEdit();
                        _paramgeneric.removeListener(this);
                    } 
                
                } // end read the values in a row

            }
            setOpened(false);
            return Click.startDrag;
        }
        else
        {
            if (someItemWasClicked)
            {
                setOpened(true);
                return Click.startDrag;
            }
            else
                return Click.unhandled; // not expanded, so no click recorded
        }
    }

    override void reflow()
    {
        if (_imageResized !is null)
        {
            int HITEM = getHeightByItem();
            int numChoices = _presetnumber.numValues();
            int resHeight = HITEM * numChoices;
            _imageResized.size(position.width, resHeight);
            ImageResizer* resizer = context.globalImageResizer;
            resizer.resizeImage_sRGBWithAlpha(_image.toRef(), _imageResized.toRef());
        }
    }

    override void onDrawBufferedRaw(ImageRef!RGBA rawMap,ImageRef!L8 opacity) 
    {
        int width = _position.width;
        int height = _position.height;

        int heightByItem = getHeightByItem();
        int numChoices = _presetnumber.numValues();
        int itemsToDraw = _opened ? numChoices : 1;

        bool mouseOver = isMouseOver();
        int itemPointed = itemAtPoint(_lastMouseY);
        int current = currentItem();
          
        for (int i = 0; i < itemsToDraw; ++i)
        {
            int rx = 0;
            int ry = i * heightByItem;

            bool thisItemIsSelected = mouseOver && ( itemPointed == i );
            bool thisItemIsCurrent = (current == i);

            // background
            RGBA colorLit = thisItemIsSelected ? menuColorSelected : menuColor;
            if (thisItemIsCurrent && _opened)
                colorLit = menuColorCurrent;

            if (!_opened && mouseOver && (itemPointed == current))
                colorLit = menuColorCurrent;

            if (thisItemIsSelected && _opened)
                colorLit = menuColorSelected;
            ubyte globalAlpha = colorLit.a;
            rawMap.aaFillRectFloat(rx, ry, rx + width, ry + heightByItem, colorLit, 1.0f);

            if (_imageEnabled)
            {
                int indexInImage = _opened ? i : current;
                box2i itemRectInImage = rectangle(0, indexInImage * heightByItem, width, heightByItem);
                ImageRef!RGBA imageSource = _imageResized.toRef.cropImageRef(itemRectInImage);
                ImageRef!RGBA imageDest = rawMap.cropImageRef(rectangle(rx, ry, width, heightByItem));
                imageSource.blendInto(imageDest);
            }

            if (textEnabled)
            {
                // draw centered text in each item
                // item #0 is shows the current value
                string label = _opened ? _labels[i] : _labels[current];
                float textX = rx + width * 0.5f;
                float textY = ry + heightByItem * 0.5f;
                RGBA textCol = textColor;//(thisItemSelected || isFirst) ? textColorSelected : textColor;
                rawMap.fillText(_font, label, textSizePx, _letterSpacing, textCol, textX, textY);
            }

            opacity.fillRect(rx, ry, rx + width, ry + heightByItem, L8(globalAlpha));
        }

        for (int i = itemsToDraw; i < numChoices; ++i)
        {
            int rx = 0;
            int ry = i * heightByItem;
            opacity.fillRect(rx, ry, rx + width, ry + heightByItem, L8(0));
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

    override void onBeginParameterHover(Parameter sender)
    {
    }

    override void onEndParameterHover(Parameter sender)
    {
    }


private:
    IntegerParameter _presetnumber; // the menu of presets index is 0
    Parameter _paramgeneric;
    Parameter[] _pluginparametersarray;
    Font _font;
    float _letterSpacing = 0.0f;

    // if _opened == false, we only draw the current value
    // if _opened == true, we draw all values in order
    bool _opened = false;

    int _lastMouseY = 0;
    const(string[]) _labels;

    bool _imageEnabled = false;    
    OwnedImage!RGBA _image = null;
    OwnedImage!RGBA _imageResized = null;

    final int getHeightByItem() pure const nothrow @nogc
    {
        float numChoices = _presetnumber.numValues();
        return cast(int)(_position.height / numChoices);
    }

    // return: index of label that is current
    final int currentItem()
    {
        return _presetnumber.value() - _presetnumber.minValue();
    }

    // -1 => no item
    // 0 to param.numValues()-1 => value item
    final int itemAtPoint(float y) nothrow @nogc
    {
        int row = cast(int)(y / getHeightByItem());
        if (_opened)
        {
            if (row < 0) 
                return -1;
            if (row >= _presetnumber.numValues()) 
                return -1;
            return row;           
        }
        else
        {
            if (row == 0)
                return currentItem;
            else
                return -1;
        }
    }

    void setOpened(bool opened)
    {
        if (_opened != opened)
        {
            _opened = opened;
            setDirtyWhole();
        }
    }
}


/// Blits a view onto another, with alpha-blending.
/// The views must have the same size.
/// PERF: optimize that
void blendInto(ImageRef!RGBA srcView, ImageRef!RGBA dstView) nothrow @nogc
{
    static ubyte blendByte(ubyte a, ubyte b, ubyte f) nothrow @nogc
    {
        int sum = ( f * a + b * (cast(ubyte)(~cast(int)f)) ) + 127;
        return cast(ubyte)(sum / 255 );
    }

    alias COLOR = RGBA;
    assert(srcView.w == dstView.w && srcView.h == dstView.h, "View size mismatch");
    foreach (y; 0..srcView.h)
    {
        COLOR* srcScan = srcView.scanline(y).ptr;
        COLOR* dstScan = dstView.scanline(y).ptr;

        foreach (x; 0..srcView.w)
        {
            ubyte alpha = srcScan[x].a;
            dstScan[x].r = blendByte(srcScan[x].r, dstScan[x].r, alpha);
            dstScan[x].g = blendByte(srcScan[x].g, dstScan[x].g, alpha);
            dstScan[x].b = blendByte(srcScan[x].b, dstScan[x].b, alpha);
            dstScan[x].a = blendByte(srcScan[x].a, dstScan[x].a, alpha);
        }
    }
}
/+
void blendWith(ImageRef!RGBA src, ImageRef!RGBA dst, int x, int y)
{
    // find destination rect in dst
    int minX = x;
    if (minX >= dst.w) return;

    int minY = y;
    
    if (minY >= dst.h) return;
    if (minX < 0) minX = 0;
    if (minX < 0) minX = 0;
    int w = src.w;
    if (w > dst.w


	src.blitTo(dst.cropImageRef(x, y, x+src.w, y+src.h));
}+/

protected :
// NUMBER OF PARMETERS FOLLOWED BY NUMBER OF PRESETS
float[23][5] presetvalues_row1=[
[1,-4,1,1,20,1,20,0,15,0,0,0,2200,0,0,0,1,12050,2,32,0,80,0],
[2,-4,1,1,25,1,20,0,15,1,1,5,8000,4,2,0,1,12050,2,32,0,100,0],
[4,-4,1,1,20,1,20,0,10,0,0,-12,4000,0,-6,1,1,3700,1.5,30,1,80,0],
[6,-4,1,1,50,1,65,0,20,1,0,-12,7200,-4,0,0,1,3300,2,32,1,80,0],
[8,-4,1,1,20,1,25,0,15,1,1,2,350,2,2,1,1,12050,1.75,30,1,100,0],
];


// HELP MAPPING ------------------ This is just an exemple !
/*  parameter index -- map or not --- description
    0    EnumParameter(param_Presets, "Presets",presetsArray, 0) );

    1    GainParameter(param_Input, "Input gain", 0.0f, -4.0f) );
    2    EnumParameter(param_Oversampling, "Oversampling rate",oversamplingtypeArray, 2) );
            // TREBLE TUBE
    3    BoolParameter(param_TubeTrebleonoff, "Hype onoff", true) );
    4    LinearFloatParameter(param_TubeTreble, "Hype amount","%",0.0f, 100.0f, 25.0f) );
            // BASS TUBE
    5    BoolParameter(param_TubeBassonoff, "Stone onoff", true) );
    6    LinearFloatParameter(param_TubeBass, "Stone amount","%",0.0f, 100.0f, 20.0f) );
            // Taratube :-)
    7    BoolParameter(param_Tubetaratubeonoff, "Badtrip onoff",false) );
    8    LinearFloatParameter(param_Tubetaratubeamt, "Badtripe amount","%",0.0f, 100.0f, 20.0f) );
            // Extra Boost BAXANDALL
    9    BoolParameter(param_baxandallboost, "Exciter", false) );
            // EQ 3 bands (fixed 110hz, 300hz to 7200hz, fixed 10000hz)
    10    BoolParameter(param_eqonoff, "Cortex EQ. on/off", false) );
    11    LinearFloatParameter(param_lowshelfGain, "Low Gain", "db", -12.0f, 12.0f, 0.0f) );
    12    LogFloatParameter(param_midpeakFreq, "Mid. Freq.","hz", 300.0f,7200.0f, 2200.0f));
    13    LinearFloatParameter(param_midpeakGain, "Mid. Gain","db", -12.0f, 12.0f, 0.0f) );
    14    LinearFloatParameter(param_highshelfGain, "High Gain","db", -12.0f, 12.0f, 0.0f) );
            // Moog LPF Filter 
    15    BoolParameter(param_moogLPFonoff, "Dope LP On/Off",false) );
    16    EnumParameter(param_moogLPFoversamplingrate, "LP Mode",lpfiltertypeArray, 1) );
    17    LinearFloatParameter(param_moogLPFFrequency, "LP Cutoff", "hz", 300.0f, 12050.0f, 12050.0f));
    18    LinearFloatParameter(param_moogLPFResonance, "LP Resonance", "", 0.01f, 3.5f, 2.0f));
    19    GainParameter(param_moogLPFDrive, "LP Gain", 48.0f, 32.0f));
            // CLIP
    20    BoolParameter(param_Clip, "Clipper",false) );
            // MIX
    21    LinearFloatParameter(param_Mix, "Mix", "%", 0.0f, 100.0f, 100.0f));
    22    GainParameter(param_Output, "Output gain", 6.0f, 0.0f) );

// in total 23 parameters :-)

*/
