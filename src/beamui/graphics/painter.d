/**
The main module for 2D painting.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.painter;

import std.algorithm.mutation : swap;
import std.math : ceil, floor, isFinite, PI, sqrt;

import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.linalg;
import beamui.core.math;
import beamui.core.types : Tup, tup;
import beamui.graphics.bitmap : Bitmap;
import beamui.graphics.brush : Brush;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing : BlendMode, CompositeMode;
import beamui.graphics.path;
import beamui.graphics.pen : PathIter, Pen;
import beamui.graphics.polygons : FillRule;
import beamui.text.glyph : GlyphRef;

enum MAX_DIMENSION = 2 ^^ 14;
enum MIN_RECT_I = RectI(MAX_DIMENSION, MAX_DIMENSION, -MAX_DIMENSION, -MAX_DIMENSION);
enum MIN_RECT_F = Rect(MAX_DIMENSION, MAX_DIMENSION, -MAX_DIMENSION, -MAX_DIMENSION);

/// Positioned glyph
struct GlyphInstance
{
    GlyphRef glyph;
    Point position;
}

/** Painter draws anti-aliased 2D vector shapes, as well as text and images.

    Painter applies clipping and transformation to all operations.
    It is layered and can use various blend modes to composite layers.

    Painter can save and restore it's current state (clipping, transformation,
    and anti-aliasing setting) using `save` method and when starting a layer.

    Note: Clipping always shrinks available drawing area.
*/
final class Painter
{
    private
    {
        bool active;
        PaintEngine engine;
        PaintEngine.State state;
        Buf!(PaintEngine.State) mainStack;
        Mat2x3 baseMatrix;

        Buf!SubPath bufContours;
        Path tempPath;

        Buf!RectI layerBounds;
    }

    this(ref PainterHead head)
    in (!head.painter)
    {
        head.painter = this;
    }

    /// True whether antialiasing is enabled for subsequent drawings
    @property bool antialias() nothrow const
    {
        return state.aa;
    }
    /// ditto
    @property void antialias(bool flag) nothrow
    in (active)
    {
        state.aa = flag;
    }

    //===============================================================
    // Clipping, transformations, and layer handling

    /// Intersect subsequent drawing with a region, transformed by current matrix
    void clipIn(Box box)
    in (active)
    {
        if (state.discard)
            return;
        if (box.empty)
            return discardSubsequent();

        const rect = Rect(box);
        const lt = Vec2(rect.left, rect.top);
        const rb = Vec2(rect.right, rect.bottom);
        const Vec2 v0 = state.mat * lt;
        const Vec2 v3 = state.mat * rb;
        const Vec2 diag0 = rb - lt;
        const Vec2 diag1 = v3 - v0;
        // a pure translation
        if (fequal2(diag0.x, diag1.x) && fequal2(diag0.y, diag1.y))
        {
            const r = RectI.from(Rect(v0, v3));
            state.clipRect.intersect(r);
        }
        else
        {
            const rt = Vec2(rect.right, rect.top);
            const lb = Vec2(rect.left, rect.bottom);
            const Vec2 v1 = state.mat * rt;
            const Vec2 v2 = state.mat * lb;
            const p0 = Vec2(min(v0.x, v1.x, v2.x, v3.x), min(v0.y, v1.y, v2.y, v3.y));
            const p1 = Vec2(max(v0.x, v1.x, v2.x, v3.x), max(v0.y, v1.y, v2.y, v3.y));
            const trBounds = RectI.from(Rect(p0, p1));
            state.clipRect.intersect(trBounds);

            // not axis-aligned
            if (!(fequal2(v0.y, v1.y) && fequal2(v0.x, v2.x)) && !(fequal2(v0.x, v1.x) && fequal2(v0.y, v2.y)))
            {
                // clip out complement triangles
                const Path.Command[3] cmds = Path.Command.lineTo;
                const Vec2[4] vs = [lt, rt, rb, lb];
                const subpath = SubPath(cmds, vs, false, rect);
                engine.geometryBBox = PaintEngine.BBox(rect, state.clipRect);
                engine.clipOut(mainStack.length, (&subpath)[0 .. 1], FillRule.nonzero, true);
            }
        }
        if (state.clipRect.empty)
            discardSubsequent();
    }
    /// ditto
    void clipIn(ref const Path path, FillRule rule = FillRule.nonzero)
    in (active)
    {
        if (state.discard)
            return;
        if (path.empty)
            return discardSubsequent();

        if (!prepareContours(path))
            return discardSubsequent();

        // limit drawing to path boundaries
        state.clipRect.intersect(engine.geometryBBox.screen);
        engine.clipOut(mainStack.length, bufContours[], rule, true);
    }

