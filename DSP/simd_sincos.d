module simd_sincos;
/*!
    @file sse_mathfun.h

    SIMD (SSE1+MMX or SSE2) implementation of sin, cos, exp and log

   Inspired by Intel Approximate Math library, and based on the
   corresponding algorithms of the cephes math library

   The default is to use the SSE1 version. If you define USE_SSE2 the
   the SSE2 intrinsics will be used in place of the MMX intrinsics. Do
   not expect any significant performance improvement with SSE2.
*/

/* Copyright (C) 2010,2011  RJVB - extensions */
/* Copyright (C) 2007  Julien Pommier

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.

  (this is the zlib license)
*/

import inteli.emmintrin;

// SIMD sin/cos/sincos
// not validated for audio, OK for spectral
// Faster than llvm_cos/llvm_sin even for scalar value

nothrow @nogc:

float _mm_sin_ss(float x) pure @safe
{
    __m128 r = _mm_sin_ps(_mm_set1_ps(x));
    return r.array[0];
}

float _mm_cos_ss(float x) pure @safe
{
    __m128 r = _mm_cos_ps(_mm_set1_ps(x));
    return r.array[0];
}

__m128 _mm_sin_ps(__m128 x) pure @safe
{
  __m128 xmm2 = _mm_setzero_ps();
  __m128 sign_bit = x;
  /* take the absolute value */
  x = _mm_and_ps(x, cast(__m128) _mm_set1_epi32(~0x80000000));

  /* extract the sign bit (upper one) */
  sign_bit = _mm_and_ps(sign_bit, cast(__m128) _mm_set1_epi32(0x80000000));

  /* scale by 4/Pi */
  __m128 y = _mm_mul_ps(x, _mm_set1_ps(1.27323954473516f));

  /* store the integer part of y in mm0 */
  __m128i emm2 = _mm_cvttps_epi32(y);
  /* j=(j+1) & (~1) (see the cephes sources) */
  emm2 = _mm_add_epi32(emm2, _mm_set1_epi32(1));
  emm2 = _mm_and_si128(emm2, _mm_set1_epi32(~1));
  y = _mm_cvtepi32_ps(emm2);
  /* get the swap sign flag */
  __m128i emm0 = _mm_and_si128(emm2, _mm_set1_epi32(4));
  emm0 = _mm_slli_epi32(emm0, 29);
  /* get the polynom selection mask
     there is one polynom for 0 <= x <= Pi/4
     and another one for Pi/4<x<=Pi/2

     Both branches will be computed.
  */
  emm2 = _mm_and_si128(emm2, _mm_set1_epi32(2));
  emm2 = _mm_cmpeq_epi32(emm2, _mm_setzero_si128());

  __m128 swap_sign_bit = _mm_castsi128_ps(emm0);
  __m128 poly_mask = _mm_castsi128_ps(emm2);
  sign_bit = _mm_xor_ps(sign_bit, swap_sign_bit);

  /* The magic pass: "Extended precision modular arithmetic"
     x = ((x - y * DP1) - y * DP2) - y * DP3; */
  __m128 xmm1 = _mm_set1_ps(-0.78515625f);
  xmm2 = _mm_set1_ps(-2.4187564849853515625e-4f);
  __m128 xmm3 =_mm_set1_ps(-3.77489497744594108e-8f);
  xmm1 = _mm_mul_ps(y, xmm1);
  xmm2 = _mm_mul_ps(y, xmm2);
  xmm3 = _mm_mul_ps(y, xmm3);
  x = _mm_add_ps(x, xmm1);
  x = _mm_add_ps(x, xmm2);
  x = _mm_add_ps(x, xmm3);

  /* Evaluate the first polynom  (0 <= x <= Pi/4) */
  y = _mm_set1_ps(2.443315711809948E-005);
  __m128 z = _mm_mul_ps(x,x);

  y = _mm_mul_ps(y, z);
  y = _mm_add_ps(y, _mm_set1_ps(-1.388731625493765E-003f));
  y = _mm_mul_ps(y, z);
  y = _mm_add_ps(y, _mm_set1_ps(4.166664568298827E-002));
  y = _mm_mul_ps(y, z);
  y = _mm_mul_ps(y, z);
  __m128 tmp = _mm_mul_ps(z, _mm_set1_ps(0.5f));
  y = _mm_sub_ps(y, tmp);
  y = _mm_add_ps(y, _mm_set1_ps(1.0f));

  /* Evaluate the second polynom  (Pi/4 <= x <= 0) */


  __m128 y2 = _mm_set1_ps(-1.9515295891E-4f);
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_add_ps(y2, _mm_set1_ps(8.3321608736E-3));
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_add_ps(y2, _mm_set1_ps(-1.6666654611E-1));
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_mul_ps(y2, x);
  y2 = _mm_add_ps(y2, x);

  /* select the correct result from the two polynoms */
  xmm3 = poly_mask;
  y2 = _mm_and_ps(xmm3, y2);
  y = _mm_andnot_ps(xmm3, y);
  y = _mm_add_ps(y,y2);
  /* update the sign */
  y = _mm_xor_ps(y, sign_bit);

  return y;
}

