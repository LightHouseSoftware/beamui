/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.ansi_console.consoleapp;

import beamui.core.config;

// dfmt off
static if (BACKEND_CONSOLE):
// dfmt on
import beamui.core.geometry;
import beamui.core.logger;
import beamui.events.event;
import beamui.events.keyboard;
import beamui.events.pointer;
import beamui.events.wheel;
import beamui.graphics.bitmap;
import beamui.graphics.colors : Color;
import beamui.platforms.ansi_console.dconsole;
import beamui.platforms.common.platform;
import beamui.platforms.common.startup;
import beamui.text.consolefont;
import beamui.text.glyph : GlyphRef;

class ConsoleWindow : Window
{
    private
    {
        ConsolePlatform _platform;

        dstring _title;
    }

    this(ConsolePlatform platform, dstring caption, Window parent, WindowOptions options)
    {
        super(parent, options);
        _platform = platform;
        width = _platform.console.width;
        height = _platform.console.height;
        _windowRect = BoxI(0, 0, width, height);
        setDPI(10, 1);
    }

    override protected void cleanup()
    {
    }

    override @property dstring title() const
    {
        return _title;
    }

    override @property void title(dstring caption)
    {
        _title = caption;
    }

    override @property void icon(Bitmap icon)
    {
        // ignore
    }

    override protected void show()
    {
        _visible = true;
        handleWindowStateChange(WindowState.normal, BoxI(0, 0, _platform.console.width, _platform.console.height));
        update();
    }

    override void invalidate()
    {
        _platform.update();
    }

    override void close()
    {
        Log.d("ConsoleWindow.close()");
        _platform.closeWindow(this);
    }

    override void handleResize(int width, int height)
    {
        super.handleResize(width, height);
    }

    protected void redraw()
    {
    }

    //===============================================================

    override @property bool isActive() const
    {
        // todo
        return true;
    }

    private bool _visible;
    /// Returns true if window is shown
    @property bool visible()
    {
        return _visible;
    }

    override protected void scheduleSystemTimer(long timestamp)
    {
        // we poll timers manually
    }
}

class ConsolePlatform : Platform
{
    @property Console console()
    {
        return _console;
    }

    private
    {
        Console _console;
        WindowMap!(ConsoleWindow, size_t) windows;
        Bitmap _bitmap;
    }

    this(ref AppConf conf)
    {
        super(conf);

        _console = new Console;
        _console.batchMode = true;
        _console.onKeyEvent = &handleKey;
        _console.onMouseEvent = &handleMouse;
        _console.onWheelEvent = &handleWheel;
        _console.onResize = &handleResize;
        _console.onInputIdle = &handleInputIdle;
        _console.init();
        _console.setCursorType(ConsoleCursorType.hidden);
        _bitmap = Bitmap(1, 1, PixelFormat.cbf32);
    }

    ~this()
    {
        Log.d("Calling console.uninit");
        _console.uninit();
        Log.d("Destroying console");
        destroy(_console);
    }

    override Window createWindow(dstring title, Window parent,
            WindowOptions options = WindowOptions.resizable | WindowOptions.expanded,
            uint width = 0, uint height = 0)
    {
        auto res = new ConsoleWindow(this, title, parent, options);
        windows.add(res, windows.count);
        return res;
    }

    override void closeWindow(Window w)
    {
        windows.remove(cast(ConsoleWindow)w);
    }

    override protected int opApply(scope int delegate(size_t i, Window w) callback)
    {
        foreach (i, w; windows)
            if (const result = callback(i, w))
                break;
        return 0;
    }

    @property ConsoleWindow activeWindow()
    {
        return windows.last;
    }

    protected bool handleKey(KeyEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        if (w.dispatchKeyEvent(event))
        {
            _needRedraw = true;
            return true;
        }
        return false;
    }

    protected bool handleMouse(MouseEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        if (w.dispatchMouseEvent(event))
        {
            _needRedraw = true;
            return true;
        }
        return false;
    }

    protected bool handleWheel(WheelEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        w.dispatchWheelEvent(event);
        _needRedraw = true;
        return true;
    }

    protected bool handleResize(int width, int height)
    {
        _bitmap.resize(width, height);
        foreach (w; windows)
        {
            w.handleResize(width, height);
        }
        _needRedraw = true;
        return false;
    }

    private bool _needRedraw = true;
    void update()
    {
        _needRedraw = true;
    }

    protected void redraw()
    {
        if (!_needRedraw)
            return;
        foreach (w; windows)
        {
            if (w.visible)
            {
                _bitmap.fillRect(RectI(0, 0, w.width, w.height), w.backgroundColor);
                w.redraw();
                auto caretRect = w.caretRect;
                if (w is activeWindow)
                {
                    if (!caretRect.empty)
                    {
                        _console.setCursor(cast(int)caretRect.left, cast(int)caretRect.top);
                        _console.setCursorType(w.caretReplace ? ConsoleCursorType.replace : ConsoleCursorType.insert);
                    }
                    else
                    {
                        _console.setCursorType(ConsoleCursorType.hidden);
                    }
                    _console.setWindowCaption(w.title);
                }
            }
        }
        _needRedraw = false;
    }

