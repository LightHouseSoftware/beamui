/**
Atlases and caches for images, rasterized glyphs, and gradients.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.textures;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import beamui.core.collections : Buf;
import beamui.core.geometry : BoxI, SizeI;
import beamui.core.math;
import beamui.graphics.atlas;
import beamui.graphics.bitmap : Bitmap;
import beamui.graphics.colors : Color;
import beamui.graphics.gl.api;
import beamui.graphics.gl.objects;
import beamui.text.glyph : GlyphRef;

package:

/// A sub-texture inside an atlas. Values behind `tex` and `texSize` may change during painting
struct TextureView
{
    const(TexId)* tex;
    const(SizeI)* texSize;
    BoxI box;

    bool empty() const nothrow
    {
        return !tex;
    }
}

private struct CachePage
{
    TexId tex;
    SizeI texSize;
    bool contentChanged;
}

/** Texture cache is an array of texture atlases for static image data.

    It allocates space for images, performs packing and uploading onto GPU,
    and removes them if the original image gets destroyed.
*/
struct TextureCache
{
    enum INITIAL_SIZE = SizeI(128, 128);
    enum MAX_SIZE = SizeI(4096, 4096);
    enum MAX_PAGES = 16;

    private AtlasList!(MAX_PAGES, MAX_SIZE, INITIAL_SIZE, true) atlas;
    private CachePage[MAX_PAGES] pages;

    @disable this(this);

    ~this()
    {
        Tex2D.unbind();
        foreach (ref p; pages)
        {
            if (p.tex.handle)
                Tex2D.del(p.tex);
        }
    }

    /// Get a view onto uploaded bitmap, or upload it if not done yet. The `bitmap` must not be empty
    TextureView getTexture(ref const Bitmap bitmap)
    in (bitmap)
    {
        const sz = SizeI(bitmap.width, bitmap.height);
        const res = atlas.findOrAdd(bitmap.id, &sz);
        if (res.error)
            return TextureView.init;

        CachePage* page = &pages[res.index];
        if (res.changed)
        {
            resize(*page, res.pageSize);
            upload(page.tex, res.box, bitmap.pixels!uint);
            page.contentChanged = true;
        }
        return TextureView(&page.tex, &page.texSize, res.box);
    }

    static private void resize(ref CachePage page, SizeI size)
    {
        if (page.texSize == size)
            return;

        TexId newTex;
        Tex2D.bind(newTex);
        Tex2D.setBasicParams(TexFiltering.smooth, TexMipmaps.yes, TexWrap.clamp);
        Tex2D.resize(size, 0, TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE));

        if (page.tex.handle)
        {
            // copy to a newly created texture
            Tex2D.copy(page.tex, page.texSize);
            Tex2D.del(page.tex);
        }
        Tex2D.unbind();
        page.tex = newTex;
        page.texSize = size;
    }

    private void upload(TexId tex, BoxI box, const uint* data)
    {
        // upload packed ARGB data as reversed BGRA.
        // this should work with any byte order
        const fmt = TexFormat(GL_BGRA, GL_RGBA8, GL_UNSIGNED_INT_8_8_8_8_REV);
        Tex2D.bind(tex);

        // erase the gaps to prevent edge artifacts
        static Buf!uint zeros;
        zeros.resize(max(box.w, box.h) + 2);
        const vEdge = box.x > 0;
        const hEdge = box.y > 0;
        if (vEdge)
        {
            const b = BoxI(box.x - 1, box.y, 1, box.h);
            Tex2D.uploadSubImage(b, 0, fmt, zeros[].ptr);
        }
        if (hEdge)
        {
            const b = vEdge ? BoxI(box.x - 1, box.y - 1, box.w + 2, 1) : BoxI(0, box.y - 1, box.w + 1, 1);
            Tex2D.uploadSubImage(b, 0, fmt, zeros[].ptr);
        }
        {
            const b = BoxI(box.x + box.w, box.y, 1, box.h);
            Tex2D.uploadSubImage(b, 0, fmt, zeros[].ptr);
        }
        {
            const b = vEdge ? BoxI(box.x - 1, box.y + box.h, box.w + 2, 1) : BoxI(0, box.y + box.h, box.w + 1, 1);
            Tex2D.uploadSubImage(b, 0, fmt, zeros[].ptr);
        }
        // upload the image
        Tex2D.uploadSubImage(box, 0, fmt, data);
        Tex2D.unbind();
    }

    void remove(uint id)
    {
        atlas.remove(id);
    }

    // called before rendering the frame
    void updateMipmaps()
    {
        foreach (ref p; pages)
        {
            if (p.contentChanged)
            {
                p.contentChanged = false;
                Tex2D.bind(p.tex);
                glGenerateMipmap(GL_TEXTURE_2D);
            }
        }
        Tex2D.unbind();
    }
}