    /// Remove a region, transformed by current matrix, from subsequent drawing
    void clipOut(Box box)
    in (active)
    {
        if (box.empty || state.discard)
            return;

        const r = Rect(box);
        tempPath.reset();
        tempPath.moveTo(r.left, r.top);
        tempPath.lineTo(r.right, r.top).lineTo(r.right, r.bottom).lineTo(r.left, r.bottom);
        tempPath.close();

        if (!prepareContours(tempPath))
            return;

        engine.clipOut(mainStack.length, bufContours[], FillRule.evenodd, false);
    }
    /// ditto
    void clipOut(ref const Path path, FillRule rule = FillRule.nonzero)
    in (active)
    {
        if (path.empty || state.discard)
            return;

        if (!prepareContours(path))
            return;

        engine.clipOut(mainStack.length, bufContours[], rule, false);
    }

    /// Translate origin of the canvas
    void translate(float dx, float dy)
    in (active)
    {
        state.mat.translate(Vec2(dx, dy));
    }
    /// Rotate subsequent canvas drawings clockwise
    void rotate(float degrees)
    in (active)
    {
        state.mat.rotate(degrees * PI / 180);
    }
    /// Rotate subsequent canvas drawings clockwise around a point
    void rotate(float degrees, float cx, float cy)
    in (active)
    {
        const dx = state.mat.store[0][2] - cx; // TODO: make some deconstruction methods?
        const dy = state.mat.store[1][2] - cy;
        state.mat.translate(Vec2(-dx, -dy));
        state.mat.rotate(degrees * PI / 180);
        state.mat.translate(Vec2(dx, dy));
    }
    /// Scale subsequent canvas drawings
    void scale(float factor)
    in (active)
    {
        state.mat.scale(Vec2(factor, factor));
    }
    /// ditto
    void scale(float factorX, float factorY)
    in (active)
    {
        state.mat.scale(Vec2(factorX, factorY));
    }
    /// Skew subsequent canvas drawings by the given angles
    void skew(float degreesX, float degreesY)
    in (active)
    {
        state.mat.skew(Vec2(degreesX * PI / 180, -degreesY * PI / 180));
    }

    /// Concat a matrix to the current canvas transformation
    void transform(Mat2x3 m)
    in (active)
    {
        state.mat *= m;
    }
    /// Setup canvas transformation matrix, replacing current one
    void setMatrix(Mat2x3 m)
    in (active)
    {
        state.mat = baseMatrix * m;
    }
    /// Reset canvas transformation to identity
    void resetMatrix()
    in (active)
    {
        state.mat = baseMatrix;
    }

    /** Quickly (and inaccurately) determine that `box` is outside the clip.

        Use it to skip drawing complex elements when they aren't visible.
    */
    bool quickReject(Box box) const
    {
        const Mat2x3 m = state.mat;
        Rect tr = Rect(box);
        if (m.store[0][0] == 1 && m.store[0][1] == 0 && m.store[1][0] == 0 && m.store[1][1] == 1)
        {
            // translation only, fast path
            const tx = m.store[0][2];
            const ty = m.store[1][2];
            tr.translate(tx, ty);
        }
        else
        {
            const Vec2 v0 = m * Vec2(tr.left, tr.top);
            const Vec2 v1 = m * Vec2(tr.right, tr.top);
            const Vec2 v2 = m * Vec2(tr.left, tr.bottom);
            const Vec2 v3 = m * Vec2(tr.right, tr.bottom);
            // dfmt off
            tr = Rect(
                min(v0.x, v1.x, v2.x, v3.x),
                min(v0.y, v1.y, v2.y, v3.y),
                max(v0.x, v1.x, v2.x, v3.x),
                max(v0.y, v1.y, v2.y, v3.y),
            );
            // dfmt on
        }
        return !tr.intersects(Rect.from(state.clipRect));
    }

