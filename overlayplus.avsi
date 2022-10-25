################################################################################
# OverlayPlus v1.2.0 (2021/09/27)
# Port of VapourSynth's havsfunc Overlay function to AviSynth+.
# http://avisynth.nl/index.php/OverlayPlus
# author: reel.deel
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.0 or greater
# Masktools2 v2.2.27 or greater
################################################################################

/*
SYNTAX and PARAMETERS
**********************
OverlayPlus (clip base, clip overlay, clip "mask", string "mode", float "opacity", int "x", int "y", bool "chroma", bool "mask_first_plane", string "cplace")

base:
-----
    Base clip; all colorspaces (except YV411) are supported.
    Alpha channel is copied from the base clip (if applicable).

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
        -----------|--------------------------------------------------------------------------
        Simple     | average, blend (normal)
        -----------|--------------------------------------------------------------------------
        Darken     | burn (colorburn), darken, linearburn, multiply, multiply128
        -----------|--------------------------------------------------------------------------
        Lighten    | add (lineardodge), dodge (colordodge), lighten, linearadd (hypot), screen
        -----------|--------------------------------------------------------------------------
        Mix        | hardlight, hardmix, interpolation, linearlight, overlay,
                   | pinlight, softburn, softdodge, softlight, softlight2, vividlight
        -----------|--------------------------------------------------------------------------
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
    Dafault: false (for RGB all planes are always processed)

mask_first_plane:
-----------------
    When set to true, the first plane of the the mask clip will be used as a mask for all channels.
    Default: true

cplace:
-------
    Chroma location placement to use on the mask when resizing the chroma channels.
    Only applicable when mask_first_plane=true and for YUV420 and YUV422 colorspaces only.
      "mpeg1" : also known as "center", "jpeg" and "chromaloc type 1" chroma placement.
      "mpeg2" : also known as "left" and "chromaloc type 0" chroma placement, most consumer SD/HD formats use this.
      "topleft" : also known as "chromaloc type 2"; used on UHD formats and only available for YUV 4:2:0 colorspaces.
    Default: "mpeg2"

################################################################################
CHANGELOG
*********
Version      Date            Changes
1.2.0        2021/09/27      - mask_first_plane is ignored if the mask clip is a Y grayscale clip
                             - The chroma paramater now defaults to false for YUV clips
                             - Padding and cropping stage is bypassed when not needed
                             - A single frame mask is used when mask clip is undefined
                             - Correct output when all the following conditions are true:
                               * mask is not defined, opacity=1.0, x=0, y=0, and overlay clip is a smaller dimension than the base clip
                             - If the base clip is RGB or YUV444, the mask clip can be either YUV444 or RGB
1.1.0        2021/09/10      - Add support for all interleaved colorspaces (RBG24/32/48/64 and YUY2)
                             - Copy alpha channel from base clip when available
                             - Fix wrong output when opacity=1.0 and mask was not used and x or y > 0
                             - Add "cplace" parameter
                             - Cosmetics and other minor improvements
1.0.0        2021/09/01      - Initial release
*/


