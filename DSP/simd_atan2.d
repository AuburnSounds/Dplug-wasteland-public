/**
SIMD atan2
Faster atan and atan2 intended for spectral.
Haven't validated that as distortion vs stdlib.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module simd_atan2;

import std.complex;
import std.math: PI;
import inteli.avx2intrin;

nothrow @nogc:




// From: https://mazzo.li/posts/vectorized-atan2.html
void atan2_manual_1(const(Complex!float)* inComplexes,
                    size_t num_points,  // must be multiple of 8
                    float* output) 
{
    // Store pi and pi/2 as constants
    const __m256 pi = _mm256_set1_ps(PI);
    const __m256 pi_2 = _mm256_set1_ps(PI/2);

    // Create bit masks that we will need.

    // The first one is all 1s except from the sign bit:
    //
    //     01111111111111111111111111111111
    //
    // We can use it to make a float absolute by AND'ing with it.
    const __m256 abs_mask = _mm256_castsi256_ps(_mm256_set1_epi32(0x7FFFFFFF));

    // The second is only the sign bit:
    //
    //     10000000000000000000000000000000
    //
    // we can use it to extract the sign of a number by AND'ing with it.
    const __m256 sign_mask = _mm256_castsi256_ps(_mm256_set1_epi32(0x80000000));

    // Traverse the arrays 8 points at a time.
    for (size_t i = 0; i < num_points; i += 8) {

        __m256 samples_0_to_3 = _mm256_loadu_ps(cast(float*) &inComplexes[i]);
        __m256 samples_4_to_7 = _mm256_loadu_ps(cast(float*) &inComplexes[i+4]);

        __m256 x;
        x[0] = samples_0_to_3[0];
        x[1] = samples_0_to_3[2];
        x[2] = samples_0_to_3[4];
        x[3] = samples_0_to_3[6];
        x[4] = samples_4_to_7[0];
        x[5] = samples_4_to_7[2];
        x[6] = samples_4_to_7[4];
        x[7] = samples_4_to_7[6];
        __m256 y;
        y[0] = samples_0_to_3[1];
        y[1] = samples_0_to_3[3];
        y[2] = samples_0_to_3[5];
        y[3] = samples_0_to_3[7];
        y[4] = samples_4_to_7[1];
        y[5] = samples_4_to_7[3];
        y[6] = samples_4_to_7[5];
        y[7] = samples_4_to_7[7];

        // Compare |y| > |x| using the `VCMPPS` instruction. The output of the
        // instruction is an 8-vector of floats that we can
        // use as a mask: the elements where the respective comparison is true
        // will be filled with 1s, with 0s where the comparison is false.
        //
        // Visually:
        //
        //      5 -5  5 -5  5 -5  5 -5
        //               >
        //     -5  5 -5  5 -5  5 -5  5
        //               =
        //      1s 0s 1s 0s 1s 0s 1s 0s
        //
        // Where `1s = 0xFFFFFFFF` and `0s = 0x00000000`.
        __m256 swap_mask = _mm256_cmp_ps!_CMP_GT_OS(
                                                    _mm256_and_ps(y, abs_mask), // |y|
                                                    _mm256_and_ps(x, abs_mask), // |x|

                                                    );
        // Create the atan input by "blending" `y` and `x`, according to the mask computed
        // above. The blend instruction will pick the first or second argument based on
        // the mask we passed in. In our case we need the number of larger magnitude to
        // be the denominator.
        __m256 atan_input = _mm256_div_ps(
                                          _mm256_blendv_ps(y, x, swap_mask), // pick the lowest between |y| and |x| for each number
                                          _mm256_blendv_ps(x, y, swap_mask)  // and the highest.
                                          );

        // Approximate atan
        //__m256 result = _mm256_atan_ps(atan_input);
        __m256 result = atan_avx_approximation(atan_input);

        // If swapped, adjust atan output. We use blending again to leave
        // the output unchanged if we didn't swap anything.
        //
        // If we need to adjust it, we simply carry the sign over from the input
        // to `pi_2` by using the `sign_mask`. This avoids a more expensive comparison,
        // and also handles edge cases such as -0 better.
        result = _mm256_blendv_ps(
                                  result,
                                  _mm256_sub_ps(
                                                _mm256_or_ps(pi_2, _mm256_and_ps(atan_input, sign_mask)),
                                                result
                                                ),
                                  swap_mask
                                  );
        // Adjust the result depending on the input quadrant.
        //
        // We create a mask for the sign of `x` using an arithmetic right shift:
        // the mask will be all 0s if the sign if positive, and all 1s
        // if the sign is negative. This avoids a further (and slower) comparison
        // with 0.
        __m256 x_sign_mask = cast(__m256)(_mm256_srai_epi32(cast(__m256i)x, 31));
        // Then use the mask to perform the adjustment only when the sign
        // if positive, and use the sign bit of `y` to know whether to add
        // `pi` or `-pi`.
        result = _mm256_add_ps(
                               _mm256_and_ps(
                                             _mm256_xor_ps(pi, _mm256_and_ps(sign_mask, y)),
                                             x_sign_mask
                                             ),
                               result
                               );

        // Store result
        _mm256_storeu_ps(&output[i], result);
    }
}

__m256 atan_avx_approximation(__m256 x) 
{
    // __m256 is the type of 8-float AVX vectors.

    // Store the coefficients -- `_mm256_set1_ps` creates a vector
    // with the same value in every element.
    __m256 a1  = _mm256_set1_ps( 0.99997726f);
    __m256 a3  = _mm256_set1_ps(-0.33262347f);
    __m256 a5  = _mm256_set1_ps( 0.19354346f);
    __m256 a7  = _mm256_set1_ps(-0.11643287f);
    __m256 a9  = _mm256_set1_ps( 0.05265332f);
    __m256 a11 = _mm256_set1_ps(-0.01172120f);

    // Compute the polynomial on an 8-vector with FMA.

    __m256 x_sq = x * x;
    __m256 result;
    result =                               a11;
    result = x_sq * result + a9;
    result = x_sq * result + a7;
    result = x_sq * result + a5;
    result = x_sq * result + a3;
    result = x_sq * result + a1;
    result = x * result;
    return result;
}

// This is a bit more expensive, but also better precision than atan_avx_approximation
__m256 _mm256_atan_ps( __m256 x )
{
	__m256 sign_bit, y;
    const __m256 sign_mask = cast(__m256) _mm256_set1_epi32(0x80000000);
    const __m256 inv_sign_mask = cast(__m256) _mm256_set1_epi32(~0x80000000);
    const __m256 atanrange_hi = _mm256_set1_ps(2.414213562373095);
    const __m256 atanrange_lo = _mm256_set1_ps(0.4142135623730950);
    const __m256 cephes_PIO2F = _mm256_set1_ps(1.5707963267948966192);
    const __m256 cephes_PIO4F = _mm256_set1_ps(0.7853981633974483096);
    const __m256 atancof_p0 = _mm256_set1_ps(8.05374449538e-2);
    const __m256 atancof_p1 = _mm256_set1_ps(1.38776856032E-1);
    const __m256 atancof_p2 = _mm256_set1_ps(1.99777106478E-1);
    const __m256 atancof_p3 = _mm256_set1_ps(3.33329491539E-1);
    const __m256 ps_1 = _mm256_set1_ps(1.0f);


	sign_bit = x;
	/* take the absolute value */
	x = _mm256_and_ps(x, inv_sign_mask);

	/* extract the sign bit (upper one) */
	sign_bit = _mm256_and_ps(sign_bit, sign_mask);

    /* range reduction, init x and y depending on range */
	/* x > 2.414213562373095 */
	//__m256 cmp0 = _mm256_cmpgt_ps( x, atanrange_hi );
	/* x > 0.4142135623730950 */
	//__m256 cmp1 = _mm256_cmpgt_ps( x, atanrange_lo );

    __m256 cmp0 = _mm256_cmp_ps!_CMP_GT_OS(x, atanrange_hi );
    __m256 cmp1 = _mm256_cmp_ps!_CMP_GT_OS(x, atanrange_lo );

	/* x > 0.4142135623730950 && !( x > 2.414213562373095 ) */
	__m256 cmp2 = _mm256_andnot_ps( cmp0, cmp1 );

	/* -( 1.0/x ) */
	__m256 y0 = _mm256_and_ps( cmp0, cephes_PIO2F );
	__m256 x0 = _mm256_div_ps( ps_1, x );
	x0 = _mm256_xor_ps( x0, sign_mask );

	__m256 y1 = _mm256_and_ps( cmp2, cephes_PIO4F );
	/* (x-1.0)/(x+1.0) */
	__m256 x1_o = _mm256_sub_ps( x, ps_1 );
	__m256 x1_u = _mm256_add_ps( x, ps_1 );
	__m256 x1 = _mm256_div_ps( x1_o, x1_u );

	__m256 x2 = _mm256_and_ps( cmp2, x1 );
	x0 = _mm256_and_ps( cmp0, x0 );
	x2 = _mm256_or_ps( x2, x0 );
	cmp1 = _mm256_or_ps( cmp0, cmp2 );
	x2 = _mm256_and_ps( cmp1, x2 );
	x = _mm256_andnot_ps( cmp1, x );
	x = _mm256_or_ps( x2, x );

	y = _mm256_or_ps( y0, y1 );


	__m256 zz = _mm256_mul_ps( x, x );
	__m256 acc = atancof_p0;
	acc = _mm256_mul_ps( acc, zz );
	acc = _mm256_sub_ps( acc, atancof_p1 );
	acc = _mm256_mul_ps( acc, zz );
	acc = _mm256_add_ps( acc, atancof_p2 );
	acc = _mm256_mul_ps( acc, zz );
	acc = _mm256_sub_ps( acc, atancof_p3 );
	acc = _mm256_mul_ps( acc, zz );
	acc = _mm256_mul_ps( acc, x );
	acc = _mm256_add_ps( acc, x );
	y = _mm256_add_ps( y, acc );

	/* update the sign */
	y = _mm256_xor_ps( y, sign_bit );

	return y;
}


void computeComplexArg_naive(Complex!float* inBuf, float* outBuf, int count)
{
    for (int n = 0; n < count; ++n)
    {
        outBuf[n] = std.complex.arg(inBuf[n]);
    }
}

void computeComplexArg_simd(Complex!float* inBuf, float* outBuf, int count)
{

    int simd_doable = (count / 8) * 8;
    atan2_manual_1(&inBuf[0], simd_doable, &outBuf[0]);

    int n = simd_doable;
    for ( ; n < count; ++n)
    {
        outBuf[n] = std.complex.arg(inBuf[n]);
    }
}