mod raylib
# Magma bindings for common raylib windowing, drawing, and input operations.
# Raylib itself is linked statically. Platform graphics and window-system
# libraries remain runtime dependencies of the generated executable.


use "std:c" as c
@platform("windows")
link "vendor/raylib/win/raylib.lib"
@platform("windows")
link "gdi32"
@platform("windows")
link "opengl32"
@platform("windows")
link "winmm"

@platform("linux")
link "vendor/raylib/linux/libraylib.a"
@platform("linux")
link ":libGL.so.1"
@platform("linux")
link ":libX11.so.6"
@platform("linux")
link "dl"
@platform("linux")
link "m"
@platform("linux")
link "pthread"
@platform("linux")
link "rt"

@platform("darwin")
link "vendor/raylib/mac/libraylib.a"
@platform("darwin")
link "framework:Cocoa"
@platform("darwin")
link "framework:CoreVideo"
@platform("darwin")
link "framework:IOKit"
@platform("darwin")
link "framework:OpenGL"

use "std:allocator" as alc
use "std:strings"   as strings
use "std:cast"      as cast

# ABI-safe public value types. Color is packed to a u32 before crossing the C
# boundary because Win64 passes this four-byte C struct as an integer value.
pub Color(r u8, g u8, b u8, a u8)

# Two-dimensional floating-point vector used for positions and dimensions.
# @example
#   position := raylib.Vector2(x=10.0, y=20.0)
pub Vector2(
    x f32
    y f32
)

# Axis-aligned floating-point rectangle described by its top-left position and size.
# @example
#   bounds := raylib.Rectangle(x=0.0, y=0.0, width=100.0, height=50.0)
pub Rectangle(
    x f32
    y f32
    width f32
    height f32
)

# GPU texture metadata used by Font atlases.
pub Texture(
    id u32
    width i32
    height i32
    mipmaps i32
    format i32
)

# CPU image metadata. The data pointer is owned by raylib when returned by a
# raylib loading function.
pub Image(
    data ptr
    width i32
    height i32
    mipmaps i32
    format i32
)

# Metrics and source image for one Unicode glyph.
pub GlyphInfo(
    value i32
    offsetX i32
    offsetY i32
    advanceX i32
    image Image
)

# Raylib font handle and atlas metadata.
pub Font(
    baseSize i32
    glyphCount i32
    glyphPadding i32
    texture Texture
    recs Rectangle*
    glyphs GlyphInfo*
)

ext ext_InitWindow InitWindow(width c.int, height c.int, title u8*) void
ext ext_CloseWindow CloseWindow() void
ext ext_WindowShouldClose WindowShouldClose() bool
ext ext_IsWindowReady IsWindowReady() bool
ext ext_IsWindowFullscreen IsWindowFullscreen() bool
ext ext_IsWindowHidden IsWindowHidden() bool
ext ext_IsWindowMinimized IsWindowMinimized() bool
ext ext_IsWindowMaximized IsWindowMaximized() bool
ext ext_IsWindowFocused IsWindowFocused() bool
ext ext_IsWindowResized IsWindowResized() bool
ext ext_SetWindowState SetWindowState(flags c.unsigned_int) void
ext ext_ClearWindowState ClearWindowState(flags c.unsigned_int) void
ext ext_ToggleFullscreen ToggleFullscreen() void
ext ext_MaximizeWindow MaximizeWindow() void
ext ext_MinimizeWindow MinimizeWindow() void
ext ext_RestoreWindow RestoreWindow() void
ext ext_SetWindowSize SetWindowSize(width c.int, height c.int) void
ext ext_GetScreenWidth GetScreenWidth() c.int
ext ext_GetScreenHeight GetScreenHeight() c.int
ext ext_GetRenderWidth GetRenderWidth() c.int
ext ext_GetRenderHeight GetRenderHeight() c.int

ext ext_SetTargetFPS SetTargetFPS(targetFps c.int) void
ext ext_GetFrameTime GetFrameTime() f32
ext ext_GetTime GetTime() f64
ext ext_GetFPS GetFPS() c.int

ext ext_BeginDrawing BeginDrawing() void
ext ext_EndDrawing EndDrawing() void
ext ext_ClearBackground ClearBackground(packedColor c.unsigned_int) void
ext ext_DrawPixel DrawPixel(x c.int, y c.int, packedColor c.unsigned_int) void
ext ext_DrawLine DrawLine(startX c.int, startY c.int, endX c.int, endY c.int, packedColor c.unsigned_int) void
ext ext_DrawCircle DrawCircle(centerX c.int, centerY c.int, radius f32, packedColor c.unsigned_int) void
ext ext_DrawRectangle DrawRectangle(x c.int, y c.int, width c.int, height c.int, packedColor c.unsigned_int) void
ext ext_DrawRectangleLines DrawRectangleLines(x c.int, y c.int, width c.int, height c.int, packedColor c.unsigned_int) void
ext ext_DrawText DrawText(text u8*, x c.int, y c.int, fontSize c.int, packedColor c.unsigned_int) void
ext ext_DrawFPS DrawFPS(x c.int, y c.int) void
ext ext_MeasureText MeasureText(text u8*, fontSize c.int) c.int

