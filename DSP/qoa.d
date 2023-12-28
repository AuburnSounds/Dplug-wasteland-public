/**

Copyright (c) 2023, Dominic Szablewski - https://phoboslab.org
SPDX-License-Identifier: MIT

QOA - The "Quite OK Audio" format for fast, lossy audio compression

*/
/*
MIT License

Copyright (c) 2022-2023 Dominic Szablewski
Copyright (c) 2023 Guillaume Piolat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
/**
Note: was modified to act as an audio effect.
Note: clip to -1..1 before entry!!!
It sounds a bit like a 90's game, perhaps a truer ADPCM codec would sound even more like that.
You will hear a bit of a "Descent II" feeling if you put it on industrial techno ^^.
*/
module qoa;

import core.stdc.stdlib: malloc, free;

import dplug.dsp.delayline;

nothrow @nogc:

enum int QOA_LMS_LEN = 4;
enum int QOA_MAX_CHANNELS = 2;

uint QOA_FRAME_SIZE(uint channels, uint slices) pure
{
    return 8 + QOA_LMS_LEN * 4 * channels + 8 * slices * channels;
}

struct qoa_lms_t
{
    int[QOA_LMS_LEN] history;
    int[QOA_LMS_LEN] weights;
}

public struct qoa_desc
{
    qoa_lms_t[QOA_MAX_CHANNELS] lms;
}

alias qoa_uint64_t = ulong;

/* The quant_tab provides an index into the dequant_tab for residuals in the
range of -8 .. 8. It maps this range to just 3bits and becomes less accurate at 
the higher end. Note that the residual zero is identical to the lowest positive 
value. This is mostly fine, since the qoa_div() function always rounds away 
from zero. */
static immutable int[17] qoa_quant_tab =
[
    7, 7, 7, 5, 5, 3, 3, 1, /* -8..-1 */
    0,                      /*  0     */
    0, 2, 2, 4, 4, 6, 6, 6  /*  1.. 8 */
];


/* We have 16 different scalefactors. Like the quantized residuals these become
less accurate at the higher end. In theory, the highest scalefactor that we
would need to encode the highest 16bit residual is (2**16)/8 = 8192. However we
rely on the LMS filter to predict samples accurately enough that a maximum 
residual of one quarter of the 16 bit range is sufficient. I.e. with the 
scalefactor 2048 times the quant range of 8 we can encode residuals up to 2**14.

The scalefactor values are computed as:
scalefactor_tab[s] <- round(pow(s + 1, 2.75)) */

static immutable int[16] qoa_scalefactor_tab =
[
    1, 7, 21, 45, 84, 138, 211, 304, 421, 562, 731, 928, 1157, 1419, 1715, 2048
];


/* The reciprocal_tab maps each of the 16 scalefactors to their rounded 
reciprocals 1/scalefactor. This allows us to calculate the scaled residuals in 
the encoder with just one multiplication instead of an expensive division. We 
do this in .16 fixed point with integers, instead of floats.

The reciprocal_tab is computed as:
reciprocal_tab[s] <- ((1<<16) + scalefactor_tab[s] - 1) / scalefactor_tab[s] */

static immutable int[16] qoa_reciprocal_tab = 
[
    65536, 9363, 3121, 1457, 781, 475, 311, 216, 156, 117, 90, 71, 57, 47, 39, 32
];


/* The dequant_tab maps each of the scalefactors and quantized residuals to 
their unscaled & dequantized version.

Since qoa_div rounds away from the zero, the smallest entries are mapped to 3/4
instead of 1. The dequant_tab assumes the following dequantized values for each 
of the quant_tab indices and is computed as:
float dqt[8] = {0.75, -0.75, 2.5, -2.5, 4.5, -4.5, 7, -7};
dequant_tab[s][q] <- round(scalefactor_tab[s] * dqt[q]) */