    /** Get bounds of clip, transformed into the local coordinate system.

        Use it to skip drawing complex elements when they aren't visible.
    */
    Rect getLocalClipBounds() const
    {
        if (state.clipRect.empty)
            return Rect.init;

        Rect r = Rect.from(state.clipRect);
        r.expand(1, 1); // antialiased fringe

        Mat2x3 m = state.mat;
        if (m.store[0][0] == 1 && m.store[0][1] == 0 && m.store[1][0] == 0 && m.store[1][1] == 1)
        {
            // translation only, fast path
            const tx = m.store[0][2];
            const ty = m.store[1][2];
            r.translate(-tx, -ty);
            return r;
        }
        else
        {
            m.invert();
            const Vec2 v0 = m * Vec2(r.left, r.top);
            const Vec2 v1 = m * Vec2(r.right, r.top);
            const Vec2 v2 = m * Vec2(r.left, r.bottom);
            const Vec2 v3 = m * Vec2(r.right, r.bottom);
            // dfmt off
            return Rect(
                min(v0.x, v1.x, v2.x, v3.x),
                min(v0.y, v1.y, v2.y, v3.y),
                max(v0.x, v1.x, v2.x, v3.x),
                max(v0.y, v1.y, v2.y, v3.y),
            );
            // dfmt on
        }
    }

    /** Save matrix, clip, and anti-aliasing setting into internal stack.

        Returns: Depth of the saved stack.

        Example:
        ---
        // `pr` is a painter instance
        {
            PaintSaver sv;
            pr.save(sv);
            pr.translate(100, 0);
            pr.fillRect(0, 0, 50, 50, NamedColor.green);
        } // translation is gone when `sv` goes out of scope
        pr.fillRect(0, 0, 50, 50, NamedColor.red);
        ---
    */
    int save(ref PaintSaver saver)
    in (active)
    in (!saver.painter, "Can't use PaintSaver twice")
    {
        saver.painter = this;
        saver.depth = mainStack.length;
        mainStack ~= state;
        return mainStack.length;
    }

    /** Start to draw into a new layer, and compose it when `saver` goes out of scope.

        Layers are a way to apply opacity and either `CompositeMode` or `BlendMode`
        to a collection of drawn shapes.

        Example:
        ---
        // `pr` is a painter instance
        const bg = Brush.fromSolid(NamedColor.white);
        pr.paintOut(bg);
        pr.translate(100, 100);
        {
            PaintSaver lsv;
            pr.beginLayer(lsv, 0.5f, BlendMode.difference);
            pr.fillCircle(0, 0, 50, NamedColor.red);
            pr.fillCircle(40, 0, 50, NamedColor.blue);
        }
        ---
    */
    void beginLayer(ref PaintSaver saver, float opacity)
    in (active)
    in (!saver.painter, "Can't use PaintSaver twice")
    {
        PaintEngine.LayerOp op;
        op.opacity = clamp(opacity, 0, 1);
        implBeginLayer(saver, op);
    }
    /// ditto
    void beginLayer(ref PaintSaver saver, float opacity, CompositeMode composition)
    in (active)
    in (!saver.painter, "Can't use PaintSaver twice")
    {
        PaintEngine.LayerOp op;
        op.opacity = clamp(opacity, 0, 1);
        op.composition = composition;
        implBeginLayer(saver, op);
    }
    /// ditto
    void beginLayer(ref PaintSaver saver, float opacity, BlendMode blending)
    in (active)
    in (!saver.painter, "Can't use PaintSaver twice")
    {
        PaintEngine.LayerOp op;
        op.opacity = clamp(opacity, 0, 1);
        op.blending = blending;
        implBeginLayer(saver, op);
    }