ext ext_GetFontDefault GetFontDefault() Font
ext ext_LoadFont LoadFont(fileName u8*) Font
ext ext_LoadFontEx LoadFontEx(fileName u8*, fontSize c.int, codepoints i32*, codepointCount c.int) Font
ext ext_LoadFontFromImage LoadFontFromImage(image Image, key Color, firstChar c.int) Font
ext ext_LoadFontFromMemory LoadFontFromMemory(fileType u8*, fileData u8*, dataSize c.int, fontSize c.int, codepoints i32*, codepointCount c.int) Font
ext ext_IsFontValid IsFontValid(font Font) bool
ext ext_UnloadFont UnloadFont(font Font) void
ext ext_ExportFontAsCode ExportFontAsCode(font Font, fileName u8*) bool
ext ext_DrawTextEx DrawTextEx(font Font, text u8*, position Vector2, fontSize f32, spacing f32, tint Color) void
ext ext_DrawTextPro DrawTextPro(font Font, text u8*, position Vector2, origin Vector2, rotation f32, fontSize f32, spacing f32, tint Color) void
ext ext_DrawTextCodepoint DrawTextCodepoint(font Font, codepoint c.int, position Vector2, fontSize f32, tint Color) void
ext ext_DrawTextCodepoints DrawTextCodepoints(font Font, codepoints i32*, codepointCount c.int, position Vector2, fontSize f32, spacing f32, tint Color) void
ext ext_SetTextLineSpacing SetTextLineSpacing(spacing c.int) void
ext ext_MeasureTextEx MeasureTextEx(font Font, text u8*, fontSize f32, spacing f32) Vector2
ext ext_GetGlyphIndex GetGlyphIndex(font Font, codepoint c.int) c.int
ext ext_GetGlyphInfo GetGlyphInfo(font Font, codepoint c.int) GlyphInfo
ext ext_GetGlyphAtlasRec GetGlyphAtlasRec(font Font, codepoint c.int) Rectangle

ext ext_IsKeyPressed IsKeyPressed(key c.int) bool
ext ext_IsKeyPressedRepeat IsKeyPressedRepeat(key c.int) bool
ext ext_IsKeyDown IsKeyDown(key c.int) bool
ext ext_IsKeyReleased IsKeyReleased(key c.int) bool
ext ext_IsKeyUp IsKeyUp(key c.int) bool
ext ext_GetKeyPressed GetKeyPressed() c.int
ext ext_GetCharPressed GetCharPressed() c.int
ext ext_SetExitKey SetExitKey(key c.int) void

ext ext_IsMouseButtonPressed IsMouseButtonPressed(button c.int) bool
ext ext_IsMouseButtonDown IsMouseButtonDown(button c.int) bool
ext ext_IsMouseButtonReleased IsMouseButtonReleased(button c.int) bool
ext ext_IsMouseButtonUp IsMouseButtonUp(button c.int) bool
ext ext_GetMouseX GetMouseX() c.int
ext ext_GetMouseY GetMouseY() c.int
ext ext_SetMousePosition SetMousePosition(x c.int, y c.int) void
ext ext_GetMouseWheelMove GetMouseWheelMove() f32
ext ext_ShowCursor ShowCursor() void
ext ext_HideCursor HideCursor() void
ext ext_IsCursorHidden IsCursorHidden() bool
ext ext_EnableCursor EnableCursor() void
ext ext_DisableCursor DisableCursor() void
ext ext_IsCursorOnScreen IsCursorOnScreen() bool

# Creates an RGBA color with straight 8-bit channels.
# @complexity O(1)
# @example
#   accent := raylib.color(30, 120, 255, 255)
pub color(r u8, g u8, b u8, a u8) Color:
    ret Color(r=r, g=g, b=b, a=a)
..

packColor(c Color) u32:
    packed u64 = cast.u8to64(c.r)
    packed = packed | (cast.u8to64(c.g) << 8)
    packed = packed | (cast.u8to64(c.b) << 16)
    packed = packed | (cast.u8to64(c.a) << 24)
    ret cast.u64to32(packed)
..