__m128 _mm_cos_ps(__m128 x) pure @safe
{
  __m128 xmm2 = _mm_setzero_ps();

  /* take the absolute value */
  x = _mm_and_ps(x, cast(__m128) _mm_set1_epi32(~0x80000000));

  /* scale by 4/Pi */
  __m128 y = _mm_mul_ps(x, _mm_set1_ps(1.27323954473516f));

  /* store the integer part of y in mm0 */
  __m128i emm2 = _mm_cvttps_epi32(y);
  /* j=(j+1) & (~1) (see the cephes sources) */
  emm2 = _mm_add_epi32(emm2, _mm_set1_epi32(1));
  emm2 = _mm_and_si128(emm2, _mm_set1_epi32(~1));
  y = _mm_cvtepi32_ps(emm2);

  emm2 = _mm_sub_epi32(emm2, _mm_set1_epi32(2));

  /* get the swap sign flag */
  __m128i emm0 = _mm_andnot_si128(emm2, _mm_set1_epi32(4));
  emm0 = _mm_slli_epi32(emm0, 29);
  /* get the polynom selection mask */
  emm2 = _mm_and_si128(emm2, _mm_set1_epi32(2));
  emm2 = _mm_cmpeq_epi32(emm2, _mm_setzero_si128());

  __m128 sign_bit = _mm_castsi128_ps(emm0);
  __m128 poly_mask = _mm_castsi128_ps(emm2);

  /* The magic pass: "Extended precision modular arithmetic"
     x = ((x - y * DP1) - y * DP2) - y * DP3; */
  __m128 xmm1 = _mm_set1_ps(-0.78515625f);
  xmm2 = _mm_set1_ps(-2.4187564849853515625e-4f);
  __m128 xmm3 =_mm_set1_ps(-3.77489497744594108e-8f);
  xmm1 = _mm_mul_ps(y, xmm1);
  xmm2 = _mm_mul_ps(y, xmm2);
  xmm3 = _mm_mul_ps(y, xmm3);
  x = _mm_add_ps(x, xmm1);
  x = _mm_add_ps(x, xmm2);
  x = _mm_add_ps(x, xmm3);

  /* Evaluate the first polynom  (0 <= x <= Pi/4) */
  y = _mm_set1_ps(2.443315711809948E-005);
  __m128 z = _mm_mul_ps(x,x);

  y = _mm_mul_ps(y, z);
  y = _mm_add_ps(y, _mm_set1_ps(-1.388731625493765E-003f));
  y = _mm_mul_ps(y, z);
  y = _mm_add_ps(y, _mm_set1_ps(4.166664568298827E-002));
  y = _mm_mul_ps(y, z);
  y = _mm_mul_ps(y, z);
  __m128 tmp = _mm_mul_ps(z, _mm_set1_ps(0.5f));
  y = _mm_sub_ps(y, tmp);
  y = _mm_add_ps(y, _mm_set1_ps(1.0f));

  /* Evaluate the second polynom  (Pi/4 <= x <= 0) */

  __m128 y2 = _mm_set1_ps(-1.9515295891E-4f);
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_add_ps(y2, _mm_set1_ps(8.3321608736E-3));
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_add_ps(y2, _mm_set1_ps(-1.6666654611E-1));
  y2 = _mm_mul_ps(y2, z);
  y2 = _mm_mul_ps(y2, x);
  y2 = _mm_add_ps(y2, x);

  /* select the correct result from the two polynoms */
  xmm3 = poly_mask;
  y2 = _mm_and_ps(xmm3, y2);
  y = _mm_andnot_ps(xmm3, y);
  y = _mm_add_ps(y,y2);
  /* update the sign */
  y = _mm_xor_ps(y, sign_bit);

  return y;
}