    private void implBeginLayer(ref PaintSaver sv, ref PaintEngine.LayerOp op)
    {
        if (state.discard)
            return;

        // save state
        sv.painter = this;
        sv.depth = mainStack.length;
        mainStack ~= state;
        layerBounds ~= MIN_RECT_I;

        // on certain modes we cannot skip transparent geometry and also must use a full-sized layer
        bool transparentPartsMatter;
        switch (op.composition) with (CompositeMode)
        {
        case copy:
        case sourceIn:
        case sourceOut:
        case destIn:
        case destAtop:
            transparentPartsMatter = true;
            break;
        default:
            break;
        }

        if (fzero6(op.opacity))
        {
            // we either discard the geometry or discard the whole layer
            discardSubsequent();
            if (!transparentPartsMatter)
                return;
        }

        // shift coordinates to the left-top corner of the clipping rectangle
        const BoxI clip = state.clipRect;
        assert(!clip.empty);
        state.clipRect.translate(-clip.x, -clip.y);
        state.mat = Mat2x3.translation(Vec2(-clip.x, -clip.y)) * state.mat;

        if (transparentPartsMatter)
            layerBounds.unsafe_ref(-1) = state.clipRect;

        mainStack.unsafe_ref(-1).layer = true;
        state.passTransparent = transparentPartsMatter; // doesn't propagate to sub-layers
        engine.beginLayer(clip, op);
    }

    private void discardSubsequent()
    {
        state.discard = true;
    }

    /// Restore matrix and clip state to `depth` call of `save`, compose layer
    private void restore(uint depth)
    {
        if (depth < mainStack.length)
        {
            foreach_reverse (i; depth .. mainStack.length)
            {
                state = mainStack[i];
                engine.restore(i);

                if (state.layer)
                {
                    RectI bounds = layerBounds[$ - 1];
                    engine.composeLayer(bounds);
                    layerBounds.shrink(1);
                    // parent layer should have at least that size
                    bounds.translate(state.clipRect.left, state.clipRect.top);
                    layerBounds.unsafe_ref(-1).include(bounds);

                    state.layer = false;
                }
            }
            mainStack.shrink(mainStack.length - depth);
        }
    }

    //===============================================================
    // Drawing commands

    /// Fill the layer with specified brush
    void paintOut(ref const Brush brush)
    in (active)
    {
        if (state.discard)
            return;
        if (!state.passTransparent && brush.isFullyTransparent)
            return;

        layerBounds.unsafe_ref(-1).include(state.clipRect);
        engine.paintOut(brush);
    }

    /// Fill a path using specified brush
    void fill(ref const Path path, ref const Brush brush, FillRule rule = FillRule.nonzero)
    in (active)
    {
        if (path.empty || state.discard)
            return;
        if (!state.passTransparent && brush.isFullyTransparent)
            return;

        if (!prepareContours(path))
            return;

        engine.fillPath(bufContours[], brush, rule);
    }

    /// Stroke a path using specified brush
    void stroke(ref const Path path, ref const Brush brush, Pen pen)
    in (active)
    {
        if (path.empty || state.discard)
            return;
        if (!state.passTransparent && brush.isFullyTransparent)
            return;

        if (pen.shouldScale)
        {
            // fade out very thin lines, taking transformation into account
            const origin = state.mat * Vec2(0);
            const coeffX = (state.mat * Vec2(1, 0) - origin).magnitudeSquared;
            const coeffY = (state.mat * Vec2(0, 1) - origin).magnitudeSquared;
            const coeff = sqrt(min(coeffX, coeffY));
            const realW = pen.width * coeff;
            if (fzero2(realW))
                return;
            if (realW < 1)
            {
                const opacity = brush.opacity * realW;
                if (!state.passTransparent && fzero2(opacity))
                    return;

                if (!prepareContours(path, pen.width / 2))
                    return;

                // make a shallow copy of the brush to change its opacity
                Brush br = brush;
                br.opacity = opacity;
                pen.width = 1.01f / coeff;
                const hairline = fequal2(coeffX, coeffY);
                engine.strokePath(bufContours[], br, pen, hairline);
            }
            else
            {
                if (!prepareContours(path, pen.width / 2))
                    return;

                engine.strokePath(bufContours[], brush, pen, false);
            }
        }
        else
        {
            if (fzero2(pen.width))
                return;
            // fade out very thin lines
            if (pen.width < 1)
            {
                const opacity = brush.opacity * pen.width;
                if (!state.passTransparent && fzero2(opacity))
                    return;

                if (!prepareContours(path, 0, 0.5f))
                    return;

                Brush br = brush;
                br.opacity = opacity;
                pen.width = 1;
                engine.strokePath(bufContours[], br, pen, true);
            }
            else
            {
                if (!prepareContours(path, 0, pen.width / 2))
                    return;

                engine.strokePath(bufContours[], brush, pen, false);
            }
        }
    }