# Returns the canonical opaque light gray palette color.
# @complexity O(1)
# @example
#   tint := raylib.lightGray()
pub lightGray() Color: ret color(200, 200, 200, 255) ..
# Returns the canonical opaque medium gray palette color.
# @complexity O(1)
# @example
#   tint := raylib.gray()
pub gray() Color: ret color(130, 130, 130, 255) ..
# Returns the canonical opaque dark gray palette color.
# @complexity O(1)
# @example
#   tint := raylib.darkGray()
pub darkGray() Color: ret color(80, 80, 80, 255) ..
# Returns the canonical opaque yellow palette color.
# @complexity O(1)
# @example
#   tint := raylib.yellow()
pub yellow() Color: ret color(253, 249, 0, 255) ..
# Returns the canonical opaque gold palette color.
# @complexity O(1)
# @example
#   tint := raylib.gold()
pub gold() Color: ret color(255, 203, 0, 255) ..
# Returns the canonical opaque orange palette color.
# @complexity O(1)
# @example
#   tint := raylib.orange()
pub orange() Color: ret color(255, 161, 0, 255) ..
# Returns the canonical opaque pink palette color.
# @complexity O(1)
# @example
#   tint := raylib.pink()
pub pink() Color: ret color(255, 109, 194, 255) ..
# Returns the canonical opaque red palette color.
# @complexity O(1)
# @example
#   tint := raylib.red()
pub red() Color: ret color(230, 41, 55, 255) ..
# Returns the canonical opaque maroon palette color.
# @complexity O(1)
# @example
#   tint := raylib.maroon()
pub maroon() Color: ret color(190, 33, 55, 255) ..
# Returns the canonical opaque green palette color.
# @complexity O(1)
# @example
#   tint := raylib.green()
pub green() Color: ret color(0, 228, 48, 255) ..
# Returns the canonical opaque lime palette color.
# @complexity O(1)
# @example
#   tint := raylib.lime()
pub lime() Color: ret color(0, 158, 47, 255) ..
# Returns the canonical opaque dark green palette color.
# @complexity O(1)
# @example
#   tint := raylib.darkGreen()
pub darkGreen() Color: ret color(0, 117, 44, 255) ..
# Returns the canonical opaque sky blue palette color.
# @complexity O(1)
# @example
#   tint := raylib.skyBlue()
pub skyBlue() Color: ret color(102, 191, 255, 255) ..
# Returns the canonical opaque blue palette color.
# @complexity O(1)
# @example
#   tint := raylib.blue()
pub blue() Color: ret color(0, 121, 241, 255) ..
# Returns the canonical opaque dark blue palette color.
# @complexity O(1)
# @example
#   tint := raylib.darkBlue()
pub darkBlue() Color: ret color(0, 82, 172, 255) ..
# Returns the canonical opaque purple palette color.
# @complexity O(1)
# @example
#   tint := raylib.purple()
pub purple() Color: ret color(200, 122, 255, 255) ..
# Returns the canonical opaque violet palette color.
# @complexity O(1)
# @example
#   tint := raylib.violet()
pub violet() Color: ret color(135, 60, 190, 255) ..
# Returns the canonical opaque dark purple palette color.
# @complexity O(1)
# @example
#   tint := raylib.darkPurple()
pub darkPurple() Color: ret color(112, 31, 126, 255) ..
# Returns the canonical opaque beige palette color.
# @complexity O(1)
# @example
#   tint := raylib.beige()
pub beige() Color: ret color(211, 176, 131, 255) ..
# Returns the canonical opaque brown palette color.
# @complexity O(1)
# @example
#   tint := raylib.brown()
pub brown() Color: ret color(127, 106, 79, 255) ..
# Returns the canonical opaque dark brown palette color.
# @complexity O(1)
# @example
#   tint := raylib.darkBrown()
pub darkBrown() Color: ret color(76, 63, 47, 255) ..
# Returns opaque white.
# @complexity O(1)
# @example
#   tint := raylib.white()
pub white() Color: ret color(255, 255, 255, 255) ..
# Returns opaque black.
# @complexity O(1)
# @example
#   tint := raylib.black()
pub black() Color: ret color(0, 0, 0, 255) ..
# Returns fully transparent black.
# @complexity O(1)
# @example
#   tint := raylib.blank()
pub blank() Color: ret color(0, 0, 0, 0) ..
# Returns opaque magenta.
# @complexity O(1)
# @example
#   tint := raylib.magenta()
pub magenta() Color: ret color(255, 0, 255, 255) ..
# Returns raylib's warm off-white palette color.
# @complexity O(1)
# @example
#   tint := raylib.rayWhite()
pub rayWhite() Color: ret color(245, 245, 245, 255) ..

