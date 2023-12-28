/**
A Raw static layer to display just before color-correcting.
Typical use case is simulating screens. Operates in Raw domain.
Copyright: Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module auburn.gui.rawlayer;

import dplug.gui.bufferedelement;

/// This displays a static image in the Raw layer.
/// The alpha channel is used for compositing with `alpha * image + (1 - alpha) * dest` as formula.
/// Note: you probably want to give it a somewhat high Z offset
class UIRawLayer : UIElement
{
nothrow:
@nogc:
    this(UIContext context, OwnedImage!RGBA image)
    {
        _image = image;
        _imageScaled = mallocNew!(OwnedImage!RGBA)();
        super(context, flagRaw);
    }

    override bool contains(int x, int y)
    {
        return false; // avoid taking mouse over
    }

    override void onDrawRaw(ImageRef!RGBA rawMap,box2i[] dirtyRects) 
    {
        // Lazy resize resources to match actual size.
        {
            int W = position.width;
            int H = position.height;
            if (_imageScaled.w != W || _imageScaled.h != H)
            {
                _imageScaled.size(W, H);
                ImageResizer resizer;
                resizer.resizeImage_sRGBWithAlpha(_image.toRef, _imageScaled.toRef);
            }
        }

        // No resize supported, widget size and image size must be the same
        assert(position.width == _imageScaled.w);
        assert(position.height == _imageScaled.h);

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);

            const int RW = dirtyRect.width;
            const int RH = dirtyRect.height; 
            for (int y = 0; y < RH; ++y)
            {
                RGBA* outRaw = cRaw.scanline(y).ptr;
                RGBA* inImage = _imageScaled.scanline(y + dirtyRect.min.y).ptr + dirtyRect.min.x;
                for (int x = 0; x < RW; ++x)
                {
                    outRaw[x] = blendColor( inImage[x], outRaw[x], inImage[x].a);
                }
            }
        }
    }

    ~this()
    {
        _imageScaled.destroyFree();
    }

private:
    OwnedImage!RGBA _image; // not owned
    OwnedImage!RGBA _imageScaled; // owned
}