/**
Drop down menu.

Copyright: Copyright Guillaume Piolat 2015-2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.dropdown;

import std.math;
import dplug.core.math;
import dplug.gui.element;
import dplug.gui.bufferedelement;
import dplug.client.params;
import dplug.graphics.resizer;

class UIDropdown : UIBufferedElementRaw, IParameterListener
{
public:
nothrow:
@nogc:

    RGBA menuColor = RGBA(13, 10, 7, 240);
    RGBA menuColorSelected = RGBA(145, 127, 104, 240);
    RGBA menuColorCurrent = RGBA(100, 87, 68, 240);

    bool textEnabled = true;
    float textSizePx = 13.0f;
    RGBA textColor = RGBA(210, 210, 210, 230);
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
        _param.removeListener(this);
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

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        int itemClicked = itemAtPoint(y);
        bool someItemWasClicked = itemClicked != -1;

        // ALT+click => set to default
        if (mstate.altPressed)
        {            
            if (someItemWasClicked)
            {
                _param.beginParamEdit();
                _param.setFromGUI(_param.defaultValue());
                _param.endParamEdit();
                setOpened(false);
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
            setOpened(false);
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
        if (_imageResized !is null)
        {
            int HITEM = getHeightByItem();
            int numChoices = _param.numValues();
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
        int numChoices = _param.numValues();
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
                rawMap.fillText(_font, label, textSizePx, 0, textCol, textX, textY);
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

 

private:
    IntegerParameter _param;
    Font _font;

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
        float numChoices = _param.numValues();
        return cast(int)(_position.height / numChoices);
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