function OverlayPlus (clip base, clip overlay, clip "mask", string "mode", float "opacity", int "x", int "y", bool "chroma", bool "mask_first_plane", string "cplace")
{
    # Defaults
    msk     = default(mask,        Undefined)
    mode    = default(mode,          "blend")
    opacity = default(opacity,           1.0)
    x       = default(x,                   0)
    y       = default(y,                   0)
    chroma  = default(chroma,          false)
    mfp     = default(mask_first_plane, true)

    # Convert interleaved formats to planar and extract alpha from base
    alpha = (HasAlpha(base)) ? ExtractA(base) : false
    base  = (IsRGB(base) && IsInterleaved(base)) ? ConvertToPlanarRGB(base) : \
            (IsYUY2(base)) ? ConvertToYV16(base) : (HasAlpha(base)) ? RemoveAlphaPlane(base) : base
    over  = (IsRGB(overlay) && IsInterleaved(overlay)) ? ConvertToPlanarRGB(overlay) : \
            (IsYUY2(overlay)) ? ConvertToYV16(overlay) : (HasAlpha(overlay)) ? RemoveAlphaPlane(overlay) : overlay
    mask  = (Defined(msk) && IsRGB(msk) && IsInterleaved(msk)) ? ConvertToPlanarRGB(msk) : \
            (Defined(msk) && IsYUY2(msk)) ? ConvertToYV16(msk) : (Defined(msk) && HasAlpha(msk)) ? RemoveAlphaPlane(msk) : msk

    # Generate mask clip
    mfp  = (Defined(msk) && NumComponents(mask) != 1) ? mfp : true
    mask = (Defined(msk)) ? mask : Trim(over, 0, -1).mt_lut(expr="range_max", y=3, u=1, v=1) # white mask
    mask = (IsRGB(mask) && mfp==true) ? ExtractR(mask) : (IsYUV(mask) && mfp==true) ? ExtractY(mask) : mask

    # Dimensions and other checks
    IsSameSize = (Width(base) == Width(over) && Height(base) == Height(over)) ? true : false
    IsSmaller  = (Width(base) > Width(over) || Height(base) > Height(over)) ? true : false
    IsMask444  = (IsRGB(base) || Is444(base) && IsRGB(mask) || Is444(mask)) ? true : false

    # Sanity checks
    opacity = Min(Max(opacity, 0.0), 1.0)
    Assert(!IsYV411(base), "OverlayPlus: YV411 colorspace is not accepted")
    Assert(PixelType(base) == PixelType(over), "OverlayPlus: overlay clip must be the same colorspace as the base clip")
    Assert(mfp == true || isMask444 == true || PixelType(mask) == PixelType(base), "OverlayPlus: mask clip must be the same colorspace as the base clip")
    Assert(BitsPerComponent(base) == BitsPerComponent(mask), "OverlayPlus: mask clip must be the same bitdepth as the base clip")
    Assert(Width(over) == Width(mask) && Height(over) == Height(mask), "OverlayPlus: mask clip must be the same dimensions as the overlay clip")
    Assert(!Is420(base) || y%2 == 0, "OverlayPlus: the value of 'y' must be mod2")
    Assert(!Is420(base) || !Is422(base) && x%2 == 0, "OverlayPlus: the value of 'x' must be mod2")

    # Padding and cropping stage
    if (x > 0 || y > 0 || IsSameSize == false) {
        # Calculate padding sizes
        l = x
        r = base.Width - over.Width - x
        t = y
        b = base.Height - over.Height - y

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
        over = over.Crop(cl, ct, -cr, -cb)
        over = over.IsRGB ? over.AddBorders(pl, pt, pr, pb, color=$000000) : over.AddBorders(pl, pt, pr, pb, color_yuv=$000000)
        mask = mask.Crop(cl, ct, -cr, -cb)
        mask = mask.IsRGB ? mask.AddBorders(pl, pt, pr, pb, color=$000000) : mask.AddBorders(pl, pt, pr, pb, color_yuv=$000000)
    }

    # Range based on bitdepth
    if (BitsPerComponent(base) != 32) {
        ntrl = String(BitLShift(1, (BitsPerComponent(base) - 1))) # 128 ... 32768 - neutral
        peak = String(BitLShift(1, BitsPerComponent(base)) - 1)   # 255 ... 65535 - peak
        fctr = String(BitLShift(1, BitsPerComponent(base)))       # 256 ... 65536 - factor
    }
    else {
        ntrl = String(0.5)
        peak = String(1.0)
        fctr = String(1.0)
    }

    # Blending modes
    if (mode == "blend" || mode == "normal") {
        expr = ""
    }
    else if (mode == "add" || mode == "addition" || mode == "lineardodge") {
        expr = "x y +"
    }
    else if (mode == "average") {
        expr = "x y + 2 /"
    }
    else if (mode == "burn" || mode == "colorburn") {
        expr = "y 0 <= y "+peak+" "+peak+" x - "+fctr+" * y / - ?"
    }
    else if (mode == "darken") {
        expr = "x y min"
    }
    else if (mode == "difference") {
        expr = "x y - abs"
    }
    else if (mode == "divide") {
        expr = "y 0 <= "+peak+" "+peak+" x * y / ?"
    }
    else if (mode == "dodge" || mode == "colordodge") {
        expr = "y "+peak+" >= y x "+fctr+" * "+peak+" y - / ?"
    }
    else if (mode == "exclusion") {
        expr = "x y + 2 x * y * "+peak+" / -"
    }
    else if (mode == "extremity") {
        expr = ""+peak+" x - y - abs"
    }
    else if (mode == "freeze") {
        expr = "y 0 <= 0 "+peak+" "+peak+" x - dup * y / "+peak+" min - ?"
    }
    else if (mode == "glow") {
        expr = "x "+peak+" >= x y y * "+peak+" x - / ?"
    }
    else if (mode == "grainextract") {
        expr = "x y - "+ntrl+" +"
    }
    else if (mode == "grainmerge") {
        expr = "x y + "+ntrl+" -"
    }
    else if (mode == "hardlight") {
        expr = "y "+ntrl+" < 2 y x * "+peak+" / * "+peak+" 2 "+peak+" y - "+peak+" x - * "+peak+" / * - ?"
    }
    else if (mode == "hardmix") {
        expr = "x "+peak+" y - < 0 "+peak+" ?"
    }
    else if (mode == "heat") {
        expr = "x 0 <= 0 "+peak+" "+peak+" y - dup * x / "+peak+" min - ?"
    }
    else if (mode == "interpolation") {
        expr = ""+peak+" 0.5 pi x * "+peak+" / cos 4 / - pi y * "+peak+" / cos 4 / - *" # from Overlay_MTools
    }
    else if (mode == "lighten") {
        expr = "x y max"
    }
    else if (mode == "linearadd" || mode == "hypot") {
        expr = "x 2 ^ y 2 ^ + sqrt" # same as Gimp's 2.10 addition blending mode, aka as Nuke's "hypot"
    }
    else if (mode == "linearburn") {
        expr = "x y + "+peak+" < 0 x y + "+peak+" - ?" # from Overlay_MTools
    }
    else if (mode == "linearlight") {
        expr = "x "+ntrl+" < x 2 y * + "+peak+" - x 2 y "+ntrl+" - * + ?"
    }
    else if (mode == "linearsubtract") {
        expr = "x 2 ^ y 2 ^ - sqrt" # same as Gimp's 2.10 subtract blending mode
    }
    else if (mode == "multiply") {
        expr = "x y * "+peak+" /"
    }
    else if (mode == "multiply128") {
        expr = "x "+ntrl+" - y * "+ntrl+" 4 / / "+ntrl+" +" # from ffmpeg
    }
    else if (mode == "negation") {
        expr = ""+peak+" "+peak+" x - y - abs -"
    }
    else if (mode == "overlay") {
        expr = "x "+ntrl+" < 2 x y * "+peak+" / * "+peak+" 2 "+peak+" x - "+peak+" y - * "+peak+" / * - ?"
    }
    else if (mode == "phoenix") {
        expr = "x y min x y max - "+peak+" +"
    }
    else if (mode == "pinlight") {
        expr = "y "+ntrl+" < x 2 y * min x 2 y "+ntrl+" - * max ?"
    }
    else if (mode == "reflect") {
        expr = "y "+peak+" >= y x x * "+peak+" y - / ?"
    }
    else if (mode == "screen") {
        expr = ""+peak+" "+peak+" x - "+peak+" y - * "+peak+" / -"
    }
    else if (mode == "softburn") {
        expr = "x y + "+peak+" < x "+peak+" == x "+peak+" y * 2 "+peak+" x - * / ? y 0 == y "+peak+" "+peak+" x - "+peak+" * y 2 * / - ? ?" # from Overlay_MTools
    }
    else if (mode == "softdodge") {
        expr = "x y + "+peak+" < y "+peak+" == y x "+peak+" * 2 "+peak+" y - * / ? x 0 == x "+peak+" "+peak+" "+peak+" y - * 2 x * / - ? ?" # from Overlay_MTools
    }
    else if (mode == "softlight") {
        expr = "x "+peak+" / x y 2 * + x y * "+ntrl+" / - *" # from Overlay_MTools
    }
    else if (mode == "softlight2") {
        expr = "y "+ntrl+" > x "+peak+" x - y "+ntrl+" - * "+ntrl+" / 0.5 x "+ntrl+" - abs "+peak+" / - * + x x "+ntrl+" y - "+ntrl+" / * 0.5 x "+ntrl+" - abs "+peak+" / - * - ?"
    }
    else if (mode == "subtract") {
        expr = "x y -"
    }
    else if (mode == "vividlight") {
        expr = "y "+ntrl+" < y 0 <= 2 y * "+peak+" "+peak+" x - "+fctr+" * 2 y * / - ? 2 y "+ntrl+" - * "+peak+" >= 2 y "+ntrl+" - * x "+fctr+" * "+peak+" 2 y "+ntrl+" - * - / ? ?"
    }
    else {
        Assert(false, "OverlayPlus: invalid 'mode' specified")
    }

    # Process
    opac    = String(opacity)
    chroma  = (base.IsRgb || chroma==true) ? "process" : "copy"
    chromax = (chroma == "process") ? expr : ""
    mfp2    = (chroma == "process") ? mfp : false # bug in mt_merge; does not honor chroma copy if luma=true
    mask    = (opacity < 1.0) ? (mfp==true && mask.NumComponents!=1) ? Expr(mask, "x "+opac+" *", "") : Expr(mask, "x "+opac+" *") : mask
    over    = (mode != "blend" && mode != "normal") ? (base.NumComponents==1) ? Expr(base, over, expr) : Expr(base, over, expr, chromax) : over
    blend   = (!Defined(msk) && opacity==1.0 && x==0 && y==0 && !IsSmaller) ? over :  mt_merge(base, over, mask, chroma=chroma, luma=mfp2, cplace=cplace)

    return (IsClip(alpha)) ? AddAlphaPlane(blend, alpha) : blend
}