/// Glyph cache is the same thing as `TextureCache`, but for glyph images
struct GlyphCache
{
nothrow:
    enum INITIAL_SIZE = SizeI(128, 128);
    enum MAX_SIZE = SizeI(2048, 2048);
    enum MAX_PAGES = 8;

    private AtlasList!(MAX_PAGES, MAX_SIZE, INITIAL_SIZE, true) atlas;
    private CachePage[MAX_PAGES] pages;

    @disable this(this);

    ~this()
    {
        Tex2D.unbind();
        foreach (ref p; pages)
        {
            if (p.tex.handle)
                Tex2D.del(p.tex);
        }
    }

    TextureView getTexture(GlyphRef glyph)
    in (glyph)
    {
        const sz = SizeI(glyph.blackBoxX, glyph.blackBoxY);
        const res = atlas.findOrAdd(glyph.id, &sz);
        if (res.error)
            return TextureView.init;

        CachePage* page = &pages[res.index];
        if (res.changed)
        {
            resize(*page, res.pageSize);
            upload(page.tex, res.box, glyph.glyph);
        }
        return TextureView(&page.tex, &page.texSize, res.box);
    }

    static private void resize(ref CachePage page, SizeI size)
    {
        if (page.texSize == size)
            return;

        TexId newTex;
        Tex2D.bind(newTex);
        Tex2D.setBasicParams(TexFiltering.smooth, TexMipmaps.no, TexWrap.clamp);
        Tex2D.resize(size, 0, TexFormat(GL_RED, GL_R8, GL_UNSIGNED_BYTE));

        if (page.tex.handle)
        {
            // copy to a newly created texture
            Tex2D.copy(page.tex, page.texSize);
            Tex2D.del(page.tex);
        }
        Tex2D.unbind();
        page.tex = newTex;
        page.texSize = size;
    }

    private void upload(TexId tex, BoxI box, const ubyte[] data)
    {
        Tex2D.bind(tex);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        Tex2D.uploadSubImage(box, 0, TexFormat(GL_RED, GL_R8, GL_UNSIGNED_BYTE), data.ptr);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        Tex2D.unbind();
    }

    void remove(uint id)
    {
        atlas.remove(id);
    }
}

enum MAX_STOPS = 16;
enum MAX_GRADIENTS = 1024;

struct ColorStopAtlas
{
nothrow:
    private TexId _tex;
    private uint _count;

    @disable this(this);

    void initialize()
    {
        Tex2D.bind(_tex);
        Tex2D.setBasicParams(TexFiltering.smooth, TexMipmaps.no, TexWrap.clamp);
        Tex2D.resize(SizeI(MAX_STOPS, MAX_GRADIENTS), 0, TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE));
        Tex2D.unbind();
    }

    ~this()
    {
        Tex2D.unbind();
        Tex2D.del(_tex);
    }

    TexId tex() const
    {
        return _tex;
    }

    uint add(ref const ColorStopAtlasRow row)
    {
        if (_count == MAX_GRADIENTS)
            return MAX_GRADIENTS - 1;

        const box = BoxI(0, _count, row.length, 1);
        const ptr = row.colors.ptr;
        Tex2D.bind(_tex);
        Tex2D.uploadSubImage(box, 0, TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE), ptr);
        Tex2D.unbind();

        return _count++;
    }

    void reset()
    {
        _count = 0;
    }
}

struct ColorStopAtlasRow
{
    private Color[MAX_STOPS] colors;
    private uint length;

    this(const Color[] cs) nothrow
    in (cs.length >= 2)
    {
        length = cast(uint)min(cs.length, MAX_STOPS);
        foreach (i, c; cs[0 .. length])
        {
            colors[i] = c.premultiplied;
        }
    }
}