void _mm_sincos_ps(__m128 x, __m128* s, __m128* c) pure @safe
{ 
    __m128 sign_bit_sin = x;

    /* take the absolute value */
    x = _mm_and_ps(x, cast(__m128) _mm_set1_epi32(~0x80000000));

    /* extract the sign bit (upper one) */
    sign_bit_sin = _mm_and_ps(sign_bit_sin, cast(__m128) _mm_set1_epi32(0x80000000));

    /* scale by 4/Pi */
    __m128 y = _mm_mul_ps(x, _mm_set1_ps(1.27323954473516f));

    /* store the integer part of y in emm2 */
    __m128i emm2 = _mm_cvttps_epi32(y);
    emm2 = _mm_and_si128( _mm_add_epi32( _mm_cvttps_epi32(y), _mm_set1_epi32(1)), _mm_set1_epi32(~1) );
    y = _mm_cvtepi32_ps(emm2);
    __m128 swap_sign_bit_sin = _mm_castsi128_ps( _mm_slli_epi32( _mm_and_si128(emm2, _mm_set1_epi32(4)), 29) );
    __m128 poly_mask = _mm_castsi128_ps( _mm_cmpeq_epi32( _mm_and_si128(emm2, _mm_set1_epi32(2)), _mm_setzero_si128()) );


    /* The magic pass: "Extended precision modular arithmetic"
       x = ((x - y * DP1) - y * DP2) - y * DP3; */
    x = _mm_add_ps( x, _mm_mul_ps( y, _mm_add_ps( _mm_add_ps( _mm_set1_ps(-0.78515625), _mm_set1_ps(-2.4187564849853515625e-4)),
                                        _mm_set1_ps(-3.77489497744594108e-8) ) ) );

    __m128 sign_bit_cos = _mm_castsi128_ps( _mm_slli_epi32( _mm_andnot_si128( _mm_sub_epi32(emm2, _mm_set1_epi32(2)), _mm_set1_epi32(4)), 29) );

    sign_bit_sin = _mm_xor_ps(sign_bit_sin, swap_sign_bit_sin);


    /* Evaluate the first polynom  (0 <= x <= Pi/4) */
    __m128 z = _mm_mul_ps(x,x);
    y = _mm_add_ps(
        _mm_mul_ps(
            _mm_sub_ps(
                _mm_mul_ps(
                    _mm_add_ps(
                        _mm_mul_ps(
                            _mm_add_ps(
                                _mm_mul_ps(_mm_set1_ps(2.443315711809948E-005f), z),
                                _mm_set1_ps(-1.388731625493765E-003f) ),
                            z ),
                        _mm_set1_ps(4.166664568298827E-002f) ),
                    z ),
                _mm_set1_ps(0.5f) ),
            z ),
        _mm_set1_ps(1.0f) );

    /* Evaluate the second polynom  (Pi/4 <= x <= 0) */
    __m128 y2 = _mm_mul_ps(
        _mm_add_ps(
            _mm_mul_ps(
                _mm_add_ps(
                    _mm_mul_ps(
                        _mm_add_ps(
                            _mm_mul_ps(_mm_set1_ps(-1.9515295891E-4f), z ),
                                       _mm_set1_ps(8.3321608736E-3f) ),
                        z ),
                    _mm_set1_ps(-1.6666654611E-1f) ),
                z ),
            _mm_set1_ps(1.0f) ),
        x );

  /* select the correct result from the two polynoms */
  {
      __m128 xmm1 = _mm_add_ps( _mm_andnot_ps( poly_mask, y), _mm_and_ps(poly_mask, y2) );
      __m128 xmm2 = _mm_sub_ps( _mm_add_ps( y, y2 ), xmm1 );
      /* update the sign */
      *s = _mm_xor_ps(xmm1, sign_bit_sin);
      *c = _mm_xor_ps(xmm2, sign_bit_cos);
  }
}