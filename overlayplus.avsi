################################################################################
# OverlayPlus v1.0.0 (2021/09/01)
# Port of VapourSynth's havsfunc Overlay function to AviSynth+.
# http://avisynth.nl/index.php/OverlayPlus
# author: reel.deel
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.0 or greater
# Masktools2 v2.2.26 or greater
################################################################################

/*
SYNTAX and PARAMETERS
**********************
OverlayPlus (clip base, clip overlay, clip "mask", string "mode", float "opacity", int "x", int "y", bool "chroma", bool "mask_first_plane")

base:
-----
    Base clip.

overlay:
--------
    Overlay clip that will be placed over the base clip.

mask:
-----
    Optional transparency mask to use for the overlay clip.

mode:
-----
    Blend mode to use. Names in parenthesis are aliases that can also be used.
    Default: "normal"

        GROUP      |   BLEND MODE
        -----------|--------------------------------------------------------------------
        Simple     | average, blend (normal)
        -----------|--------------------------------------------------------------------
        Darken     | burn (colorburn), darken, linearburn, multiply, multiply128
        -----------|--------------------------------------------------------------------
        Lighten    | add (lineardodge), dodge (colordodge), lighten, linearadd, screen
        -----------|--------------------------------------------------------------------
        Mix        | hardlight, hardmix, interpolation, linearlight, overlay,
                   | pinlight, softburn, softdodge, softlight, softlight2, vividlight
        -----------|--------------------------------------------------------------------
        Difference | difference, divide, exclusion, extremity, grainextract, grainmerge,
                   | linearsubtract, negation, phoenix, subtract

opacity:
--------
    Blend transparency; the range is from 0.0 to 1.0, where 0.0 is transparent and 1.0 is fully opaque.
    Default: 1.0

x/y:
----
    Horizontal and vertical placement of the overlay clip on the base clip, in pixels. Can be positive or negative.
    Default: 0

chroma:
-------
    Enable or disable chroma processing. When chroma=false, chroma planes are copied from the base clip.
    Dafault: true (for RGB all planes are always processed)

mask_first_plane:
-----------------
    When set to true, the first plane of the the mask clip will be used as a mask for all channels.
    Default: true
*/


