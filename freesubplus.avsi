################################################################################
# FreeSubPlus v1.0.0 (2021/09/06)
# FreeSub() with additional colorspaces.
# http://avisynth.nl/index.php/FreeSubPlus
# author: reel.deel
#
# REQUIREMENTS
# ************
# AviSynth+ v3.7.0 or greater
# Masktools2 v2.2.26 or greater
# FreeSub v20180217 or greater
################################################################################

/*
SYNTAX and PARAMETERS
**********************
FreeSubPlus (clip input, string "text", int "x", int "y", int "first_frame", int "last_frame", string "font", int "size", int "text_color", int "halo_color", \
             int "align", int "lsp", int "font_width", int "halo_width", int "halo_height", string "matrix", string "chromaresample", string "chromaloc", string "output")

input:
------
    Input clip; all planar YUV/RGB colorspaces are supported (except YV411).
    RGB48/64 are also supported but output will be planar RGB.
    For 8-bit RGB is recommended to use FreeSub() as this script provides no benefits.

text:
-----
    Text to write.

x/y:
-----
    Anchor point.  Actual position of text also depends on alignment.
    Default: center of clip (width/2, height/2)

first_frame/last_frame:
-----------------------
    Frames to display subtitle on, inclusive.
    Default: first and last frame of the input clip.

font:
-----
    Path to BDF font file.  Can be relative to script location.

size:
-----
    Scales the height of the text by an integer multiple of its original size using a point resize.
    Default: 1

text_color/halo_color:
----------------------
    Text and halo color in ARGB. The first two hex values are for the alpha; 00 is opaque and ff is exactly transparent.
    Default: $20FFFFFF (text_color)
    Default: $20000000 (halo_color)

align:
------
    Controls the position of the text relative to the anchor point.  Based on the numeric keypad layout.
    1,4,7 are left aligned to the right of the anchor point.
    2,5,8 are centered (left to right) on the anchor point.
    3,6,9 are right aligned to the left of the anchor point.
    1,2,3 are bottom aligned to the top of the anchor point.
    4,5,6 are centered (top to bottom) on the anchor point.
    7,8,9 are top aligned to the bottom of the anchor point.
        +-----------------------+
        |   7   |   8   |   9   |
        +-----------------------+
        |   4   |   5   |   6   |
        +-----------------------+
        |   1   |   2   |   3   |
        +-----------------------+

    Default: 5

lsp:
----
    Setting any value for this turns on multiline mode, which displays multiple line text.
    Align properly understands this in both x and y directions.  0 uses the default line spacing.
    negative values put lines of text closer together, which can cause overwriting if things are too close.
    Positive values put the lines of text farther apart.  These units are multiplied by "size".
    Default: unset

font_width:
-----------
    Like "size", but in the horizontal direction.
    Default: same as size

halo_width:
-----------
    Draws a border around the text with this width.  Setting 0 effectively disables the border on the sides of text.
    Default: same as font_width

halo_height:
------------
    Draws a border around the text with this height.  Setting 0 effectively disables the border on the top and bottom of text.
    If both halo_width and halo_height are 0, there will be no border.
    Default: same as size

matrix:
-------
    Matrix to use on the subtitles for YUV colorspaces. To get accurate colors use the same matrix as the imput clip.
      "Rec601"  : Uses Rec.601 (SD) coefficients; limited range.
      "Rec709"  : Uses Rec.709 (HD) coefficients; limited scale range.
      "Rec2020" : Uses Rec.2020 (UHD) coefficients; limited scale range.
      "PC.601"  : Uses Rec.601 (SD) coefficients; full scale range.
      "PC.709"  : Uses Rec.709 (HD) coefficients; full scale range.
      "Average" : Uses averaged coefficients (the luma becomes the average of the RGB channels); full scale range.
    Default: "Rec709"

chromaresample:
---------------
    Resizer to use on the chroma planes when the colorspace of the input clip is YUV420 or YUV422.
    Available options: "point", "bilinear", "bicubic", "lanczos", "lanczos4", "blackman", "spline16", "spline36", "spline64", "gauss" and "sinc"
    Default: "bicubic"

chromaloc:
----------
    Chroma location placement to use for subsampled YUV420 colorspaces only.
      "mpeg1" : also known as "center" and "jpeg" chroma placement.
      "mpeg2" : also known as "left" chroma placement, most consumer SD/HD formats use this.
    Default: "mpeg2"

output:
-------
    Set to "mask" to output the subtitle mask.
    Default: "normal"
*/

