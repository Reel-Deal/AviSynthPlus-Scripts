################################################################################
# DDCR v1.0.0 (2023/03/03)
# A purely spatial dot crawl removal script for AviSynth+. Only the luma channel
# is processed, chroma is simply copied. DDCR stands for Didée's Dot Crawl Remover.
# Modified from https://forum.doom9.org/showthread.php?p=1584186#post1584186
#
# http://avisynth.nl/index.php/DDCR
# mod by: Reel.Deal
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.2 or greater
# frfun7 v0.9 or greater
# MaskTools2 v2.2.30 or greater
# RgTools v1.2 or greater
# sbr v1.0.0 or greater
# Vinverse v0.9.4 or greater
################################################################################
/*
SYNTAX and PARAMETERS
**********************
DDCR(clip input, int "mode", float_array "frfun7_params")

input:
------
    Input clip; all 8 bit Y/YUV colorspaces are supported. Progressive input only.

mode:
-----
    Processing mode:
    * 1 : post IVTC
    * 2 : post deinterlacing
    Filter should be used right after IVTC or deinterlacing.
    With truly interlaced content, QTGMC does a good job at removing most of the
    dot crawl. Mode 2 helps removing the remaining dot crawl.

    Default: 1

frfun7_params:
--------------
    frfun7 parameters, they must be given in the correct order.
    * lamda (float) : adjust the power of the local denoising.
    * T     (float) : limits the max luma denoising power for edges.
    * P     (int)   : 0 is faster but lower quality, 1 is slower but better quality.
    * TP1   (int)   : bypass threshold which affects P=1.
    * R1    (int)   : first past radius; valid values are 2 or 3.
    If only the first value is given, the rest will be set to their default,
    and so on. See frfun7 documentation for full details.

    Default: [1.01, 8.0, 1, 0, 3]
*/
################################################################################

Function DDCR(clip input, int "mode", float_array "frfun7_params")
{
    # Defaults
    mode    = Default(mode, 1)
    params  = Defined(frfun7_params)
    asize   = (params) ? ArraySize(frfun7_params) : 0
    lambda  = (params) ? frfun7_params[0] : 1.01
    T       = (params && asize >= 2) ? frfun7_params[1] : 8.0
    P       = (params && asize >= 3) ? frfun7_params[2] : 1
    TP1     = (params && asize >= 4) ? frfun7_params[3] : 0
    R1      = (params && asize >= 5) ? frfun7_params[4] : 3

    # Sanity checks
    Assert(1 <= mode <= 2, "DDCR: invalid 'mode' specified")
    Assert(!IsRGB(input), "DDCR: input clip must be Y/YUV")
    Assert(BitsPerComponent(input)==8, "DDCR: input clip must be 8-bit")

    # Properties
    IsY_    = IsY(input)
    IsYUY2_ = IsYUY2(input)
    ox      = Width(input)
    oy      = Height(input)
    ox2     = ox + 8

    # Convert YUY2 to planar and extract luma plane
    src     = (IsYUY2_) ? ConvertToYUV422(input) : input
    grey    = (IsY_) ? src : ExtractY(src)

    # Borders
    borders = BicubicResize(grey, ox/2, oy/2).BicubicResize(ox2, oy)
    raw     = StackHorizontal(Crop(borders, 0, 0, 4, 0), grey, Crop(borders, ox+4, 0, 0, 0))

    # Mode
    clean1  = (mode == 1) ? SeparateFields(raw).Vinverse2().Weave() : Vinverse2(raw)

    # Process
    D1      = mt_makediff(raw, clean1)
    D8      = BicubicResize(D1, ox2/2-72, oy).Blur(1, 0).BicubicResize(ox2, oy, 1, 0)
    D9      = mt_lutxy(D1, D8, "x 128 - y 128 - * 0 < 128 x 128 - abs y 128 - abs < x y ? ?")
    clean1a = mt_adddiff(clean1, D9)
    clean1b = (TP1==0) ? frfun7(clean1a, lambda=lambda, T=T, P=P, R1=R1) \
                       : frfun7(clean1a, lambda=lambda, T=T, P=P, TP1=TP1, R1=R1) # bug in frfun7 v0.9

    allD    = mt_makediff(raw, clean1b)
    shrpD   = mt_makediff(clean1b, RemoveGrain(clean1b, 20))
    DD      = Repair(shrpD, allD, 13).mt_lutxy(shrpD, "x 128 - y 128 - * 0 < 128 x 128 - abs y 128 - abs < x y ? ?")
    clean1c = mt_lutxy(clean1b, clean1a, "x 3 + y < x 2 + x y < x 1 + x 3 - y > x 2 - x y > x 1 - x ? ? ? ?")
    clean1d = mt_adddiff(clean1c, sbr(DD)).Crop(4, 0, -4, 0)
    merged  = (IsY_) ? clean1d : MergeLuma(src, clean1d)
    output  = (IsYUY2_) ? ConvertToYUY2(merged) : merged

    # Output
    Return(propCopy(output, input))
}