    /** Draw a thin 1px line between two points (including the last pixel).

        No matter of transform, it will always be one pixel wide.
    */
    void drawLine(float x0, float y0, float x1, float y1, Color color)
    in (isFinite(x0) && isFinite(y0))
    in (isFinite(x1) && isFinite(y1))
    in (active)
    {
        if ((fequal2(x0, x1) && fequal2(y0, y1)) || state.discard)
            return;
        if (!state.passTransparent && color.isFullyTransparent)
            return;

        x0 += 0.5f;
        y0 += 0.5f;
        x1 += 0.5f;
        y1 += 0.5f;

        // no need to clip, they are thin lines anyway
        const RectI clip = state.clipRect;
        Rect bounds = Rect(x0, y0, x1, y1);
        if (bounds.left > bounds.right)
            swap(bounds.left, bounds.right);
        if (bounds.top > bounds.bottom)
            swap(bounds.top, bounds.bottom);

        layerBounds.unsafe_ref(-1).include(clip);

        const Path.Command[1] cmds = Path.Command.lineTo;
        const Vec2[2] ps = [Vec2(x0, y0), Vec2(x1, y1)];
        const subpath = SubPath(cmds, ps, false, bounds);
        engine.geometryBBox = PaintEngine.BBox(bounds, clip);

        const br = Brush.fromSolid(color);
        Pen pen = Pen(1);
        pen.shouldScale = false;
        engine.strokePath((&subpath)[0 .. 1], br, pen, true);
    }
    /// Fill a simple axis-oriented rectangle
    void fillRect(float x, float y, float width, float height, Color color)
    in (isFinite(x) && isFinite(y))
    in (isFinite(width) && isFinite(height))
    in (active)
    {
        if (fzero2(width) || fzero2(height) || state.discard)
            return;
        if (!state.passTransparent && color.isFullyTransparent)
            return;

        tempPath.reset();
        tempPath.moveTo(x, y);
        tempPath.lineTo(x + width, y).lineTo(x + width, y + height).lineTo(x, y + height);
        tempPath.close();

        if (!prepareContours(tempPath))
            return;

        const br = Brush.fromSolid(color);
        engine.fillPath(bufContours[], br, FillRule.evenodd);
    }
    /// Fill a triangle. Use it if you need to draw lone solid triangles
    void fillTriangle(Vec2 p0, Vec2 p1, Vec2 p2, Color color)
    in (isFinite(p0.magnitudeSquared))
    in (isFinite(p1.magnitudeSquared))
    in (isFinite(p2.magnitudeSquared))
    in (active)
    {
        if (state.discard)
            return;
        if (!state.passTransparent && color.isFullyTransparent)
            return;

        tempPath.reset();
        tempPath.moveTo(p0.x, p0.y).lineTo(p1.x, p1.y).lineTo(p2.x, p2.y).close();

        if (!prepareContours(tempPath))
            return;

        const br = Brush.fromSolid(color);
        engine.fillPath(bufContours[], br, FillRule.evenodd);
    }
    /// Fill a circle
    void fillCircle(float centerX, float centerY, float radius, Color color)
    in (isFinite(centerX) && isFinite(centerY))
    in (isFinite(radius))
    in (active)
    {
        if (radius < 0 || fzero2(radius) || state.discard)
            return;
        if (!state.passTransparent && color.isFullyTransparent)
            return;

        const k = radius * 4.0f / 3.0f;
        const rect = Rect(centerX - radius, centerY - k, centerX + radius, centerY + k);

        tempPath.reset();
        tempPath.moveTo(rect.left, centerY);
        tempPath.cubicTo(rect.left, rect.top, rect.right, rect.top, rect.right, centerY);
        tempPath.cubicTo(rect.right, rect.bottom, rect.left, rect.bottom, rect.left, centerY);

        if (!prepareContours(tempPath))
            return;

        const br = Brush.fromSolid(color);
        engine.fillPath(bufContours[], br, FillRule.evenodd);
    }

