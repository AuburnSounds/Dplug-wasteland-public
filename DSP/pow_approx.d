module pow_approx;

import inteli.emmintrin;
import std.math: log, pow;

nothrow @nogc:

// Translation of: https://github.com/herumi/fmath/blob/master/fmath.hpp
// Note: this sound a bit better than _mm_pow_ps
// Small difference on a GR signal, might be -106 RMS in a full plugin.
// However, the compression sounds nicer with this pow, and would probably sound even nicer with a smoother pow
// One day could be cool to create a library to approximate transcendental function in a musical way, so that their input parameter
// can be modulated without adverse effect. 

float _mm_pow_ss_alt(float base, float exponent)
{
    __m128 r = _mm_pow_ps_alt(_mm_set1_ps(base), _mm_set1_ps(exponent));
    return r.array[0];
}

__m128 _mm_pow_ps_alt(__m128 x, __m128 y)
{
    return _mm_exp_ps_alt(_mm_mul_ps(y, _mm_log_ps_alt(x)));
}

__m128 _mm_exp_ps_alt(__m128 x)
{
    __m128i limit = cast(__m128i)(_mm_and_ps(x, *cast(__m128*)(expVar.i7fffffff.ptr)));

    int over = _mm_movemask_epi8(_mm_cmpgt_epi32(limit, *cast(__m128i*)(expVar.maxX.ptr)));
    if (over) 
    {
        x = _mm_min_ps(x, _mm_load_ps(expVar.maxX.ptr));
        x = _mm_max_ps(x, _mm_load_ps(expVar.minX.ptr));
    }

    __m128i r = _mm_cvtps_epi32(_mm_mul_ps(x, *cast(__m128*)(expVar.a.ptr)));
    __m128 t = _mm_sub_ps(x, _mm_mul_ps(_mm_cvtepi32_ps(r), *cast(__m128*)(expVar.b.ptr)));
    t = _mm_add_ps(t, *cast(__m128*)(expVar.f1.ptr));

    __m128i v4 = _mm_and_si128(r, *cast(__m128i*)(expVar.mask_s.ptr));
    __m128i u4 = _mm_add_epi32(r, *cast(__m128i*)(expVar.i127s.ptr));
    u4 = _mm_srli_epi32(u4, expVar.s);
    u4 = _mm_slli_epi32(u4, 23);

    uint v0, v1, v2, v3;
    v0 = _mm_cvtsi128_si32(v4);
    v1 = _mm_extract_epi16(v4, 2);
    v2 = _mm_extract_epi16(v4, 4);
    v3 = _mm_extract_epi16(v4, 6);

    __m128 t0, t1, t2, t3;

    t0 = _mm_castsi128_ps(_mm_set1_epi32(expVar.tbl[v0]));
    t1 = _mm_castsi128_ps(_mm_set1_epi32(expVar.tbl[v1]));
    t2 = _mm_castsi128_ps(_mm_set1_epi32(expVar.tbl[v2]));
    t3 = _mm_castsi128_ps(_mm_set1_epi32(expVar.tbl[v3]));

    t1 = _mm_movelh_ps(t1, t3);
    t1 = _mm_castsi128_ps(_mm_slli_epi64(_mm_castps_si128(t1), 32));
    t0 = _mm_movelh_ps(t0, t2);
    t0 = _mm_castsi128_ps(_mm_srli_epi64(_mm_castps_si128(t0), 32));
    t0 = _mm_or_ps(t0, t1);

    t0 = _mm_or_ps(t0, _mm_castsi128_ps(u4));

    t = _mm_mul_ps(t, t0);

    return t;
}