function FreeSubPlus (clip input, string "text", int "x", int "y", int "first_frame", int "last_frame", string "font", int "size", int "text_color", int "halo_color", \
                      int "align", int "lsp", int "font_width", int "halo_width", int "halo_height", string "matrix", string "chromaresample", string "chromaloc", string "output")
{
    text_color = default(text_color, $20FFFFFF)
    halo_color = default(halo_color, $20000000)
    matrix     = default(matrix,      "Rec709")
    chromaloc  = default(chromaloc,    "mpeg2")
    output     = default(output,      "normal")

    tc_s = Hex(text_color, width=8)  # string
    tc_o = LeftStr(tc_s, 2)          # opacity
    tc_c = RightStr(tc_s, 6)         # color
    tcm  = HexValue(tc_o + "FFFFFF") # text_color for mask
    tcs  = HexValue("00" + tc_c)     # text_color for subs

    hc_s = Hex(halo_color, width=8)  # string
    hc_o = LeftStr(hc_s, 2)          # opacity
    hc_c = RightStr(hc_s, 6)         # color
    hcm  = HexValue(hc_o + "FFFFFF") # halo_color for mask
    hcs  = HexValue("00" + hc_c)     # halo_color for subs

    Assert(!IsYV411(input), "FreeSubPlus: YV411 colorspace is not supported")
    bits   = BitsPerComponent(input)
    fulls  = (IsRGB(input) || matrix=="PC.601" || matrix=="PC.709" || matrix=="Average") ? true : false
    mfp    = (IsRGB(input) || Is444(input)) ? true : false
    input  = (IsRGB(input) && IsInterleaved(input)) ? ConvertToPlanarRGB(input) : \
             (IsYUY2(input)) ? ConvertToYV16(input) : input
    input2 = (Is420(input)) ? ConvertToRGB24(input, matrix=matrix, chromaresample=chromaresample, ChromaInPlacement=chromaloc) : ConvertToRGB24(input, matrix=matrix, chromaresample=chromaresample)

    blank = Blankclip(input, pixel_type="RGB24", color=$000000)
    mask  = FreeSub(blank, text, x, y, first_frame, last_frame, font, size, tcm, hcm, align, lsp, font_width, halo_width, halo_height).ShowRed("Y8")
    mask  = (bits > 8) ? ConvertBits(mask, bits, fulls=true) : mask
    mask  = (Is422(input)) ? YToUV(mask,mask,mask).ConvertToYUV422(chromaresample=chromaresample) : \
            (Is420(input)) ? YToUV(mask,mask,mask).ConvertToYUV420(chromaresample=chromaresample, ChromaOutPlacement=chromaloc) : mask

    subs  = FreeSub(input2, text, x, y, first_frame, last_frame, font, size, tcs, hcs, align, lsp, font_width, halo_width, halo_height)
    subs  = (Is444(input)) ? ConvertToYUV444(subs, matrix=matrix)                                                              : \
            (Is422(input)) ? ConvertToYUV422(subs, matrix=matrix, chromaresample=chromaresample)                               : \
            (Is420(input)) ? ConvertToYUV420(subs, matrix=matrix, chromaresample=chromaresample, ChromaOutPlacement=chromaloc) : \
            (IsY(input)) ? ConvertToY(subs, matrix=matrix) : ConvertToPlanarRGB(subs)
    subs  = (bits > 8) ? ConvertBits(subs, bits, fulls=fulls) : subs

    merge = mt_merge(input, subs, mask, luma=mfp, y=3, u=3, v=3)
    return (output=="mask") ? mask : merge
}