    /// Draw an image at some position with some opacity
    void drawImage(const Bitmap image, float x, float y, float opacity)
    in (image)
    in (isFinite(x) && isFinite(y))
    in (isFinite(opacity))
    in (active)
    {
        if (state.discard)
            return;

        const w = image.width;
        const h = image.height;

        opacity = clamp(opacity, 0, 1);
        if (fzero6(opacity))
        {
            if (state.passTransparent)
            {
                // draw a transparent rectangle instead
                fillRect(x, y, w, h, Color.transparent);
            }
            return;
        }

        const local = Rect(x, y, x + w, y + h);
        const screen = transformRectAndClip(local);
        if (screen.empty)
            return;

        layerBounds.unsafe_ref(-1).include(screen);
        engine.geometryBBox = PaintEngine.BBox(local, screen);
        engine.drawImage(image, Vec2(x, y), opacity);
    }

    /// Draw a rescaled nine-patch image with some opacity
    void drawNinePatch(const Bitmap image, RectI srcRect, Rect dstRect, float opacity)
    in (image)
    in (image.hasNinePatch)
    in (isFinite(dstRect.width) && isFinite(dstRect.height))
    in (isFinite(opacity))
    in (active)
    {
        if (srcRect.empty || dstRect.empty || state.discard)
            return;
        if (fzero6(dstRect.width) || fzero6(dstRect.height))
            return;

        opacity = clamp(opacity, 0, 1);
        if (fzero6(opacity))
        {
            if (state.passTransparent)
            {
                // draw a transparent rectangle instead
                fillRect(dstRect.left, dstRect.top, dstRect.width, dstRect.height, Color.transparent);
            }
            return;
        }
        const screen = transformRectAndClip(dstRect);
        if (screen.empty)
            return;

        static void correctFrameBounds(ref int a1, ref int a2, ref float b1, ref float b2)
        {
            if (a1 > a2)
            {
                a1 = a2 = (a1 + a2) / 2;
            }
            if (b1 > b2)
            {
                b1 = b2 = (b1 + b2) / 2;
            }
        }

        const np = image.ninePatch;
        // dfmt off
        PaintEngine.NinePatchInfo info = {
            srcRect.left, srcRect.left + np.frame.left, srcRect.right - np.frame.right, srcRect.right,
            srcRect.top, srcRect.top + np.frame.top, srcRect.bottom - np.frame.bottom, srcRect.bottom,
            dstRect.left, dstRect.left + np.frame.left, dstRect.right - np.frame.right, dstRect.right,
            dstRect.top, dstRect.top + np.frame.top, dstRect.bottom - np.frame.bottom, dstRect.bottom,
        };
        // dfmt on
        correctFrameBounds(info.x1, info.x2, info.dst_x1, info.dst_x2);
        correctFrameBounds(info.y1, info.y2, info.dst_y1, info.dst_y2);

        layerBounds.unsafe_ref(-1).include(screen);
        engine.geometryBBox = PaintEngine.BBox(dstRect, screen);
        engine.drawNinePatch(image, info, opacity);
    }

    /// Draw a text run at some position with some color
    void drawText(const GlyphInstance[] run, Color color)
    in (active)
    {
        if (run.length == 0 || color.isFullyTransparent || state.discard)
            return;

        const local = computeTextRunBounds(run);
        const screen = transformRectAndClip(local);
        if (screen.empty)
            return;

        layerBounds.unsafe_ref(-1).include(screen);
        engine.geometryBBox = PaintEngine.BBox(local, screen);
        engine.drawText(run, color);
    }