# Allocating UTF-8 wrapper intended for setup code. Hot drawing loops should
# convert stable text once with strings.toCstr and call drawTextC.
# @warning Call once before other window, drawing, or input functions.
# @complexity O(N) for title bytes plus platform initialization
# @example
#   raylib.initWindow(1280, 720, "Magma")
pub initWindow(width i32, height i32, title str) void:
    titleC u8* = strings.toCstrNoCopy(title)
    ext_InitWindow(width, height, titleC)
..

# Closes the window and releases raylib-managed graphics resources.
# @complexity O(1), excluding platform teardown
# @example
#   raylib.closeWindow()
pub closeWindow() void: ext_CloseWindow() ..
# Reports whether the user requested exit, including the configured exit key.
# @complexity O(1)
# @example
#   while raylib.windowShouldClose() == false:
pub windowShouldClose() bool: ret ext_WindowShouldClose() ..
# Reports whether window and graphics initialization completed successfully.
# @complexity O(1)
# @example
#   ready := raylib.isWindowReady()
pub isWindowReady() bool: ret ext_IsWindowReady() ..
# Reports whether the window is currently fullscreen.
# @complexity O(1)
pub isWindowFullscreen() bool: ret ext_IsWindowFullscreen() ..
# Reports whether the window is hidden.
# @complexity O(1)
pub isWindowHidden() bool: ret ext_IsWindowHidden() ..
# Reports whether the window is minimized.
# @complexity O(1)
pub isWindowMinimized() bool: ret ext_IsWindowMinimized() ..
# Reports whether the window is maximized.
# @complexity O(1)
pub isWindowMaximized() bool: ret ext_IsWindowMaximized() ..
# Reports whether the window has keyboard focus.
# @complexity O(1)
pub isWindowFocused() bool: ret ext_IsWindowFocused() ..
# Reports whether the client area was resized during the current frame.
# @complexity O(1)
pub isWindowResized() bool: ret ext_IsWindowResized() ..
# Enables one or more bitwise-combined window configuration flags.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowResizable())
pub setWindowState(flags u32) void: ext_SetWindowState(flags) ..
# Disables one or more bitwise-combined window configuration flags.
# @complexity O(1)
# @example
#   raylib.clearWindowState(raylib.flagWindowResizable())
pub clearWindowState(flags u32) void: ext_ClearWindowState(flags) ..
# Toggles between fullscreen and windowed display modes.
# @complexity O(1), excluding platform display reconfiguration
pub toggleFullscreen() void: ext_ToggleFullscreen() ..
# Requests the platform to maximize the window.
# @complexity O(1)
pub maximizeWindow() void: ext_MaximizeWindow() ..
# Requests the platform to minimize the window.
# @complexity O(1)
pub minimizeWindow() void: ext_MinimizeWindow() ..
# Restores a minimized or maximized window.
# @complexity O(1)
pub restoreWindow() void: ext_RestoreWindow() ..
# Changes the client-area size in screen pixels.
# @complexity O(1)
# @example
#   raylib.setWindowSize(1280, 720)
pub setWindowSize(width i32, height i32) void: ext_SetWindowSize(width, height) ..
# Returns the logical screen width in pixels.
# @complexity O(1)
pub screenWidth() i32: ret ext_GetScreenWidth() ..
# Returns the logical screen height in pixels.
# @complexity O(1)
pub screenHeight() i32: ret ext_GetScreenHeight() ..
# Returns the current framebuffer width, accounting for high-DPI scaling.
# @complexity O(1)
pub renderWidth() i32: ret ext_GetRenderWidth() ..
# Returns the current framebuffer height, accounting for high-DPI scaling.
# @complexity O(1)
pub renderHeight() i32: ret ext_GetRenderHeight() ..

# Sets the desired frame rate used by endDrawing() pacing; zero disables the limit.
# @complexity O(1)
# @example
#   raylib.setTargetFPS(60)
pub setTargetFPS(targetFps i32) void: ext_SetTargetFPS(targetFps) ..
# Returns seconds spent on the previous frame.
# @complexity O(1)
# @example
#   delta := raylib.frameTime()
pub frameTime() f32: ret ext_GetFrameTime() ..
# Returns seconds elapsed since initWindow().
# @complexity O(1)
# @example
#   elapsed := raylib.time()
pub time() f64: ret ext_GetTime() ..
# Returns raylib's recent frames-per-second estimate.
# @complexity O(1)
# @example
#   currentFps := raylib.fps()
pub fps() i32: ret ext_GetFPS() ..

