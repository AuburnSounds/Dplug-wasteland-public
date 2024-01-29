/**
HFixed menu. 2.. 3 ... x slots aligned horizontaly

-------------------------------
| item1 | item2 | item3 | ... |
-------------------------------
always open :-)
The user point its mouse on the item area ... 

Original Copyright: Copyright Guillaume Piolat 2015-2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)

Add-on to get this FixeMenu lib : Stephane Ribas (SMAOLAB)

Note that use an image in the menu is not working yet :(
Only text accepted for the moment.

*/

/* 
Instructions / exemple

Oversampling
----------------------
| OFF | X2 | X4 | X8 |
----------------------

1- In gui.d, declare :
// oversampling off x2 x4 ...
UIFixedmenu oversampling_type;
enum oversamplingtype_value {
  OFF,
  X2,
  X4,
  X8,
}
static immutable oversamplingtypeArray = [__traits(allMembers, oversamplingtype_value)];

2- then, in gui.d, write the following code : 
...
this(BlablablablaClient client)
{
  _client = client;
...

  // oversampling
  oversampling_type= mallocNew!UIFixedmenu(context(), _font, cast(IntegerParameter) _client.param(param_Oversampling), oversamplingtypeArray);
  addChild(oversampling_type);

...
}

3- then ,in gui.d, write the following code : 
...
override void reflow()
{
  super.reflow();
  ...
  
  oversampling_type.position = rectangle(665, 540, 90, 25).scaleByFactor(S);

  ...
}

4- in the main.d, you should read the oversampling parameter, put somewhere in your code (in the maind.d)

_oversamplingtype=readParam!int(param_Oversampling);

if (_oversamplingtype==0) then ... 
if (_oversamplingtype==1) then ...

5- that's all :-)

6- Extra tip:
param_Oversampling can be an enum, and like this, you DAW will display a text instead of an integer.

exemple:
...
params.pushBack(mallocNew!EnumParameter(param_Oversampling, "Oversampling rate",oversamplingtypeArray, 2) );
...
/// type of oversampling value.
enum oversamplingtype_value {
    x1,
    x2,
    x4,
    x8,
}
static immutable oversamplingtypeArray = [__traits(allMembers, oversamplingtype_value)];
...

7- really, that's the end ! enjoy the code below...

*/

module fixedmenu;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.gui.bufferedelement;
import dplug.client.params;
import dplug.graphics.resizer;

class UIFixedmenu : UIBufferedElementRaw, IParameterListener
{
public:
nothrow:
@nogc:

    RGBA menuColor = RGBA(184, 179, 169, 150); // background
    RGBA menuColorSelected = RGBA(165, 35, 35, 240);
    RGBA menuColorCurrent = RGBA(145, 127, 104, 240);

    bool textEnabled = true;
    float textSizePx = 18.0f;
    RGBA textColor = RGBA(10, 10, 10, 200);
    RGBA textColorSelected = RGBA(210, 210, 210, 240);


    this(UIContext context, Font font, IntegerParameter param, const(string[]) labels)
    {
        super(context, flagRaw);

        _param = param;
        _param.addListener(this);
        _font = font;
        _labels = labels;
        assert(_param.numValues() == labels.length);
    }

