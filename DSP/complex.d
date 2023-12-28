/**
A few wrappers for faster complex numbers work.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module complex;

import std.complex;

nothrow @nogc:

import inteli.pmmintrin;
import simd_sincos;

/// Add two complex numbers.
Complex!float complexAdd(Complex!float a, Complex!float b) pure @safe
{
    return a + b;
}

///ditto
Complex!double complexAdd(Complex!double a, Complex!double b) pure @safe
{
    return a + b;
}

/// Multiply two complex numbers. This uses SSE3 when available.
Complex!float complexMul(Complex!float a, Complex!float b) pure @safe
{
    __m128 A = void;
    A[0] = a.re*b.re;
    A[1] = a.re*b.im;

    __m128 B = void;
    B[0] = a.im*b.im;
    B[1] = a.im*b.re;
    __m128 R = _mm_addsub_ps(A, B);
    return Complex!float(R[0], R[1]);
}

// Multiply two pairs of complex numbers (four complex numbers).
// This return [A*B, C*D] from the inputs [A C] and [B D], with A B C and D being 32-bit float complex numbers.
// This uses SSE3 when available.
__m128 complexMul(__m128 AC, __m128 BD) pure @safe
{
    // M contains: [A.re * B.re, A.re * B*im, C.re * D.re, C.re * D.im]
    __m128 M = _mm_moveldup_ps(AC) * BD;

    // N contains: [A.im * B.im, A.im * B.re, C.im * D.im, C.im * D.re]
    __m128 N = _mm_movehdup_ps(AC) * _mm_shuffle_ps!(_MM_SHUFFLE(2, 3, 0, 1))(BD, BD);

    __m128 R = _mm_addsub_ps(M, N);
    return R;
}

///ditto
Complex!double complexMul(Complex!double a, Complex!double b) pure
{
    __m128d A = void;
    A[0] = a.re*b.re;
    A[1] = a.re*b.im;

    __m128d B = void;
    B[0] = a.im*b.im;
    B[1] = a.im*b.re;
    __m128d R = _mm_addsub_pd(A, B);
    return Complex!double(R[0], R[1]);
}

/// Get a complex numbers from its modulus and angle.
/// Returns: (cos(argument) + i * sin(argument)) * modulus
Complex!float complexFromPolar(float modulus, float argumentInRadians)
{
    return modulus * complexFromArgument(argumentInRadians);
}

/// Get a normalized complex numbers from its angle.
/// Returns: cos(argument) + i * sin(argument)
/// Note: uses _mm_sincos_ps, not necessarily as safe and accurate than Phobos or libc.
Complex!float complexFromArgument(float argumentInRadians)
{
    __m128 A = _mm_setzero_ps();
    __m128 S = _mm_setzero_ps();
    __m128 C = _mm_setzero_ps();
    A.ptr[0] = argumentInRadians;
    _mm_sincos_ps(A, &S, &C);
    return Complex!float(C.array[0], S.array[0]);
}