# Begins one frame's drawing command sequence.
# @warning Every call must be paired with endDrawing() on the same thread.
# @complexity O(1)
# @example
#   raylib.beginDrawing()
pub beginDrawing() void: ext_BeginDrawing() ..
# Ends the frame, presents it, polls events, and applies target-FPS pacing.
# @complexity O(1) plus any configured frame wait
# @example
#   raylib.endDrawing()
pub endDrawing() void: ext_EndDrawing() ..
# Clears the current frame buffer to a solid color.
# @complexity O(1) command submission
# @example
#   raylib.clearBackground(raylib.black())
pub clearBackground(c Color) void: ext_ClearBackground(packColor(c)) ..
# Draws one pixel in screen coordinates.
# @complexity O(1)
pub drawPixel(x i32, y i32, c Color) void: ext_DrawPixel(x, y, packColor(c)) ..
# Draws a one-pixel-wide line between two screen coordinates.
# @complexity O(1) command submission
pub drawLine(startX i32, startY i32, endX i32, endY i32, c Color) void: ext_DrawLine(startX, startY, endX, endY, packColor(c)) ..
# Draws a filled circle with a pixel radius.
# @complexity O(1) command submission
pub drawCircle(centerX i32, centerY i32, radius f32, c Color) void: ext_DrawCircle(centerX, centerY, radius, packColor(c)) ..
# Draws a filled axis-aligned rectangle in screen coordinates.
# @complexity O(1) command submission
pub drawRectangle(x i32, y i32, width i32, height i32, c Color) void: ext_DrawRectangle(x, y, width, height, packColor(c)) ..
# Draws the outline of an axis-aligned rectangle.
# @complexity O(1) command submission
pub drawRectangleLines(x i32, y i32, width i32, height i32, c Color) void: ext_DrawRectangleLines(x, y, width, height, packColor(c)) ..
# Draws a null-terminated UTF-8 string without allocating.
# @warning text must remain valid through the call and contain a terminating zero byte.
# @complexity O(N) for text length
# @example
#   raylib.drawTextC(labelC, 20, 20, 24, raylib.white())
pub drawTextC(text u8*, x i32, y i32, fontSize i32, c Color) void: ext_DrawText(text, x, y, fontSize, packColor(c)) ..
# Draws the current FPS estimate at the given screen position.
# @complexity O(1)
pub drawFPS(x i32, y i32) void: ext_DrawFPS(x, y) ..
# Measures a null-terminated UTF-8 string using raylib's default font.
# @complexity O(N) for text length
# @example
#   width := raylib.measureTextC(labelC, 24)
pub measureTextC(text u8*, fontSize i32) i32: ret ext_MeasureText(text, fontSize) ..

# Draws a Magma string using the default font.
# @warning Embedded zero bytes terminate the displayed text early.
# @complexity O(N) for text length
# @example
#   raylib.drawText("Hello", 20, 20, 24, raylib.white())
pub drawText(text str, x i32, y i32, fontSize i32, c Color) void:
    textC u8* = strings.toCstrNoCopy(text)
    ext_DrawText(textC, x, y, fontSize, packColor(c))
..

# Returns the pixel width of a Magma string in the default font.
# @complexity O(N) for text length
# @example
#   width := raylib.measureText("Hello", 24)
pub measureText(text str, fontSize i32) i32:
    textC u8* = strings.toCstrNoCopy(text)
    width i32 = ext_MeasureText(textC, fontSize)
    ret width
..

# Returns raylib's default borrowed font. Do not pass it to unloadFont().
pub fontDefault() Font:
    ret ext_GetFontDefault()
..

# Loads a font file and uploads its atlas to the GPU.
pub loadFont(fileName str) Font:
    fileNameC u8* = strings.toCstrNoCopy(fileName)
    ret ext_LoadFont(fileNameC)
..

# Loads a font at a requested pixel height and optional Unicode codepoint set.
# Pass none and zero to load raylib's default character set.
pub loadFontEx(fileName str, fontSize i32, codepoints i32*, codepointCount i32) Font:
    fileNameC u8* = strings.toCstrNoCopy(fileName)
    ret ext_LoadFontEx(fileNameC, fontSize, codepoints, codepointCount)
..

# Loads a font from an image using the supplied key color.
pub loadFontFromImage(image Image, key Color, firstChar i32) Font:
    ret ext_LoadFontFromImage(image, key, firstChar)
..

# Loads a font from an encoded in-memory file buffer.
pub loadFontFromMemory(fileType str, fileData u8*, dataSize i32, fontSize i32, codepoints i32*, codepointCount i32) Font:
    fileTypeC u8* = strings.toCstrNoCopy(fileType)
    ret ext_LoadFontFromMemory(fileTypeC, fileData, dataSize, fontSize, codepoints, codepointCount)
..

# Reports whether CPU-side font data is valid. GPU texture validity is not checked.
pub isFontValid(font Font) bool:
    ret ext_IsFontValid(font)
..

# Releases a loaded font and its GPU atlas. Never unload fontDefault().
pub unloadFont(font Font) void:
    ext_UnloadFont(font)