    /// Fills `engine.geometryBBox` and `bufContours`
    private bool prepareContours(ref const Path path, float padding = 0, float trPadding = 0)
    in (!path.empty)
    in (isFinite(padding))
    in (isFinite(trPadding))
    {
        bufContours.clear();
        auto bbox = PaintEngine.BBox(MIN_RECT_F, MIN_RECT_I);

        const Mat2x3 m = state.mat;
        const RectI clip = state.clipRect;
        // dfmt off
        foreach (ref subpath; path)
        {
            Rect r = subpath.bounds;
            r.expand(padding, padding);
            const Vec2 v0 = m * Vec2(r.left, r.top);
            const Vec2 v1 = m * Vec2(r.right, r.top);
            const Vec2 v2 = m * Vec2(r.left, r.bottom);
            const Vec2 v3 = m * Vec2(r.right, r.bottom);
            Rect tr = Rect(
                min(v0.x, v1.x, v2.x, v3.x),
                min(v0.y, v1.y, v2.y, v3.y),
                max(v0.x, v1.x, v2.x, v3.x),
                max(v0.y, v1.y, v2.y, v3.y),
            );
            tr.expand(trPadding, trPadding);
            if (!fzero2(tr.width) && !fzero2(tr.height))
            {
                RectI box = RectI(
                    cast(int)floor(tr.left),
                    cast(int)floor(tr.top),
                    cast(int)ceil(tr.right),
                    cast(int)ceil(tr.bottom),
                );
                if (box.intersect(clip))
                {
                    bufContours ~= subpath;
                    bbox.local.include(r);
                    bbox.screen.include(box);
                }
            }
        }
        // dfmt on
        layerBounds.unsafe_ref(-1).include(bbox.screen);
        engine.geometryBBox = bbox;
        return bufContours.length > 0;
    }

    private RectI transformRectAndClip(Rect untr)
    {
        const Mat2x3 m = state.mat;
        const Vec2 v0 = m * Vec2(untr.left, untr.top);
        const Vec2 v1 = m * Vec2(untr.right, untr.top);
        const Vec2 v2 = m * Vec2(untr.left, untr.bottom);
        const Vec2 v3 = m * Vec2(untr.right, untr.bottom);
        // dfmt off
        const tr = Rect(
            min(v0.x, v1.x, v2.x, v3.x),
            min(v0.y, v1.y, v2.y, v3.y),
            max(v0.x, v1.x, v2.x, v3.x),
            max(v0.y, v1.y, v2.y, v3.y),
        );
        // dfmt on
        if (fzero2(tr.width) || fzero2(tr.height))
            return RectI.init;
        // dfmt off
        RectI box = RectI(
            cast(int)floor(tr.left),
            cast(int)floor(tr.top),
            cast(int)ceil(tr.right),
            cast(int)ceil(tr.bottom),
        );
        // dfmt on
        box.intersect(state.clipRect);
        return box;
    }

    static private Rect computeTextRunBounds(const GlyphInstance[] run)
    {
        Rect r = MIN_RECT_F;
        foreach (ref gi; run)
        {
            r.left = min(r.left, gi.position.x);
            r.top = min(r.top, gi.position.y);
            r.right = max(r.right, gi.position.x + gi.glyph.correctedBlackBoxX);
            r.bottom = max(r.bottom, gi.position.y + gi.glyph.blackBoxY);
        }
        return r;
    }
}

/** Controls and guards `Painter`'s frame cycle.

    Note: One who constructs painter and paint engine owns them.
*/
struct PainterHead
{
    private Painter painter;

