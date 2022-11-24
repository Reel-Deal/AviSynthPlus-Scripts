################################################################################
# WDFPlus v1.0.0 (2022/11/23)
# Faster version of mirkosp's warpdering_faster script for AviSynth+.
#
# http://avisynth.nl/index.php/WDFPlus
# mod by: reel.deal
#
# mirkosp's original description:
# 	Uses aWarpSharp2's flattening to clean out ringing/smaller halos,
# 	then runs some masks to preserve the edges and avoid the thinning.
# 	This is nothing really new but it kind of just works, so eh.
#	Calling the filter more times in a row is probably more effective than toying with the parameters.
#	Only really tested out with a DVD, probably only works as intended on SD sources.
#	For HD, it might need some more mt_expand() in the owarp clip (I don't think, though).
#	Oh, and it's for newer and minor stuff, like downscaled HD sources released only on DVD and so on.
#	Don't expect this to work on Trigun. Or, well, I guess it could work, but... you know the deal.
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.3 or greater (r3682 minimum)
# Masktools2 v2.2.30 or greater
# NNEDI3CL v1.0.5 or greater
# aWarpSharp2 v2.1.7 or greater
# vsTEdgeMask v1.0.1 or greater
# NNEDI3 v0.9.4.61 or greater (if gpu=false)
################################################################################

/*
SYNTAX and PARAMETERS
**********************
WDFPlus (clip input, int "strength", int "tmax", int "tmin", bool "gpu")

input:
------
    Input clip; all 8-16 bit Y/YUV colorspaces are supported, except YV411.

strength:
---------
    Warp sharpening depth, higher values increase strength.
    Default: 6

tmax/tmin:
----------
    tmax and tmin work out the hysteresis mask for the final masking pass.
    Default: 10 (tmax), 7 (tmin)

gpu:
----
    True uses NNEDI3CL, false uses NNEDI3.
    Default: true
*/

function WDFPlus(clip input, int "strength", int "tmax", int "tmin", bool "gpu")
{
    strength = Default(strength, 6)
    tmax     = Default(tmax, 10)
    tmin     = Default(tmin, 7)
    gpu      = Default(gpu, true)

    Assert(!IsYV411(input), "WDFPlus: YV411 colorspace is not accepted")
    Assert(!IsRGB(input), "WDFPlus: input clip must be YUV")
    Assert(BitsPerComponent(input)!=32, "WDFPlus: input clip must be 8-16 bit")

    src   = (IsYUY2(input)) ? ConvertToYV16(input) : input
    csp   = BuildPixelType(sample_clip=src)
    w     = src.Width()
    h     = src.Height()
    pad   = PointResize(src, w+8, h+8, -4, -4, w+8, h+8)
    grey  = ExtractY(pad)
    up2   = (gpu==true) ? NNEDI3CL(grey, field=1, dh=true, dw=true) : nnedi3_rpow2(grey, rfactor=2)
    up4   = Spline36Resize(up2, (w+8)*4, (h+8)*4, 0.25, 0.25)
    edge  = aSobel(grey, thresh=255).aBlur()
    warp  = aWarp4(up4, edge, depth=strength)
    msk   = vsTEdgeMask(grey, threshY=0).mt_expand().mt_expand().mt_expand().mt_expand().mt_expand().Blur(1)
    owarp = mt_merge(grey, warp, msk).ShowY(csp)
    msk   = mt_hysteresis(vsTEdgeMask(grey, threshy=tmax), vsTEdgeMask(grey, threshy=tmin)).Blur(1)
    out   = mt_merge(owarp, pad, msk, u=4, v=4).Crop(4,4,-4,-4)
    final = propCopy(out,input)
    Return (IsYUY2(input)) ? ConvertToYUY2(final) : final
}