..

# Exports a loaded font as a C source file.
pub exportFontAsCode(font Font, fileName str) bool:
    fileNameC u8* = strings.toCstrNoCopy(fileName)
    ret ext_ExportFontAsCode(font, fileNameC)
..

# Draws existing null-terminated UTF-8 text with a custom font.
pub drawTextExC(font Font, text u8*, position Vector2, fontSize f32, spacing f32, tint Color) void:
    ext_DrawTextEx(font, text, position, fontSize, spacing, tint)
..

# Draws a Magma UTF-8 string with a custom font.
pub drawTextEx(font Font, text str, position Vector2, fontSize f32, spacing f32, tint Color) void:
    textC u8* = strings.toCstrNoCopy(text)
    ext_DrawTextEx(font, textC, position, fontSize, spacing, tint)
..

# Draws custom-font text around an origin with rotation in degrees.
pub drawTextPro(font Font, text str, position Vector2, origin Vector2, rotation f32, fontSize f32, spacing f32, tint Color) void:
    textC u8* = strings.toCstrNoCopy(text)
    ext_DrawTextPro(font, textC, position, origin, rotation, fontSize, spacing, tint)
..

# Draws one Unicode codepoint with a custom font.
pub drawTextCodepoint(font Font, codepoint i32, position Vector2, fontSize f32, tint Color) void:
    ext_DrawTextCodepoint(font, codepoint, position, fontSize, tint)
..

# Draws an array of Unicode codepoints with a custom font.
pub drawTextCodepoints(font Font, codepoints i32*, codepointCount i32, position Vector2, fontSize f32, spacing f32, tint Color) void:
    ext_DrawTextCodepoints(font, codepoints, codepointCount, position, fontSize, spacing, tint)
..

# Sets extra vertical pixel spacing between lines containing line breaks.
pub setTextLineSpacing(spacing i32) void:
    ext_SetTextLineSpacing(spacing)
..

# Measures existing null-terminated UTF-8 text with a custom font.
pub measureTextExC(font Font, text u8*, fontSize f32, spacing f32) Vector2:
    ret ext_MeasureTextEx(font, text, fontSize, spacing)
..

# Returns the logical width and height of custom-font text.
pub measureTextEx(font Font, text str, fontSize f32, spacing f32) Vector2:
    textC u8* = strings.toCstrNoCopy(text)
    ret ext_MeasureTextEx(font, textC, fontSize, spacing)
..

# Returns a font's glyph index for a Unicode codepoint, falling back to '?'.
pub glyphIndex(font Font, codepoint i32) i32:
    ret ext_GetGlyphIndex(font, codepoint)
..

# Returns metrics and bitmap metadata for a Unicode codepoint.
pub glyphInfo(font Font, codepoint i32) GlyphInfo:
    ret ext_GetGlyphInfo(font, codepoint)
..

# Returns the glyph's source rectangle within the font atlas.
pub glyphAtlasRectangle(font Font, codepoint i32) Rectangle:
    ret ext_GetGlyphAtlasRec(font, codepoint)
..

# Reports whether key transitioned from up to down during the current frame.
# @complexity O(1)
# @example
#   pressed := raylib.isKeyPressed(raylib.keySpace())
pub isKeyPressed(key i32) bool: ret ext_IsKeyPressed(key) ..
# Reports whether key generated an operating-system repeat event this frame.
# @complexity O(1)
pub isKeyPressedRepeat(key i32) bool: ret ext_IsKeyPressedRepeat(key) ..
# Reports whether key is currently held down.
# @complexity O(1)
# @example
#   moving := raylib.isKeyDown(raylib.keyW())
pub isKeyDown(key i32) bool: ret ext_IsKeyDown(key) ..
# Reports whether key transitioned from down to up during the current frame.
# @complexity O(1)
pub isKeyReleased(key i32) bool: ret ext_IsKeyReleased(key) ..
# Reports whether key is currently not held down.
# @complexity O(1)
pub isKeyUp(key i32) bool: ret ext_IsKeyUp(key) ..
# Pops one key code from the pressed-key queue, or zero when empty.
# @complexity O(1)
# @example
#   key := raylib.keyPressed()
pub keyPressed() i32: ret ext_GetKeyPressed() ..
# Pops one Unicode codepoint from the text-input queue, or zero when empty.
# @complexity O(1)
# @example
#   codepoint := raylib.charPressed()
pub charPressed() i32: ret ext_GetCharPressed() ..
# Selects the key that makes windowShouldClose() report an exit request.
# @complexity O(1)
# @example
#   raylib.setExitKey(raylib.keyEscape())
pub setExitKey(key i32) void: ext_SetExitKey(key) ..