    protected bool handleInputIdle()
    {
        foreach (w; windows)
        {
            w.pollTimers();
            w.handlePostedEvents();
        }
        redraw();
        _console.flush();
        windows.purge();
        return false;
    }

    override int runEventLoop()
    {
        Log.i("Entered message loop");
        while (_console.pollInput())
        {
            if (windows.count == 0)
            {
                Log.d("No windows - exiting message loop");
                break;
            }
        }
        windows.purge();
        Log.i("Exiting from message loop");
        return 0;
    }

    private dstring _clipboardText;

    override bool hasClipboardText(bool mouseBuffer = false)
    {
        return _clipboardText.length > 0;
    }

    override dstring getClipboardText(bool mouseBuffer = false)
    {
        return _clipboardText;
    }

    override void setClipboardText(dstring text, bool mouseBuffer = false)
    {
        _clipboardText = text;
    }

    private void handleCtrlC()
    {
        Log.w("Ctrl+C pressed - stopping application");
        if (_console)
        {
            _console.stop();
        }
    }
}
/+
class ANSIConsoleDrawBuf : ConsoleDrawBuf
{
    @property Console console() { return _console; }

    private Console _console;

    private struct RGB
    {
        int r;
        int g;
        int b;
        int match(int rr, int gg, int bb) immutable
        {
            int dr = rr - r;
            int dg = gg - g;
            int db = bb - b;
            if (dr < 0)
                dr = -dr;
            if (dg < 0)
                dg = -dg;
            if (db < 0)
                db = -db;
            return dr + dg + db;
        }
    }

    version (Windows)
    {
        // windows color table
        static immutable RGB[16] CONSOLE_COLORS_RGB = [
            RGB(0,0,0),
            RGB(0,0,128),
            RGB(0,128,0),
            RGB(0,128,128),
            RGB(128,0,0),
            RGB(128,0,128),
            RGB(128,128,0),
            RGB(192,192,192),
            RGB(0x7c,0x7c,0x7c), // ligth gray
            RGB(0,0,255),
            RGB(0,255,0),
            RGB(0,255,255),
            RGB(255,0,0),
            RGB(255,0,255),
            RGB(255,255,0),
            RGB(255,255,255),
        ];
    }
    else
    {
        // linux color table
        static immutable RGB[16] CONSOLE_COLORS_RGB = [
            RGB(0,0,0),
            RGB(128,0,0),
            RGB(0,128,0),
            RGB(128,128,0),
            RGB(0,0,128),
            RGB(128,0,128),
            RGB(0,128,128),
            RGB(192,192,192),
            RGB(0x7c,0x7c,0x7c), // ligth gray
            RGB(255,0,0),
            RGB(0,255,0),
            RGB(255,255,0),
            RGB(0,0,255),
            RGB(255,0,255),
            RGB(0,255,255),
            RGB(255,255,255),
        ];
    }

    static ubyte toConsoleColor(Color color, bool forBackground = false)
    {
        if (forBackground && color.a < 128)
            return CONSOLE_TRANSPARENT_BACKGROUND;
        int r = color.r;
        int g = color.g;
        int b = color.b;
        int bestMatch = CONSOLE_COLORS_RGB[0].match(r, g, b);
        int bestMatchIndex = 0;
        for (int i = 1; i < 16; i++)
        {
            int m = CONSOLE_COLORS_RGB[i].match(r, g, b);
            if (m < bestMatch)
            {
                bestMatch = m;
                bestMatchIndex = i;
            }
        }
        return cast(ubyte)bestMatchIndex;
    }

    static immutable dchar[512] SPACE_STRING = ' ';

    override void fillRect(RectI rc, Color color)
    {
        if (color.a < 128)
            return; // transparent
        _console.backgroundColor = toConsoleColor(color);
        if (applyClipping(rc))
        {
            int w = rc.width;
            foreach (y; rc.top .. rc.bottom)
            {
                _console.setCursor(rc.left, y);
                _console.writeText(SPACE_STRING[0 .. w]);
            }
        }
    }

    override void drawChar(int x, int y, dchar ch, Color color, Color bgcolor)
    {
        if (!clipRect.contains(x, y))
            return;
        ubyte tc = toConsoleColor(color, false);
        ubyte bc = toConsoleColor(bgcolor, true);
        dchar[1] text;
        text[0] = ch;
        _console.textColor = tc;
        _console.backgroundColor = bc;
        _console.setCursor(x, y);
        _console.writeText(cast(dstring)text);
    }
}
+/
extern (C) void mySignalHandler(int value)
{
    Log.i("Signal handler - signal = ", value);
    if (auto platform = cast(ConsolePlatform)platform)
        platform.handleCtrlC();
}

extern (C) Platform initPlatform(AppConf conf)
{
    version (Windows)
    {
        import core.sys.windows.winuser;

        DOUBLE_CLICK_THRESHOLD_MS = GetDoubleClickTime();
    }
    else
    {
        // set Ctrl+C handler
        import core.sys.posix.signal;

        sigset(SIGINT, &mySignalHandler);
    }

    conf.dialogDisplayModes = DialogDisplayMode.allTypesOfDialogsInPopup;
    return new ConsolePlatform(conf);
}