function OverlayPlus (clip base, clip overlay, clip "mask", string "mode", float "opacity", int "x", int "y", bool "chroma", bool "mask_first_plane")
{
    # Defaults
    msk     = default(mask,        Undefined)
    mode    = default(mode,          "blend")
    opacity = default(opacity,           1.0)
    x       = default(x,                   0)
    y       = default(y,                   0)
    chroma  = default(chroma,           true)
    mfp     = default(mask_first_plane, true)

    # Mask clip
    mask = Defined(msk) ? msk : overlay.IsRGB ? Blankclip(overlay, color=$ffffff) : Blankclip(overlay, color_yuv=$ffffff) # color=$ffffff on YUV produces limited range white(235)

    # Sanity checks
    opacity = min(max(opacity, 0.0), 1.0)
    Assert(!IsYV411(base), "OverlayPlus: YV411 colorspace is not accepted")
    Assert(IsPlanar(base), "OverlayPlus: base clip must be planar (Y, YUV or RGB)")
    Assert(IsPlanar(overlay), "OverlayPlus: overlay clip must be planar (Y, YUV or RGB)")
    Assert(IsPlanar(mask), "OverlayPlus: mask clip must be planar (Y, YUV or RGB)")
    Assert(PixelType(base) == PixelType(overlay), "OverlayPlus: overlay clip must be the same colorspace as the base clip")
    Assert(mfp == true || PixelType(mask) == PixelType(base), "OverlayPlus: mask clip must be the same colorspace as the base clip")
    Assert(BitsPerComponent(base) == BitsPerComponent(mask), "OverlayPlus: mask clip must be the same bitdepth as the base clip")
    Assert(overlay.Width == mask.Width && overlay.Height == mask.Height, "OverlayPlus: mask clip must be the same dimensions as the overlay clip")
    Assert(!Is420(base) || y%2 == 0, "OverlayPlus: the value of 'y' must be mod2")
    Assert(!Is420(base) || !Is422(base) && x%2 == 0, "OverlayPlus: the value of 'x' must be mod2")

    # Calculate padding sizes
    l = x
    r = base.width - overlay.width - x
    t = y
    b = base.height - overlay.height - y

    # Split into crop and padding values
    cl = min(l, 0) * -1
    pl = max(l, 0)
    ct = min(t, 0) * -1
    pt = max(t, 0)
    cr = min(r, 0) * -1
    pr = max(r, 0)
    cb = min(b, 0) * -1
    pb = max(b, 0)

    # Crop and padding
    overlay = overlay.Crop(cl, ct, -cr, -cb)
    overlay = overlay.IsRGB ? overlay.AddBorders(pl, pt, pr, pb, color=$000000) : overlay.AddBorders(pl, pt, pr, pb, color_yuv=$000000) # color=$000000 on YUV does not produce black(0) borders
    mask = mask.Crop(cl, ct, -cr, -cb)
    mask = mask.IsRGB ? mask.AddBorders(pl, pt, pr, pb, color=$000000) : mask.AddBorders(pl, pt, pr, pb, color_yuv=$000000) # color=$000000 on YUV does not produce black(0) borders


    # Range based on bitdepth
    if (BitsPerComponent(base) != 32) {
        neutral = String(BitLShift(1, (BitsPerComponent(base) - 1))) # 128 ... 32768
        peak    = String(BitLShift(1, BitsPerComponent(base)) - 1)   # 255 ... 65535
        factor  = String(BitLShift(1, BitsPerComponent(base)))       # 256 ... 65536
    }
    else {
        neutral = String(0.5)
        peak    = String(1.0)
        factor  = String(1.0)
    }


    # Blending modes
    if (mode == "blend" || mode == "normal") {
        #NOP()
        expr = ""
    }
    else if (mode == "add" || mode == "addition" || mode == "lineardodge") {
        expr = "x y +"
    }
    else if (mode == "average") {
        expr = "x y + 2 /"
    }
    else if (mode == "burn" || mode == "colorburn") {
        expr = "y 0 <= y "+ peak +" "+ peak +" x - "+ factor +" * y / - ?"
    }
    else if (mode == "darken") {
        expr = "x y min"
    }
    else if (mode == "difference") {
        expr = "x y - abs"
    }
    else if (mode == "divide") {
        expr = "y 0 <= "+ peak +" "+ peak +" x * y / ?"
    }
    else if (mode == "dodge" || mode == "colordodge") {
        expr = "y "+ peak +" >= y x "+ factor +" * "+ peak +" y - / ?"
    }
    else if (mode == "exclusion") {
        expr = "x y + 2 x * y * "+ peak +" / -"
    }
    else if (mode == "extremity") {
        expr = ""+ peak +" x - y - abs"
    }
    else if (mode == "freeze") {
        expr = "y 0 <= 0 "+ peak +" "+ peak +" x - dup * y / "+ peak +" min - ?"
    }
    else if (mode == "glow") {
        expr = "x "+ peak +" >= x y y * "+ peak +" x - / ?"
    }
    else if (mode == "grainextract") {
        expr = "x y - "+ neutral +" +"
    }
    else if (mode == "grainmerge") {
        expr = "x y + "+ neutral +" -"
    }
    else if (mode == "hardlight") {
        expr = "y "+ neutral +" < 2 y x * "+ peak +" / * "+ peak +" 2 "+ peak +" y - "+ peak +" x - * "+ peak +" / * - ?"
    }
    else if (mode == "hardmix") {
        expr = "x "+ peak +" y - < 0 "+ peak +" ?"
    }
    else if (mode == "heat") {
        expr = "x 0 <= 0 "+ peak +" "+ peak +" y - dup * x / "+ peak +" min - ?"
    }
    else if (mode == "interpolation") {
        expr = ""+ peak +" 0.5 pi x * "+ peak +" / cos 4 / - pi y * "+ peak +" / cos 4 / - *" # from Overlay_MTools
    }
    else if (mode == "lighten") {
        expr = "x y max"
    }
    else if (mode == "linearadd" || mode == "hypot") {
        expr = "x 2 ^ y 2 ^ + sqrt" # same as Gimp's 2.10 addition blending mode, aka as Nuke's "hypot"
    }
    else if (mode == "linearburn") {
        expr = "x y + "+ peak +" < 0 x y + "+ peak +" - ?" # from Overlay_MTools
    }
    else if (mode == "linearlight") {
        expr = "x "+ neutral +" < x 2 y * + "+ peak +" - x 2 y "+ neutral +" - * + ?"
    }
    else if (mode == "linearsubtract") {
        expr = "x 2 ^ y 2 ^ - sqrt" # same as Gimp's 2.10 subtract blending mode
    }
    else if (mode == "multiply") {
        expr = "x y * "+ peak +" /"
    }
    else if (mode == "multiply128") {
        expr = "x "+ neutral +" - y * "+ neutral +" 4 / / "+ neutral +" +" # from ffmpeg
    }
    else if (mode == "negation") {
        expr = ""+ peak +" "+ peak +" x - y - abs -"
    }
    else if (mode == "overlay") {
        expr = "x "+ neutral +" < 2 x y * "+ peak +" / * "+ peak +" 2 "+ peak +" x - "+ peak +" y - * "+ peak +" / * - ?"
    }
    else if (mode == "phoenix") {
        expr = "x y min x y max - "+ peak +" +"
    }
    else if (mode == "pinlight") {
        expr = "y "+ neutral +" < x 2 y * min x 2 y "+ neutral +" - * max ?"
    }
    else if (mode == "reflect") {
        expr = "y "+ peak +" >= y x x * "+ peak +" y - / ?"
    }
    else if (mode == "screen") {
        expr = ""+ peak +" "+ peak +" x - "+ peak +" y - * "+ peak +" / -"
    }
    else if (mode == "softburn") {
        expr = "x y + "+ peak +" < x "+ peak +" == x "+ peak +" y * 2 "+ peak +" x - * / ? y 0 == y "+ peak +" "+ peak +" x - "+ peak +" * y 2 * / - ? ?" # from Overlay_MTools
    }
    else if (mode == "softdodge") {
        expr = "x y + "+ peak +" < y "+ peak +" == y x "+ peak +" * 2 "+ peak +" y - * / ? x 0 == x "+ peak +" "+ peak +" "+ peak +" y - * 2 x * / - ? ?" # from Overlay_MTools
    }
    else if (mode == "softlight") {
        expr = "x "+ peak +" / x y 2 * + x y * "+ neutral +" / - *" # from Overlay_MTools
    }
    else if (mode == "softlight2") {
        expr = "y "+ neutral +" > x "+ peak +" x - y "+ neutral +" - * "+ neutral +" / 0.5 x "+ neutral +" - abs "+ peak +" / - * + x x "+ neutral +" y - "+ neutral +" / * 0.5 x "+ neutral +" - abs "+ peak +" / - * - ?"
    }
    else if (mode == "subtract") {
        expr = "x y -"
    }
    else if (mode == "vividlight") {
        expr = "y "+ neutral +" < y 0 <= 2 y * "+ peak +" "+ peak +" x - "+ factor +" * 2 y * / - ? 2 y "+ neutral +" - * "+ peak +" >= 2 y "+ neutral +" - * x "+ factor +" * "+ peak +" 2 y "+ neutral +" - * - / ? ?"
    }
    else {
        Assert(false, "OverlayPlus: invalid 'mode' specified")
    }

    # Process
    chroma  = (base.IsRgb || chroma==true) ? "process" : "copy"
    chromax = (chroma == "process") ? expr : ""
    mfp2    = (chroma == "process") ? mfp : false # bug in mt_merge; does not honor chroma copy if luma=true
    mask    = (opacity < 1.0) ? (mfp==true && mask.NumComponents!=1) ? Expr(mask, "x "+ String(opacity) +" *", "") : Expr(mask, "x "+ String(opacity) +" *") : mask
    overlay = (mode != "blend" && mode != "normal") ? (base.NumComponents==1) ? Expr(base, overlay, expr) : Expr(base, overlay, expr, chromax) : overlay
    blend   = (Defined(msk)==false && opacity == 1.0 && chroma=="process") ? overlay : mt_merge(base, overlay, mask, chroma=chroma, luma=mfp2)
    return blend
}