# Reports whether button transitioned from up to down during the current frame.
# @complexity O(1)
# @example
#   clicked := raylib.isMouseButtonPressed(raylib.mouseButtonLeft())
pub isMouseButtonPressed(button i32) bool: ret ext_IsMouseButtonPressed(button) ..
# Reports whether the mouse button is currently held down.
# @complexity O(1)
pub isMouseButtonDown(button i32) bool: ret ext_IsMouseButtonDown(button) ..
# Reports whether the mouse button transitioned to up this frame.
# @complexity O(1)
pub isMouseButtonReleased(button i32) bool: ret ext_IsMouseButtonReleased(button) ..
# Reports whether the mouse button is currently not held down.
# @complexity O(1)
pub isMouseButtonUp(button i32) bool: ret ext_IsMouseButtonUp(button) ..
# Returns the mouse cursor's logical x coordinate.
# @complexity O(1)
pub mouseX() i32: ret ext_GetMouseX() ..
# Returns the mouse cursor's logical y coordinate.
# @complexity O(1)
pub mouseY() i32: ret ext_GetMouseY() ..
# Moves the mouse cursor to the supplied logical screen coordinate.
# @complexity O(1)
pub setMousePosition(x i32, y i32) void: ext_SetMousePosition(x, y) ..
# Returns wheel movement accumulated for the current frame; positive is forward.
# @complexity O(1)
# @example
#   scroll := raylib.mouseWheelMove()
pub mouseWheelMove() f32: ret ext_GetMouseWheelMove() ..
# Makes the operating-system cursor visible.
# @complexity O(1)
pub showCursor() void: ext_ShowCursor() ..
# Hides the operating-system cursor.
# @complexity O(1)
pub hideCursor() void: ext_HideCursor() ..
# Reports whether the cursor is hidden.
# @complexity O(1)
pub isCursorHidden() bool: ret ext_IsCursorHidden() ..
# Enables and releases the cursor for normal desktop movement.
# @complexity O(1)
pub enableCursor() void: ext_EnableCursor() ..
# Disables and captures the cursor for relative-look controls.
# @complexity O(1)
pub disableCursor() void: ext_DisableCursor() ..
# Reports whether the cursor lies within the window's screen area.
# @complexity O(1)
pub isCursorOnScreen() bool: ret ext_IsCursorOnScreen() ..

# ConfigFlags values.
# Returns the ConfigFlags bit that requests vertical synchronization; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagVsyncHint())
pub flagVsyncHint() u32: ret 0x00000040 ..
# Returns the ConfigFlags bit that selects fullscreen mode; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagFullscreenMode())
pub flagFullscreenMode() u32: ret 0x00000002 ..
# Returns the ConfigFlags bit that allows user resizing; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowResizable())
pub flagWindowResizable() u32: ret 0x00000004 ..
# Returns the ConfigFlags bit that removes window decorations; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowUndecorated())
pub flagWindowUndecorated() u32: ret 0x00000008 ..
# Returns the ConfigFlags bit that starts with the window hidden; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowHidden())
pub flagWindowHidden() u32: ret 0x00000080 ..
# Returns the ConfigFlags bit that starts minimized; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowMinimized())
pub flagWindowMinimized() u32: ret 0x00000200 ..
# Returns the ConfigFlags bit that starts maximized; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowMaximized())
pub flagWindowMaximized() u32: ret 0x00000400 ..
# Returns the ConfigFlags bit that starts without focus; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowUnfocused())
pub flagWindowUnfocused() u32: ret 0x00000800 ..
# Returns the ConfigFlags bit that keeps the window topmost; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowTopmost())
pub flagWindowTopmost() u32: ret 0x00001000 ..
# Returns the ConfigFlags bit that continues updating while minimized; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowAlwaysRun())
pub flagWindowAlwaysRun() u32: ret 0x00000100 ..
# Returns the ConfigFlags bit that requests framebuffer transparency; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowTransparent())
pub flagWindowTransparent() u32: ret 0x00000010 ..
# Returns the ConfigFlags bit that enables high-DPI scaling; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowHighDpi())
pub flagWindowHighDpi() u32: ret 0x00002000 ..
# Returns the ConfigFlags bit that passes mouse input through; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagWindowMousePassthrough())
pub flagWindowMousePassthrough() u32: ret 0x00004000 ..
# Returns the ConfigFlags bit that selects borderless windowed mode; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagBorderlessWindowedMode())
pub flagBorderlessWindowedMode() u32: ret 0x00008000 ..
# Returns the ConfigFlags bit that requests 4x multisampling; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagMsaa4xHint())
pub flagMsaa4xHint() u32: ret 0x00000020 ..
# Returns the ConfigFlags bit that requests interlaced output; combine flags with bitwise OR.
# @complexity O(1)
# @example
#   raylib.setWindowState(raylib.flagInterlacedHint())
pub flagInterlacedHint() u32: ret 0x00010000 ..