static immutable int[8][16] qoa_dequant_tab = 
[
    [   1,    -1,    3,    -3,    5,    -5,     7,     -7],
    [   5,    -5,   18,   -18,   32,   -32,    49,    -49],
    [  16,   -16,   53,   -53,   95,   -95,   147,   -147],
    [  34,   -34,  113,  -113,  203,  -203,   315,   -315],
    [  63,   -63,  210,  -210,  378,  -378,   588,   -588],
    [ 104,  -104,  345,  -345,  621,  -621,   966,   -966],
    [ 158,  -158,  528,  -528,  950,  -950,  1477,  -1477],
    [ 228,  -228,  760,  -760, 1368, -1368,  2128,  -2128],
    [ 316,  -316, 1053, -1053, 1895, -1895,  2947,  -2947],
    [ 422,  -422, 1405, -1405, 2529, -2529,  3934,  -3934],
    [ 548,  -548, 1828, -1828, 3290, -3290,  5117,  -5117],
    [ 696,  -696, 2320, -2320, 4176, -4176,  6496,  -6496],
    [ 868,  -868, 2893, -2893, 5207, -5207,  8099,  -8099],
    [1064, -1064, 3548, -3548, 6386, -6386,  9933,  -9933],
    [1286, -1286, 4288, -4288, 7718, -7718, 12005, -12005],
    [1536, -1536, 5120, -5120, 9216, -9216, 14336, -14336],
];


/* The Least Mean Squares Filter is the heart of QOA. It predicts the next
sample based on the previous 4 reconstructed samples. It does so by continuously
adjusting 4 weights based on the residual of the previous prediction.

The next sample is predicted as the sum of (weight[i] * history[i]).

The adjustment of the weights is done with a "Sign-Sign-LMS" that adds or
subtracts the residual to each weight, based on the corresponding sample from 
the history. This, surprisingly, is sufficient to get worthwhile predictions.

This is all done with fixed point integers. Hence the right-shifts when updating
the weights and calculating the prediction. */

int qoa_lms_predict(qoa_lms_t *lms) pure
{
    int prediction = 0;
    for (int i = 0; i < QOA_LMS_LEN; i++) 
    {
        prediction += lms.weights[i] * lms.history[i];
    }
    return prediction >> 13;
}

void qoa_lms_update(qoa_lms_t *lms, int sample, int residual) pure
{
    int delta = residual >> 4;
    for (int i = 0; i < QOA_LMS_LEN; i++) 
    {
        lms.weights[i] += lms.history[i] < 0 ? -delta : delta;
    }

    for (int i = 0; i < QOA_LMS_LEN-1; i++) 
    {
        lms.history[i] = lms.history[i+1];
    }
    lms.history[QOA_LMS_LEN-1] = sample;
}


/* qoa_div() implements a rounding division, but avoids rounding to zero for 
small numbers. E.g. 0.1 will be rounded to 1. Note that 0 itself still 
returns as 0, which is handled in the qoa_quant_tab[].
qoa_div() takes an index into the .16 fixed point qoa_reciprocal_tab as an
argument, so it can do the division with a cheaper integer multiplication. */

int qoa_div(int v, int scalefactor) pure
{
    int reciprocal = qoa_reciprocal_tab[scalefactor];
    int n = (v * reciprocal + (1 << 15)) >> 16;
    n = n + ((v > 0) - (v < 0)) - ((n > 0) - (n < 0)); /* round away from 0 */
    return n;
}

int qoa_clamp(int v, int min, int max) pure
{
    if (v < min) { return min; }
    if (v > max) { return max; }
    return v;
}

int qoa_clamp_s16(int v) pure
{
    if (cast(uint)(v + 32768) > 65535) 
    {
        if (v < -32768) { return -32768; }
        if (v >  32767) { return  32767; }
    }
    return v;
}

/// Simulates QOA encoder and decoder, but with only 20 samples of latency.
struct QOAEncodeDecode
{
nothrow @nogc:
    enum MAX_CHANNELS = 2;
    enum MAX_BLOB = 20;

    void initialize(int channels, int maxFrames)
    {
        _channels = channels;

        for (int c = 0; c < channels; c++) 
        {
            /* Set the initial LMS weights to {0, 0, -1, 2}. This helps with the 
            prediction of the first few ms of a file. */
            _lms[c].weights[0] = 0;
            _lms[c].weights[1] = 0;
            _lms[c].weights[2] = -(1<<13);
            _lms[c].weights[3] =  (1<<14);

            /* Explicitly set the history samples to 0, as we might have some
            garbage in there. */
            for (int i = 0; i < QOA_LMS_LEN; i++)
            {
                _lms[c].history[i] = 0;
            }

            _inputDelay[c].initialize(maxFrames + 1 + MAX_BLOB);
        }

        _blobIndex = MAX_BLOB;
    }