    /// Make this `UIDropdown` work with this image as background.
    /// `image` becomes owned by the UIFixemenu.
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
        _param.removeListener(this);
    }

    override void onFocusExit()
    {
        // close when clicking elsewhere
        //setOpened(false);
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        _lastMouseY = y;
        _lastMouseX = x; // SMAO, to get it horizontal

        setDirtyWhole(); // in case hovered element has changed
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

    override bool contains(int x, int y)
    {
        //return super.contains(x, y) && (itemAtPoint(y) != -1);
        return super.contains(x, y) && (itemAtPointX(x) != -1);// to get it horizontal
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        //int itemClicked = itemAtPoint(y);
        int itemClicked = itemAtPointX(x); //to get it horizontal
        bool someItemWasClicked = itemClicked != -1;

        // ALT+click => set to default
        if (mstate.altPressed)
        {
            if (someItemWasClicked)
            {
                _param.beginParamEdit();
                _param.setFromGUI(_param.defaultValue());
                _param.endParamEdit();
                //setOpened(false);
                setOpened(true); // SMAO, to always have the menu open, that's the trick to get this widget effet of a fixedmenu
                return true;
            }
        }

        if (_opened)
        {
            // click on value => close menu and set parameter
            if (itemClicked != -1)
            {
                _param.beginParamEdit();
                _param.setFromGUI(itemClicked + _param.minValue());
                _param.endParamEdit();
            }
            //setOpened(false);
            setOpened(true); // SMAO, to leave the menu open...
            return true;
        }
        else
        {
            if (someItemWasClicked)
            {
                setOpened(true);
                return true;
            }
            else
                return false; // not expanded, so no click recorded
        }
    }

    override void reflow()
    {
        /*if (_imageResized !is null)
        {
            int HITEM = getHeightByItem();
            int numChoices = _param.numValues();
            int resHeight = HITEM * numChoices;
            _imageResized.size(position.width, resHeight);
            ImageResizer* resizer = context.globalImageResizer;
            resizer.resizeImage_sRGBWithAlpha(_image.toRef(), _imageResized.toRef());
        }*/
        // arrf, image is not working correctly for the moment...
        if (_imageResized !is null)
        {
            int HITEM = getWidthByItem();
            int numChoices = _param.numValues();
            int resHeight = HITEM * numChoices;
            _imageResized.size(resHeight, position.height );
            ImageResizer* resizer = context.globalImageResizer;
            resizer.resizeImage_sRGBWithAlpha(_image.toRef(), _imageResized.toRef());
        }
    }

    override void onDrawBufferedRaw(ImageRef!RGBA rawMap,ImageRef!L8 opacity)
    {
        int width = _position.width;
        int height = _position.height;

        int heightByItem = getHeightByItem();
        int widthByItem = getWidthByItem();

        int numChoices = _param.numValues();
        int itemsToDraw = _opened ? numChoices : 1;

        bool mouseOver = isMouseOver();
        int itemPointed = itemAtPointX(_lastMouseX);// in order to get the mouse location horizontally //itemAtPoint(_lastMouseY);
        int current = currentItem();

        for (int i = 0; i < itemsToDraw; ++i)
        {
            int rx = i * widthByItem;//0;
            int ry = 0;//i * widthByItem; to get horizontal...

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
            //rawMap.aaFillRectFloat(rx, ry, rx + width, ry + heightByItem, colorLit, 1.0f);
            //rawMap.aaFillRectFloat(rx, ry, rx + widthByItem, ry + height, colorLit, 1.0f);
            rawMap.aaFillRectFloat(rx, ry, rx + widthByItem, ry + height, colorLit, 1.0f); // to get the horizontal menu

            if (_imageEnabled) // image not displayed correctly
            {
                int indexInImage = _opened ? i : current;
                box2i itemRectInImage = rectangle(0, indexInImage * heightByItem, widthByItem, heightByItem);
                ImageRef!RGBA imageSource = _imageResized.toRef.cropImageRef(itemRectInImage);
                ImageRef!RGBA imageDest =
                rawMap.cropImageRef(rectangle(rx, ry,
                  widthByItem, heightByItem));
                imageSource.blendInto(imageDest);
            }

            if (textEnabled)
            {
                // draw centered text in each item
                // item #0 is shows the current value
                string label = _opened ? _labels[i] : _labels[current];
                float textX = rx + widthByItem * 0.5f;
                //float textY = ry + heightByItem * 0.5f; to get horizontal
                float textY = ry + height * 0.5f;
                RGBA textCol = textColor;//(thisItemSelected || isFirst) ? textColorSelected : textColor;
                rawMap.fillText(_font, label, textSizePx, 0, textCol, textX, textY);
            }

            opacity.fillRect(rx, ry, rx + widthByItem, ry + height, L8(globalAlpha));
        }

        for (int i = itemsToDraw; i < numChoices; ++i)
        {
          //  int rx = 0;
          //  int ry = i * heightByItem;
              int rx = i*widthByItem; // to get horizontal
              int ry = 0;

            opacity.fillRect(rx, ry, rx + widthByItem, ry + height, L8(0));
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



private:
    IntegerParameter _param;
    Font _font;

    // if _opened == false, we only draw the current value
    // if _opened == true, we draw all values in order
    bool _opened = true; // SMAO, to get by default the menu open

    int _lastMouseY = 0;
    int _lastMouseX = 0; // SMAO

    const(string[]) _labels;

    bool _imageEnabled = false;
    OwnedImage!RGBA _image = null;
    OwnedImage!RGBA _imageResized = null;

    final int getHeightByItem() pure const nothrow @nogc
    {
        float numChoices = _param.numValues();
        return cast(int)(_position.height / numChoices);
    }

    // SMAO
    final int getWidthByItem() pure const nothrow @nogc
    {
        float numChoices = _param.numValues();
        return cast(int)(_position.width / numChoices);
    }

    // return: index of label that is current
    final int currentItem()
    {
        return _param.value() - _param.minValue();
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
            if (row >= _param.numValues())
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

    // SMAO, to catch the mouse on X axes..
    // -1 => no item
    // 0 to param.numValues()-1 => value item
    final int itemAtPointX(float x) nothrow @nogc
    {
        int row = cast(int)(x / getWidthByItem());
        if (_opened)
        {
            if (row < 0)
                return -1;
            if (row >= _param.numValues())
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
