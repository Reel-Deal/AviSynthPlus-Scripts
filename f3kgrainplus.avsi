################################################################################
# f3kgrainPlus v1.0.0 (2022/12/09)
# Fast luma-adaptive grain generator for AviSynth+
# Temporal soften strength of grain is changeable ( it can only be set on/off in f3kdb )
#
# http://avisynth.nl/index.php/f3kgrainPlus
# mod by: reel.deal (original author: 06_taro)
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.2 or greater
# MaskTools2 v2.2.30 or greater
# neo_f3kdb r8 or greater
# RgTools v1.2 or greater
################################################################################

/*
SYNTAX and PARAMETERS
**********************
f3kgrainPlus (clip input, int "luma", int "chroma", int "mode", int "temp", int "adapt", float "sigma")

input:
------
    Input clip; all 8-16 bit Y/YUV colorspaces are supported, except YV411.

luma, chroma:
-------------
    Luma/chroma grain strength
    Default: 64, 64

mode:
-----
    random_algo_grain mode:
    * 0 - old algorithm
    * 1 - uniform distribution
    * 2 - Gaussian(normal) distribution
    Default: 1

temp:
-----
    Temporal stabilization for grain (the higher, the more calm) [0=nervous,...,100=static]
    Default: 50

adapt:
------
    Brightness threshold for adaptative grain mask [-1=off, 0=input, 1...254, 255=invert]
    The higher, the less grain in dark areas & the more grain in bright areas
    Default: 64

sigma:
------
    Standard deviation of Gaussian distribution mode
    Default: 1.0

################################################################################
CHANGELOG
*********
Version      Date            Changes
1.0.0        2022/12/09      - Based on f3kgrain v0.4
                             - Add native high bitdepth support
                             - Use neo_f3kdb
                             - Remove dither dependency and lsb parameter
                             - Cosmetics
*/

Function f3kgrainPlus(clip input, int "luma", int "chroma", int "mode", int "temp", int "adapt", float "sigma")
{
    luma   = Default(luma,   64)
    chroma = Default(chroma, 64)
    mode   = Default(mode,    1)
    temp   = Default(temp,   50)
    adapt  = Default(adapt,  64)

    sigma  = Default(sigma, 1.0)

    Assert( temp>=0 && temp<=100,        "f3kgrainPlus: invalid value for temp(0~100)!"    )
    Assert( adapt>=-1 && adapt<=255,     "f3kgrainPlus: invalid value for adapt(-1~255)!"  )
    Assert( !IsYV411(input),             "f3kgrainPlus: YV411 colorspace is not supported" )
    Assert( !IsRGB(input),               "f3kgrainPlus: input clip must be YUV"            )
    Assert( BitsPerComponent(input)!=32, "f3kgrainPlus: input clip must be 8-16 bit"       )

    Y = (luma==0)   ? 2 : 3
    U = (chroma==0) ? 2 : 3
    V = (chroma==0) ? 2 : 3

    YUY2_ = IsYUY2(input)
    input = (YUY2_) ? ConvertToYV16(input) : input

    Lclip = ExtractY(input)
    Lmask = (adapt==0)   ? Lclip.RemoveGrain(19)
    \     : (adapt==255) ? Lclip.mt_invert().RemoveGrain(19)
    \     :                Lclip.mt_lut("x "+string(adapt)+" - abs 255 * "+string(adapt)+" 128 - abs 128 + /", scale_inputs="allf").RemoveGrain(19)

    grain = input.BlankClip(color_yuv=$808080).neo_f3kdb(Y=0, Cb=0, Cr=0, grainY=luma, grainC=chroma, dynamic_grain=true, random_algo_grain=mode, random_param_grain=sigma)

    gsoft = (luma!=0 && chroma!=0) ? grain.TemporalSoften(1, 255, 255, scenechange=255)
    \     : (luma!=0)              ? grain.TemporalSoften(1, 255,   0, scenechange=255)
    \     : (chroma!=0)            ? grain.TemporalSoften(1,   0, 255, scenechange=255)
    \     :                          grain

    gmerge = (temp ==   0) ? grain
    \      : (temp == 100) ? gsoft
    \      : (luma!=0 && chroma!=0) ? Merge(grain, gsoft, temp/100.)
    \      : (luma!=0)              ? MergeLuma(grain, gsoft, temp/100.)
    \      : (chroma!=0)            ? MergeChroma(grain, gsoft, temp/100.)
    \      :                          grain

    adsoft = mt_adddiff(input, gmerge, Y=Y, U=U, V=V)

    b_luma = (chroma!=0) ? True : False

    out = (adapt==-1) ? adsoft : mt_merge(adsoft, input, Lmask, luma=b_luma, Y=Y, U=U, V=V)
    return (YUY2_) ? ConvertToYV16(out) : out
}