__m128 _mm_log_ps_alt(__m128 x)
{
    __m128i xi = _mm_castps_si128(x);
    __m128i idx = _mm_srli_epi32(_mm_and_si128(xi, *cast(__m128i*)(logVar.m2.ptr)), (23 - logVar.LEN));
    __m128 a  = _mm_cvtepi32_ps(_mm_sub_epi32(_mm_and_si128(xi, *cast(__m128i*)(logVar.m1.ptr)), *cast(__m128i*)(logVar.m5.ptr)));
    __m128 b2 = _mm_cvtepi32_ps(_mm_and_si128(xi, *cast(__m128i*)(logVar.m3.ptr)));

    a = _mm_mul_ps(a, *cast(__m128*)(logVar.m4.ptr)); // c_log2

    uint i0 = _mm_cvtsi128_si32(idx);
    uint i1 = _mm_extract_epi16(idx, 2);
    uint i2 = _mm_extract_epi16(idx, 4);
    uint i3 = _mm_extract_epi16(idx, 6);   

    __m128 app, rev;
    __m128i L = _mm_loadl_epi64(cast(__m128i*)(&logVar.tbl[i0].app));
    __m128i H = _mm_loadl_epi64(cast(__m128i*)(&logVar.tbl[i1].app));
    __m128 t = _mm_castsi128_ps(_mm_unpacklo_epi64(L, H));
    L = _mm_loadl_epi64(cast(__m128i*)(&logVar.tbl[i2].app));
    H = _mm_loadl_epi64(cast(__m128i*)(&logVar.tbl[i3].app));
    rev = _mm_castsi128_ps(_mm_unpacklo_epi64(L, H));

    enum ubyte pack0 = MIE_PACK(2, 0, 2, 0);
    enum ubyte pack1 = MIE_PACK(3, 1, 3, 1);
    app = _mm_shuffle_ps!pack0(t, rev);
    rev = _mm_shuffle_ps!pack1(t, rev);

    a = _mm_add_ps(a, app);
    rev = _mm_mul_ps(b2, rev);
    return _mm_add_ps(a, rev);
}


private:

enum EXP_TABLE_SIZE = 10;
enum EXPD_TABLE_SIZE = 11;
enum LOG_TABLE_SIZE = 12;

struct ExpVar (size_t N = EXP_TABLE_SIZE)
{
    enum 
        s = N,
        n = 1 << s,
        f88 = 0x42b00000; /* 88.0 */
    
    float[8] minX;
    float[8] maxX;
    float[8] a;
    float[8] b;
    float[8] f1;
    uint[8] i127s;
    uint[8] mask_s;
    uint[8] i7fffffff;
    uint[n] tbl;

    static ExpVar init()
    {
        ExpVar r;

        float log_2 = log(2.0f);
        for (int i = 0; i < 8; i++) 
        {
            r.maxX[i] = 88;
            r.minX[i] = -88;
            r.a[i] = n / log_2;
            r.b[i] = log_2 / n;
            r.f1[i] = 1.0f;
            r.i127s[i] = 127 << s;
            r.i7fffffff[i] = 0x7fffffff;
            r.mask_s[i] = mask(s);
        }

        for (int i = 0; i < n; i++) 
        {
            float y = pow(2.0f, cast(float)i / n);          
            r.tbl[i] = *cast(uint*)(&y) & mask(23);
        }
        return r;
    }
}


union fi 
{
    float f;
    uint i;
}

align(16) static immutable ExpVar!EXP_TABLE_SIZE expVar = ExpVar!EXP_TABLE_SIZE.init();



uint mask(int x)
{
    return (1U << x) - 1;
}

struct tbl_t 
{
    float app;
    float rev;
} 

struct LogVar(size_t N = LOG_TABLE_SIZE)
{
    enum int LEN = N - 1;
    uint[4] m1; // 0
    uint[4] m2; // 16
    uint[4] m3; // 32
    float[4] m4;        // 48
    uint[4] m5; // 64
    
    tbl_t[1 << LEN] tbl;

    float c_log2 = log(2.0f) / (1 << 23);
    
    static LogVar init()
    {
        LogVar r;

        const double e = 1 / cast(double)(1 << 24);
        const double h = 1 / cast(double)(1 << LEN);
        const size_t n = 1U << LEN;
        for (size_t i = 0; i < n; i++) 
        {
            double x = 1 + double(i) / n;
            double a = log(x);
            r.tbl[i].app = cast(float)a;
            if (i < n - 1) {
                double b = log(x + h - e);
                r.tbl[i].rev = cast(float)((b - a) / ((h - e) * (1 << 23)));
            } else {
                r.tbl[i].rev = cast(float)(1 / (x * (1 << 23)));
            }
        }
        for (int i = 0; i < 4; i++) {
            r.m1[i] = mask(8) << 23;
            r.m2[i] = mask(LEN) << (23 - LEN);
            r.m3[i] = mask(23 - LEN);
            r.m4[i] = r.c_log2;
            r.m5[i] = 127U << 23;
        }
        return r;
    }
}

align(16) static immutable LogVar!LOG_TABLE_SIZE logVar 
    = LogVar!LOG_TABLE_SIZE.init();


static int MIE_PACK(int x, int y, int z, int w)
{
    return ((x) * 64 + (y) * 16 + (z) * 4 + (w));
}