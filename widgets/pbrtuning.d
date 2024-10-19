/**
Tune PBR with Wren.

Copyright: Guillaume Piolat 2024.
License:   BSL-1.0
*/
module auburn.gui.pbrtuning;

import dplug.core;
import dplug.gui;

// How to use: instantiate and reflow it on whole screen.
class UIPBRTuning : UIElement
{
public:
nothrow:
@nogc:

    @ScriptProperty
    {
        /// Global scaling for ALL lights. Amplifier.
        float lightQuantity = 1.0f;

        // FUTURE: there is no Wren support for vec2f and vec3f unfortunately

        float light1 = 1.0f;
        float light1_R = 0.168;
        float light1_G = 0.168;
        float light1_B = 0.168;

        float light2 = 1.0f;
        float light2Dir_X = -0.5f;
        float light2Dir_Y = 1.0f;
        float light2Dir_Z = 0.23f;
        float light2_R = 0.3116;
        float light2_G = 0.3116;
        float light2_B = 0.3936;

        float light3 = 1.0f;
        float light3Dir_X = 0.0f;
        float light3Dir_Y = 1.0f;
        float light3Dir_Z = 0.1f;
        float light3_R = 0.12f;
        float light3_G = 0.12f;
        float light3_B = 0.12f;

        float ambientLight = 0.03f;
        float skyboxAmount = 0.4;

        /*
        Graillon 3 values:, maybe better default
        double lightQuantity = 0.888   ;     
        double light1   = 1.315;
        double light1_R = 0.1834;
        double light1_G = 0.1729;
        double light1_B = 0.1834;
        double light2 = 0.93;
        double light2Dir_X = -0.15;
        double light2Dir_Y = 1.0;
        double light2Dir_Z = 0.209;
        double light2_R = 0.31748;
        double light2_G = 0.30348;
        double light2_B = 0.33508;
        double light3 = 1.14;
        double light3Dir_X = 0.0;
        double light3Dir_Y = 1.0;
        double light3Dir_Z = 0.1;
        double light3_R = 0.141;
        double light3_G = 0.127;
        double light3_B = 0.12;
        double ambientLight = -0.019;
        double skyboxAmount = 0.61;
        */
    }

    this(UIContext context, PBRCompositor compositor)
    {
        super(context, flagPBR);
        _compositor = compositor;
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, 
                            ImageRef!L16 depthMap, 
                            ImageRef!RGBA materialMap,
                            box2i[] dirtyRects)
    {
        // Note: do nothing, however modify PBR settings
        // so that the next compositing changes everything
        float globalLightFactor = 1.4f * lightQuantity;
        _compositor.light1Color = vec3f(light1_R, light1_G, light1_B) * light1 * globalLightFactor;
        _compositor.light2Dir   = vec3f(light2Dir_X, light2Dir_Y, light2Dir_Z).normalized;
        _compositor.light2Color = vec3f(light2_R, light2_G, light2_B) * light2 * globalLightFactor;
        _compositor.light3Dir   = vec3f(light3Dir_X, light3Dir_Y, light3Dir_Z).normalized;
        _compositor.light3Color = vec3f(light3_R, light3_G, light3_B) * light3 * globalLightFactor;
        _compositor.ambientLight = ambientLight * globalLightFactor;
        _compositor.skyboxAmount = skyboxAmount * globalLightFactor;
    }
 
private:
    PBRCompositor _compositor;
}

