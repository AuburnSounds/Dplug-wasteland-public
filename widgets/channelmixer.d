/**
Channel mixer. Like in GIMP, however the results are different and it's best to setup that using Wren instead of GIMP.

Copyright: Guillaume Piolat 2024.
License:   Boost-1.0.
*/
module auburn.gui.channelmixer;


import dplug.math.matrix;

import dplug.core.math;
import dplug.gui.element;

/// Same as GIMP "Channel Mixer", a RGB 3x3 matrix color effect.
/// This is how simple it is to do a post-effect.
class UIChannelMixer : UIElement
{
public:
nothrow:
@nogc:

    @ScriptProperty bool enableMatrix = true;

    // A 3x3 RGB matrix

    @ScriptProperty float R_to_R = 1.0f;
    @ScriptProperty float G_to_R = 0.0f;
    @ScriptProperty float B_to_R = 0.0f;

    @ScriptProperty float R_to_G = 0.0f;
    @ScriptProperty float G_to_G = 1.0f;
    @ScriptProperty float B_to_G = 0.0f;

    @ScriptProperty float R_to_B = 0.0f;
    @ScriptProperty float G_to_B = 0.0f;
    @ScriptProperty float B_to_B = 1.0f;

    @ScriptProperty float R_offset = 0.0f;
    @ScriptProperty float G_offset = 0.0f;
    @ScriptProperty float B_offset = 0.0f;

    this(UIContext context)
    {
        super(context, flagRaw);
    }

    ~this()
    {
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        if (!enableMatrix)
            return;

        foreach(dirtyRect; dirtyRects)
        {
            applyColorMatrix(rawMap.cropImageRef(dirtyRect));
        }
    }

    override bool contains(int x, int y)
    {
        // HACK: this is just a way to avoid taking mouseOver.
        // As this widget is often a top widget,
        // this avoids capturing mouse instead
        // of all below widgets.
        return false;
    }

    // Apply color correction and convert RGBA8 to BGRA8
    void applyColorMatrix(ImageRef!RGBA image) pure nothrow @nogc
    {
        int w = image.w;
        int h = image.h;
        for (int j = 0; j < h; ++j)
        {
            ubyte* scan = cast(ubyte*)image.scanline(j).ptr;

            // PERF: this is awful probably. Should be done with PMADDWD.
            for (int i = 0; i < w; ++i)
            {
                ubyte r = scan[4*i];
                ubyte g = scan[4*i+1];
                ubyte b = scan[4*i+2];
                ubyte a = 255;

                float R = R_offset + R_to_R * r + G_to_R * g + B_to_R * b;
                float G = G_offset + R_to_G * r + G_to_G * g + B_to_G * b;
                float B = B_offset + R_to_B * r + G_to_B * g + B_to_B * b;

                // Convert back to byte.
                short ir = cast(short)(0.5f + R);
                short ig = cast(short)(0.5f + G);
                short ib = cast(short)(0.5f + B);

                if (ir < 0) ir = 0;
                if (ir > 255) ir = 255;
                if (ig < 0) ig = 0;
                if (ig > 255) ig = 255;
                if (ib < 0) ib = 0;
                if (ib > 255) ib = 255;

                scan[4*i]   = cast(ubyte)ir;
                scan[4*i+1] = cast(ubyte)ig;
                scan[4*i+2] = cast(ubyte)ib;
            }
        }
    }

private:
}