    int latencySamples()
    {
        return MAX_BLOB; // TODO: MAX_BLOB or MAX_BLOB-1???
    }

    void nextBuffer(float** inoutSamples, int frames, int blobSize) // Note: 20 sounds best, as in original codec
    {
        assert(blobSize >= 1 && blobSize <= MAX_BLOB);

        for (int c = 0; c < _channels; c++) 
        {
            _inputDelay[c].feedBuffer(inoutSamples[c][0..frames]);
        }        

        int n = 0;
        while (n < frames)
        {
            if (_blobIndex >= blobSize) // empty (note: changing blob size will desync things, which is OK)
            {
                // Simulates encoding+decoding
                for (int c = 0; c < _channels; c++) 
                {
                    const(float*) readPtr = _inputDelay[c].readPointer() - MAX_BLOB - frames + 1 + n;

                    /* Brute for search for the best scalefactor. Just go through all
                    16 scalefactors, encode all samples for the current slice and 
                    meassure the total squared error. */
                    qoa_uint64_t best_error = -1;
                    qoa_uint64_t best_slice;
                    qoa_lms_t best_lms;

                    for (int scalefactor = 0; scalefactor < 16; scalefactor++) 
                    {
                        /* We have to reset the LMS state to the last known good one
                        before trying each scalefactor, as each pass updates the LMS
                        state when encoding. */
                        qoa_lms_t lms = _lms[c];
                        qoa_uint64_t slice = scalefactor;
                        qoa_uint64_t current_error = 0;

                        for (int k = 0; k < blobSize; ++k) 
                        {
                            int sample = qoa_clamp_s16( cast(int)(readPtr[k] * 32768.0f) ); // TODO: overflow

                            int predicted = qoa_lms_predict(&lms);

                            int residual = sample - predicted;
                            int scaled = qoa_div(residual, scalefactor);
                            int clamped = qoa_clamp(scaled, -8, 8);
                            int quantized = qoa_quant_tab[clamped + 8];
                            int dequantized = qoa_dequant_tab[scalefactor][quantized];
                            int reconstructed = qoa_clamp_s16(predicted + dequantized);

                            long error = (sample - reconstructed);
                            current_error += error * error;
                            if (current_error > best_error) 
                            {
                                break;
                            }
                            qoa_lms_update(&lms, reconstructed, dequantized);
                            slice = (slice << 3) | quantized;
                        }

                        if (current_error < best_error) 
                        {
                            best_error = current_error;
                            best_slice = slice;
                            best_lms = lms;
                        }
                    }
                    _lms[c] = best_lms;

                    // Decode same channel now
                    {
                        int scalefactor = (best_slice >> 60) & 0xf;
                        for (int k = 0; k < blobSize; ++k) 
                        {
                            int predicted = qoa_lms_predict(&_lms[c]);
                            int quantized = (best_slice >> 57) & 0x7;
                            int dequantized = qoa_dequant_tab[scalefactor][quantized];
                            int reconstructed = qoa_clamp_s16(predicted + dequantized);
                            _blob[c][k] = (cast(short)reconstructed) / 32768.0f; // yup, no dither here...
                            best_slice <<= 3;
                            qoa_lms_update(&_lms[c], reconstructed, dequantized);

                            _blob[c][k] = readPtr[k];
                        }
                    }
                    
                }
                _blobIndex = 0;
            }

            int take = frames - n;
            if (take > (blobSize-_blobIndex)) 
                take = (blobSize-_blobIndex);
            for (int c = 0; c < _channels; c++) 
            {
                const(float)* pblob = &_blob[c][_blobIndex];
                inoutSamples[c][n..n+take] = pblob[0..take];
            }
            n += take;
            _blobIndex += take;
        }
    }

private:
    int _channels;
    qoa_lms_t[MAX_CHANNELS] _lms;


    float[MAX_BLOB][MAX_CHANNELS] _blob;
    int _blobIndex; // index of first available decoded sample in _blob

    Delayline!float[MAX_CHANNELS] _inputDelay;
}