# Common KeyboardKey values. Letters and digits use their ASCII values.
# Returns the keyboard code for Space.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keySpace())
pub keySpace() i32: ret 32 ..
# Returns the keyboard code for A.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyA())
pub keyA() i32: ret 65 ..
# Returns the keyboard code for D.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyD())
pub keyD() i32: ret 68 ..
# Returns the keyboard code for S.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyS())
pub keyS() i32: ret 83 ..
# Returns the keyboard code for W.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyW())
pub keyW() i32: ret 87 ..
# Returns the keyboard code for Escape.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyEscape())
pub keyEscape() i32: ret 256 ..
# Returns the keyboard code for Enter.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyEnter())
pub keyEnter() i32: ret 257 ..
# Returns the keyboard code for Tab.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyTab())
pub keyTab() i32: ret 258 ..
# Returns the keyboard code for Backspace.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyBackspace())
pub keyBackspace() i32: ret 259 ..
# Returns the keyboard code for Insert.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyInsert())
pub keyInsert() i32: ret 260 ..
# Returns the keyboard code for Delete.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyDelete())
pub keyDelete() i32: ret 261 ..
# Returns the keyboard code for Right.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyRight())
pub keyRight() i32: ret 262 ..
# Returns the keyboard code for Left.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyLeft())
pub keyLeft() i32: ret 263 ..
# Returns the keyboard code for Down.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyDown())
pub keyDown() i32: ret 264 ..
# Returns the keyboard code for Up.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyUp())
pub keyUp() i32: ret 265 ..
# Returns the keyboard code for Home.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyHome())
pub keyHome() i32: ret 268 ..
# Returns the keyboard code for End.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyEnd())
pub keyEnd() i32: ret 269 ..
# Returns the keyboard code for F1.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF1())
pub keyF1() i32: ret 290 ..
# Returns the keyboard code for F2.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF2())
pub keyF2() i32: ret 291 ..
# Returns the keyboard code for F3.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF3())
pub keyF3() i32: ret 292 ..
# Returns the keyboard code for F4.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF4())
pub keyF4() i32: ret 293 ..
# Returns the keyboard code for F5.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF5())
pub keyF5() i32: ret 294 ..
# Returns the keyboard code for F6.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF6())
pub keyF6() i32: ret 295 ..
# Returns the keyboard code for F7.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF7())
pub keyF7() i32: ret 296 ..
# Returns the keyboard code for F8.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF8())
pub keyF8() i32: ret 297 ..
# Returns the keyboard code for F9.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF9())
pub keyF9() i32: ret 298 ..
# Returns the keyboard code for F10.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF10())
pub keyF10() i32: ret 299 ..
# Returns the keyboard code for F11.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF11())
pub keyF11() i32: ret 300 ..
# Returns the keyboard code for F12.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyF12())
pub keyF12() i32: ret 301 ..
# Returns the keyboard code for LeftShift.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyLeftShift())
pub keyLeftShift() i32: ret 340 ..
# Returns the keyboard code for LeftControl.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyLeftControl())
pub keyLeftControl() i32: ret 341 ..
# Returns the keyboard code for LeftAlt.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyLeftAlt())
pub keyLeftAlt() i32: ret 342 ..
# Returns the keyboard code for RightShift.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyRightShift())
pub keyRightShift() i32: ret 344 ..
# Returns the keyboard code for RightControl.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyRightControl())
pub keyRightControl() i32: ret 345 ..
# Returns the keyboard code for RightAlt.
# @complexity O(1)
# @example
#   down := raylib.isKeyDown(raylib.keyRightAlt())
pub keyRightAlt() i32: ret 346 ..

# Returns the identifier for the primary left mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonLeft())
pub mouseButtonLeft() i32: ret 0 ..
# Returns the identifier for the secondary right mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonRight())
pub mouseButtonRight() i32: ret 1 ..
# Returns the identifier for the middle wheel mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonMiddle())
pub mouseButtonMiddle() i32: ret 2 ..
# Returns the identifier for the first side mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonSide())
pub mouseButtonSide() i32: ret 3 ..
# Returns the identifier for the extra side mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonExtra())
pub mouseButtonExtra() i32: ret 4 ..
# Returns the identifier for the browser-forward mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonForward())
pub mouseButtonForward() i32: ret 5 ..
# Returns the identifier for the browser-back mouse button.
# @complexity O(1)
# @example
#   down := raylib.isMouseButtonDown(raylib.mouseButtonBack())
pub mouseButtonBack() i32: ret 6 ..