    /// `dipSize` is in device-independent pixels, `ddpSize` is in physical pixels
    void beginFrame(PaintEngine paintEngine, Size dipSize, SizeI ddpSize, Color background)
    in (painter && !painter.active)
    in (paintEngine)
    in (0 < dipSize.w && dipSize.w < MAX_DIMENSION)
    in (0 < dipSize.h && dipSize.h < MAX_DIMENSION)
    in (0 < ddpSize.w && ddpSize.w < MAX_DIMENSION)
    in (0 < ddpSize.h && ddpSize.h < MAX_DIMENSION)
    {
        with (painter)
        {
            active = true;
            engine = paintEngine;
            state = PaintEngine.State.init;
            state.clipRect = RectI(0, 0, ddpSize.w, ddpSize.h);
            state.mat = baseMatrix = Mat2x3.scaling(Vec2(ddpSize.w / dipSize.w, ddpSize.h / dipSize.h));
            mainStack.clear();
            bufContours.clear();
            layerBounds.clear();
            layerBounds ~= MIN_RECT_I;
            engine.st = &state;
            engine.begin(PaintEngine.FrameConfig(dipSize, ddpSize, background));
        }
    }

    void endFrame()
    in (painter && painter.active)
    {
        with (painter)
        {
            active = false;
            restore(0);
            engine.end();
            engine.paint();
        }
    }

    void repaint()
    in (painter && !painter.active && painter.engine)
    {
        with (painter)
        {
            engine.paint();
        }
    }
}

/** Restores painter's state on destruction, usually when goes out of scope.

    Note: It is forbidden to use one saver twice.
*/
struct PaintSaver
{
    private Painter painter;
    private uint depth;

    private this(int);
    @disable this(this);

    ~this()
    {
        import core.stdc.stdlib : abort;
        import std.stdio : writeln;

        if (painter)
        {
            // FIXME: due to whatever cause, throwing an error inside a destructor may cause segfault
            try
            {
                painter.restore(depth);
            }
            catch (Error e)
            {
                writeln(e);
                abort();
            }
            painter = null;
        }
    }
}

/// Base for painting backends
abstract class PaintEngine
{
protected:
    struct FrameConfig
    {
        Size dipSize;
        SizeI ddpSize;
        Color background;
    }

    struct State
    {
        bool aa = true;
        /// Transformed and scaled
        RectI clipRect = RectI(-MAX_DIMENSION, -MAX_DIMENSION, MAX_DIMENSION, MAX_DIMENSION);
        /// Contains scaling
        Mat2x3 mat = Mat2x3.identity;

        bool layer;
        bool discard;
        bool passTransparent;
    }

    struct BBox
    {
        Rect local;
        RectI screen;
    }

    struct LayerOp
    {
        float opacity = 1;
        CompositeMode composition = CompositeMode.sourceOver;
        BlendMode blending = BlendMode.normal;
    }

    static class FlatteningContourIter : PathIter
    {
        private
        {
            const(SubPath)[] list;
            Mat2x3 mat;
            bool transform;
            Buf!Vec2 buf;
        }

        void recharge(const SubPath[] contours, ref const Mat2x3 mat, bool transform)
        {
            list = contours;
            this.mat = mat;
            this.transform = transform;
        }

        bool next(out const(Vec2)[] points, out bool closed)
        {
            const hasElements = list.length > 0;
            if (hasElements)
            {
                buf.clear();
                if (transform)
                    list[0].flatten!true(buf, mat);
                else
                    list[0].flatten!false(buf, mat);

                points = buf[];
                closed = list[0].closed;
                list = list[1 .. $];
            }
            return hasElements;
        }
    }

    struct NinePatchInfo
    {
        int x0, x1, x2, x3;
        int y0, y1, y2, y3;
        float dst_x0, dst_x1, dst_x2, dst_x3;
        float dst_y0, dst_y1, dst_y2, dst_y3;
    }

    // temporary state, just to use less parameters in methods
    const(State)* st;
    BBox geometryBBox;

    void begin(FrameConfig);
    void end();
    void paint();

    void beginLayer(BoxI, LayerOp);
    void composeLayer(RectI);

    void clipOut(uint, const SubPath[], FillRule, bool complement);
    void restore(uint);

    void paintOut(ref const Brush);
    void fillPath(const SubPath[], ref const Brush, FillRule);
    void strokePath(const SubPath[], ref const Brush, ref const Pen, bool hairline);

    void drawImage(ref const Bitmap, Vec2, float);
    void drawNinePatch(ref const Bitmap, ref const NinePatchInfo, float);
    void drawText(const GlyphInstance[], Color);
}
