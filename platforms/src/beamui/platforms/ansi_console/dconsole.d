/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.ansi_console.dconsole;

import beamui.core.config;

// dfmt off
static if (BACKEND_CONSOLE):
// dfmt on
version (Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.wincon;
    import core.sys.windows.winuser;
    import core.sys.windows.basetyps, core.sys.windows.w32api, core.sys.windows.winnt;
}
import std.stdio;
import std.utf;
import beamui.core.logger;
import beamui.core.signals;
import beamui.events.keyboard;
import beamui.events.pointer;
import beamui.events.wheel;

/// Console cursor type
enum ConsoleCursorType
{
    hidden, /// Hidden
    insert, /// Insert (usually underscore)
    replace, /// Replace (usually square)
}

version (Windows)
{
}
else
{
    import core.sys.posix.signal;

    private __gshared bool SIGHUP_flag;
    private extern (C) void signalHandler_SIGHUP(int) nothrow @nogc @system
    {
        SIGHUP_flag = true;
    }

    void setSignalHandlers()
    {
        signal(SIGHUP, &signalHandler_SIGHUP);
    }
}

/// Console I/O support
class Console
{
    // dfmt off
    @property
    {
        int width() const { return _width; }
        int height() const { return _height; }
    }
    // dfmt on

    private
    {
        int _cursorX;
        int _cursorY;
        int _width;
        int _height;

        version (Windows)
        {
            WORD _attr = WORD.max;
            immutable ushort COMMON_LVB_UNDERSCORE = 0x8000;
        }
        else
        {
            uint _attr = uint.max;
        }
        bool _stopped;
    }

    version (Windows)
    {
        HANDLE _hstdin;
        HANDLE _hstdout;
    }
    else
    {
        immutable int READ_BUF_SIZE = 1024;
        char[READ_BUF_SIZE] readBuf;
        int readBufPos = 0;
        bool isSequenceCompleted()
        {
            if (!readBufPos)
                return false;
            if (readBuf[0] == 0x1B)
            {
                if (readBufPos > 1 && readBuf[1] == '[' && readBuf[2] == 'M')
                    return readBufPos >= 6;
                for (int i = 1; i < readBufPos; i++)
                {
                    char ch = readBuf[i];
                    if (ch == 'O' && i == readBufPos - 1)
                        continue;
                    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '@' || ch == '~')
                        return true;
                }
                return false;
            }
            if (readBuf[0] & 0x80)
            {
                if ((readBuf[0] & 0xE0) == 0xC0)
                    return readBufPos >= 2;
                if ((readBuf[0] & 0xF0) == 0xE0)
                    return readBufPos >= 3;
                if ((readBuf[0] & 0xF8) == 0xF0)
                    return readBufPos >= 4;
                if ((readBuf[0] & 0xFC) == 0xF8)
                    return readBufPos >= 5;
                return readBufPos >= 6;
            }
            return true;
        }

        string rawRead(int pollTimeout = 3000)
        {
            if (_stopped)
                return null;
            import core.thread;
            import core.stdc.errno;

            int waitTime = 0;
            int startPos = readBufPos;
            while (readBufPos < READ_BUF_SIZE)
            {
                import core.sys.posix.unistd;

                char ch = 0;
                int res = cast(int)read(STDIN_FILENO, &ch, 1);
                if (res < 0)
                {
                    auto err = errno;
                    switch (err)
                    {
                    case EBADF:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EFAULT:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EINVAL:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EIO:
                        Log.e("rawRead stdin EIO - stopping terminal");
                        _stopped = true;
                        return null;
                    default:
                        break;
                    }
                }
                if (res <= 0)
                {
                    if (readBufPos == startPos && waitTime < pollTimeout)
                    {
                        Thread.sleep(dur!("msecs")(10));
                        waitTime += 10;
                        continue;
                    }
                    break;
                }
                readBuf[readBufPos++] = ch;
                if (isSequenceCompleted())
                    break;
            }
            if (readBufPos > 0 && isSequenceCompleted())
            {
                string s = readBuf[0 .. readBufPos].dup;
                readBufPos = 0;
                return s;
            }
            return null;
        }

        bool rawWrite(string s)
        {
            import core.sys.posix.unistd;
            import core.stdc.errno;

            int res = cast(int)write(STDOUT_FILENO, s.ptr, s.length);
            if (res < 0)
            {
                auto err = errno;
                while (err == EAGAIN)
                {
                    //debug Log.d("rawWrite error EAGAIN - will retry");
                    res = cast(int)write(STDOUT_FILENO, s.ptr, s.length);
                    if (res >= 0)
                        return res > 0;
                    err = errno;
                }
                Log.e("rawWrite error ", err, " - stopping terminal");
                _stopped = true;
            }
            return res > 0;
        }
    }

    version (Windows)
    {
        DWORD savedStdinMode;
        DWORD savedStdoutMode;
    }
    else
    {
        import core.sys.posix.termios;
        import core.sys.posix.fcntl;
        import core.sys.posix.sys.ioctl;

        termios savedStdinState;
    }

    void uninit()
    {
        version (Windows)
        {
            SetConsoleMode(_hstdin, savedStdinMode);
            SetConsoleMode(_hstdout, savedStdoutMode);
        }
        else
        {
            import core.sys.posix.unistd;

            tcsetattr(STDIN_FILENO, TCSANOW, &savedStdinState);
            // reset terminal state
            rawWrite("\033c");
            // reset attributes
            rawWrite("\x1b[0m");
            // clear screen
            rawWrite("\033[2J");
            // normal cursor
            rawWrite("\x1b[?25h");
            // set auto wrapping mode
            rawWrite("\x1b[?7h");
        }
    }

    bool initialize()
    {
        version (Windows)
        {
            _hstdin = GetStdHandle(STD_INPUT_HANDLE);
            if (_hstdin == INVALID_HANDLE_VALUE)
                return false;
            _hstdout = GetStdHandle(STD_OUTPUT_HANDLE);
            if (_hstdout == INVALID_HANDLE_VALUE)
                return false;
            CONSOLE_SCREEN_BUFFER_INFO csbi;
            if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
            {
                if (!AllocConsole())
                {
                    return false;
                }
                _hstdin = GetStdHandle(STD_INPUT_HANDLE);
                _hstdout = GetStdHandle(STD_OUTPUT_HANDLE);
                if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
                {
                    return false;
                }
                //printf( "GetConsoleScreenBufferInfo failed: %lu\n", GetLastError());
            }
            // update console modes
            immutable DWORD ENABLE_QUICK_EDIT_MODE = 0x0040;
            immutable DWORD ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
            immutable DWORD ENABLE_LVB_GRID_WORLDWIDE = 0x0010;
            DWORD mode = 0;
            GetConsoleMode(_hstdin, &mode);
            savedStdinMode = mode;
            mode = mode & ~ENABLE_ECHO_INPUT;
            mode = mode & ~ENABLE_LINE_INPUT;
            mode = mode & ~ENABLE_QUICK_EDIT_MODE;
            mode |= ENABLE_PROCESSED_INPUT;
            mode |= ENABLE_MOUSE_INPUT;
            mode |= ENABLE_WINDOW_INPUT;
            SetConsoleMode(_hstdin, mode);
            GetConsoleMode(_hstdout, &mode);
            savedStdoutMode = mode;
            mode = mode & ~ENABLE_PROCESSED_OUTPUT;
            mode = mode & ~ENABLE_WRAP_AT_EOL_OUTPUT;
            mode = mode & ~ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            mode |= ENABLE_LVB_GRID_WORLDWIDE;
            SetConsoleMode(_hstdout, mode);

            _cursorX = csbi.dwCursorPosition.X;
            _cursorY = csbi.dwCursorPosition.Y;
            _width = csbi.srWindow.Right - csbi.srWindow.Left + 1; // csbi.dwSize.X;
            _height = csbi.srWindow.Bottom - csbi.srWindow.Top + 1; // csbi.dwSize.Y;
            _attr = csbi.wAttributes;
            _textColor = _attr & 0x0F;
            _backgroundColor = (_attr & 0xF0) >> 4;
            _underline = (_attr & COMMON_LVB_UNDERSCORE) != 0;
            //writeln("csbi=", csbi);
        }
        else
        {
            import core.sys.posix.unistd;

            if (!isatty(1))
                return false;
            setSignalHandlers();
            fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
            termios ttystate;
            //get the terminal state
            tcgetattr(STDIN_FILENO, &ttystate);
            savedStdinState = ttystate;
            //turn off canonical mode
            ttystate.c_lflag &= ~ICANON;
            ttystate.c_lflag &= ~ECHO;
            //minimum of number input read.
            ttystate.c_cc[VMIN] = 1;
            //set the terminal attributes.
            tcsetattr(STDIN_FILENO, TCSANOW, &ttystate);

            winsize w;
            ioctl(0, TIOCGWINSZ, &w);
            _width = w.ws_col;
            _height = w.ws_row;

            _cursorX = 0;
            _cursorY = 0;

            _textColor = 7;
            _backgroundColor = 0;
            _underline = false;
            // enable mouse tracking - all events
            rawWrite("\033[?1003h");
            //rawWrite("\x1b[c");
            //string termType = rawRead();
            //Log.d("Term type=", termType);
        }
        return true;
    }

    /// Clear screen and set cursor position to 0,0
    void clearScreen()
    {
        version (Windows)
        {
            _attr = 0;
            DWORD charsWritten;
            FillConsoleOutputCharacter(_hstdout, ' ', _width * _height, COORD(0, 0), &charsWritten);
            FillConsoleOutputAttribute(_hstdout, 0, _width * _height, COORD(0, 0), &charsWritten);
        }
        else
        {
            _attr = 0;
            rawWrite("\033[2J");
        }
        setCursor(0, 0);
    }

    /// Set cursor position
    void setCursor(int x, int y)
    {
        rawSetCursor(x, y);
        _cursorX = x;
        _cursorY = y;
    }

    /// Write text string directly onto screen, moving cursor
    void writeText(const dchar[] str, ubyte textColor, ubyte backgroundColor, bool underline)
    {
        if (!str.length)
            return;

        rawSetAttributes(textColor, backgroundColor, underline);
        rawWriteText(str);

        foreach (i; 0 .. str.length)
        {
            if (_cursorX >= _width)
            {
                _cursorX = 0;
                _cursorY++;
                if (_cursorY >= _height)
                {
                    _cursorY = _height - 1;
                }
            }
            _cursorX++;
            if (_cursorX >= _width)
            {
                if (_cursorY < _height - 1)
                {
                    _cursorX = 0;
                    _cursorY++;
                }
            }
        }
    }

    protected void rawSetCursor(int x, int y)
    {
        version (Windows)
        {
            SetConsoleCursorPosition(_hstdout, COORD(cast(short)x, cast(short)y));
        }
        else
        {
            import core.stdc.stdio;
            import core.stdc.string;

            char[50] buf;
            sprintf(buf.ptr, "\x1b[%d;%dH", y + 1, x + 1);
            rawWrite(cast(string)(buf[0 .. strlen(buf.ptr)]));
        }
    }

    private dstring _windowCaption;
    void setWindowCaption(dstring str)
    {
        if (_windowCaption == str)
            return;
        _windowCaption = str;
        version (Windows)
        {
            SetConsoleTitle(toUTF16z(str));
        }
        else
        {
            // TODO: ANSI terminal caption
        }
    }

    private ConsoleCursorType _rawCursorType = ConsoleCursorType.insert;
    protected void rawSetCursorType(ConsoleCursorType type)
    {
        if (_rawCursorType == type)
            return;
        version (Windows)
        {
            CONSOLE_CURSOR_INFO ci;
            final switch (type) with (ConsoleCursorType)
            {
            case insert:
                ci.dwSize = 10;
                ci.bVisible = TRUE;
                break;
            case replace:
                ci.dwSize = 100;
                ci.bVisible = TRUE;
                break;
            case hidden:
                ci.dwSize = 10;
                ci.bVisible = FALSE;
                break;
            }
            SetConsoleCursorInfo(_hstdout, &ci);
        }
        else
        {
            final switch (type) with (ConsoleCursorType)
            {
            case insert:
                rawWrite("\x1b[?25h");
                break;
            case replace:
                rawWrite("\x1b[?25h");
                break;
            case hidden:
                rawWrite("\x1b[?25l");
                break;
            }
        }
        _rawCursorType = type;
    }

    private ConsoleCursorType _cursorType = ConsoleCursorType.insert;
    void setCursorType(ConsoleCursorType type)
    {
        _cursorType = type;
        rawSetCursorType(_cursorType);
    }

    protected void rawWriteText(const dchar[] str)
    {
        // use cursor position to break lines
        debug foreach (ch; str)
            assert(ch != '\n' && ch != '\r');

        version (Windows)
        {
            wstring s16 = toUTF16(str);
            DWORD charsWritten;
            WriteConsole(_hstdout, cast(const(void)*)s16.ptr, cast(uint)s16.length, &charsWritten, cast(void*)null);
        }
        else
        {
            string s8 = toUTF8(str);
            rawWrite(s8);
        }
    }

    private ubyte _textColor;
    private ubyte _backgroundColor;
    private bool _underline;

    protected void rawSetAttributes(ubyte textColor, ubyte backgroundColor, bool underline)
    {
        version (Windows)
        {
            const attr = cast(WORD)textColor | cast(WORD)backgroundColor << 4 | (underline ? COMMON_LVB_UNDERSCORE : 0);
            if (_attr == attr)
                return;
            _attr = attr;

            SetConsoleTextAttribute(_hstdout, attr);
        }
        else
        {
            import core.stdc.stdio;
            import core.stdc.string;

            const attr = cast(uint)textColor | cast(uint)backgroundColor << 8 | (underline ? 0x10000 : 0);
            if (_attr == attr)
                return;
            _attr = attr;

            const int textCol = (textColor & 7) + (textColor & 8 ? 90 : 30);
            const int bgCol = (backgroundColor & 7) + (backgroundColor & 8 ? 100 : 40);

            char[50] buf = 0;
            if (_textColor != textColor && _backgroundColor != backgroundColor)
                sprintf(buf.ptr, "\x1b[%d;%dm", textCol, bgCol);
            else if (_textColor != textColor && _backgroundColor == backgroundColor)
                sprintf(buf.ptr, "\x1b[%dm", textCol);
            else
                sprintf(buf.ptr, "\x1b[%dm", bgCol);

            rawWrite(cast(string)buf[0 .. strlen(buf.ptr)]);
        }

        _textColor = textColor;
        _backgroundColor = backgroundColor;
        _underline = underline;
    }

    protected void checkResize()
    {
        version (Windows)
        {
            CONSOLE_SCREEN_BUFFER_INFO csbi;
            if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
                return;

            _cursorX = csbi.dwCursorPosition.X;
            _cursorY = csbi.dwCursorPosition.Y;
            int w = csbi.srWindow.Right - csbi.srWindow.Left + 1; // csbi.dwSize.X;
            int h = csbi.srWindow.Bottom - csbi.srWindow.Top + 1; // csbi.dwSize.Y;
            if (_width != w || _height != h)
                handleConsoleResize(w, h);
        }
        else
        {
            import core.sys.posix.unistd;

            //import core.sys.posix.fcntl;
            //import core.sys.posix.termios;
            import core.sys.posix.sys.ioctl;

            winsize w;
            ioctl(STDIN_FILENO, TIOCGWINSZ, &w);
            if (_width != w.ws_col || _height != w.ws_row)
            {
                handleConsoleResize(w.ws_col, w.ws_row);
            }
        }
    }

    /// Keyboard event signal
    Listener!(bool delegate(KeyEvent)) onKeyEvent;
    /// Mouse event signal
    Listener!(bool delegate(MouseEvent)) onMouseEvent;
    /// Wheel event signal
    Listener!(bool delegate(WheelEvent)) onWheelEvent;
    /// Console size changed signal
    Listener!(bool delegate(int width, int height)) onResize;
    /// Console input is idle
    Listener!(bool delegate()) onInputIdle;

    protected bool handleKeyEvent(KeyEvent event)
    {
        return onKeyEvent(event);
    }

    protected bool handleMouseEvent(MouseEvent event)
    {
        ButtonDetails* pbuttonDetails;
        if (event.button == MouseButton.left)
            pbuttonDetails = &_lbutton;
        else if (event.button == MouseButton.right)
            pbuttonDetails = &_rbutton;
        else if (event.button == MouseButton.middle)
            pbuttonDetails = &_mbutton;
        if (pbuttonDetails)
        {
            if (event.action == MouseAction.buttonDown)
            {
                pbuttonDetails.down(event.x, event.y, event.mouseMods, event.keyMods);
            }
            else if (event.action == MouseAction.buttonUp)
            {
                pbuttonDetails.up(event.x, event.y, event.mouseMods, event.keyMods);
            }
        }
        event.lbutton = _lbutton;
        event.rbutton = _rbutton;
        event.mbutton = _mbutton;
        return onMouseEvent(event);
    }

    protected bool handleWheelEvent(WheelEvent event)
    {
        return onWheelEvent(event);
    }

    protected bool handleConsoleResize(int width, int height)
    {
        _width = width;
        _height = height;
        return onResize(width, height);
    }

    protected bool handleInputIdle()
    {
        checkResize();
        return onInputIdle();
    }

    private MouseMods lastMouseMods;
    private MouseButton lastButtonDown;

    protected ButtonDetails _lbutton;
    protected ButtonDetails _mbutton;
    protected ButtonDetails _rbutton;

    void stop()
    {
        // set stopped flag
        _stopped = true;
    }

    /// Wait for input, handle input
    bool pollInput()
    {
        if (_stopped)
        {
            debug Log.i("Console _stopped flag is set - returning false from pollInput");
            return false;
        }
        version (Windows)
        {
            INPUT_RECORD record;
            DWORD eventsRead;
            BOOL success = PeekConsoleInput(_hstdin, &record, 1, &eventsRead);
            if (!success)
            {
                DWORD err = GetLastError();
                _stopped = true;
                return false;
            }
            if (eventsRead == 0)
            {
                handleInputIdle();
                Sleep(1);
                return true;
            }
            success = ReadConsoleInput(_hstdin, &record, 1, &eventsRead);
            if (!success)
            {
                return false;
            }
            switch (record.EventType)
            {
            case KEY_EVENT:
                const action = record.KeyEvent.bKeyDown ? KeyAction.keyDown : KeyAction.keyUp;
                const key = cast(Key)record.KeyEvent.wVirtualKeyCode;
                const dchar ch = record.KeyEvent.UnicodeChar;
                const uint keyState = record.KeyEvent.dwControlKeyState;
                KeyMods mods;
                if (keyState & LEFT_ALT_PRESSED)
                    mods |= KeyMods.alt | KeyMods.lalt;
                if (keyState & RIGHT_ALT_PRESSED)
                    mods |= KeyMods.alt | KeyMods.ralt;
                if (keyState & LEFT_CTRL_PRESSED)
                    mods |= KeyMods.control | KeyMods.lcontrol;
                if (keyState & RIGHT_CTRL_PRESSED)
                    mods |= KeyMods.control | KeyMods.rcontrol;
                if (keyState & SHIFT_PRESSED)
                    mods |= KeyMods.shift;

                handleKeyEvent(new KeyEvent(action, key, mods));
                if (action == KeyAction.keyDown && ch)
                    handleKeyEvent(new KeyEvent(KeyAction.text, key, mods, [ch]));
                break;
            case MOUSE_EVENT:
                const short x = record.MouseEvent.dwMousePosition.X;
                const short y = record.MouseEvent.dwMousePosition.Y;
                const uint buttonState = record.MouseEvent.dwButtonState;
                const uint keyState = record.MouseEvent.dwControlKeyState;
                const uint eventFlags = record.MouseEvent.dwEventFlags;
                MouseMods mmods;
                KeyMods kmods;
                if ((keyState & LEFT_ALT_PRESSED) || (keyState & RIGHT_ALT_PRESSED))
                    kmods |= KeyMods.alt;
                if ((keyState & LEFT_CTRL_PRESSED) || (keyState & RIGHT_CTRL_PRESSED))
                    kmods |= KeyMods.control;
                if (keyState & SHIFT_PRESSED)
                    kmods |= KeyMods.shift;
                if (buttonState & FROM_LEFT_1ST_BUTTON_PRESSED)
                    mmods |= MouseMods.left;
                if (buttonState & FROM_LEFT_2ND_BUTTON_PRESSED)
                    mmods |= MouseMods.middle;
                if (buttonState & RIGHTMOST_BUTTON_PRESSED)
                    mmods |= MouseMods.right;
                bool actionSent;
                if (mmods != lastMouseMods)
                {
                    MouseButton btn = MouseButton.none;
                    MouseAction action = MouseAction.cancel;
                    if ((mmods & MouseMods.left) != (lastMouseMods & MouseMods.left))
                    {
                        btn = MouseButton.left;
                        action = (mmods & MouseMods.left) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if ((mmods & MouseMods.right) != (lastMouseMods & MouseMods.right))
                    {
                        btn = MouseButton.right;
                        action = (mmods & MouseMods.right) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if ((mmods & MouseMods.middle) != (lastMouseMods & MouseMods.middle))
                    {
                        btn = MouseButton.middle;
                        action = (mmods & MouseMods.middle) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if (action != MouseAction.cancel)
                        actionSent = true;
                }
                if ((eventFlags & MOUSE_MOVED) && !actionSent)
                {
                    auto e = new MouseEvent(MouseAction.move, MouseButton.none, mmods, kmods, x, y);
                    handleMouseEvent(e);
                    actionSent = true;
                }
                if (eventFlags & MOUSE_WHEELED)
                {
                    const int delta = (buttonState >> 16) & 0xFFFF;
                    auto e = new WheelEvent(x, y, mmods, kmods, 0, cast(short)-delta);
                    handleWheelEvent(e);
                    actionSent = true;
                }
                lastMouseMods = mmods;
                break;
            case WINDOW_BUFFER_SIZE_EVENT:
                const sz = record.WindowBufferSizeEvent.dwSize;
                handleConsoleResize(sz.X, sz.Y);
                break;
            default:
                break;
            }
        }
        else
        {
            import std.algorithm : startsWith;

            if (SIGHUP_flag)
            {
                Log.i("SIGHUP signal fired");
                _stopped = true;
            }

            string s = rawRead(20);
            if (s.length == 0)
            {
                handleInputIdle();
                return !_stopped;
            }
            if (s.length == 6 && s[0] == 27 && s[1] == '[' && s[2] == 'M')
            {
                // mouse event
                MouseAction a = MouseAction.cancel;
                const int mb = s[3] - 32;
                const int mx = s[4] - 32 - 1;
                const int my = s[5] - 32 - 1;

                const int btn = mb & 3;
                if (btn < 3)
                    a = MouseAction.buttonDown;
                else
                    a = MouseAction.buttonUp;
                if (mb & 32)
                    a = MouseAction.move;

                MouseButton button;
                MouseMods mmods;
                KeyMods kmods;
                if (btn == 0)
                {
                    button = MouseButton.left;
                    mmods |= MouseMods.left;
                }
                else if (btn == 1)
                {
                    button = MouseButton.middle;
                    mmods |= MouseMods.middle;
                }
                else if (btn == 2)
                {
                    button = MouseButton.right;
                    mmods |= MouseMods.right;
                }
                else if (btn == 3 && a != MouseAction.move)
                    a = MouseAction.buttonUp;
                if (button != MouseButton.none)
                    lastButtonDown = button;
                else if (a == MouseAction.buttonUp)
                    button = lastButtonDown;
                if (mb & 4)
                    kmods |= KeyMods.shift;
                if (mb & 8)
                    kmods |= KeyMods.alt;
                if (mb & 16)
                    kmods |= KeyMods.control;
                //Log.d("mouse evt:", s, " mb=", mb, " mx=", mx, " my=", my, "  action=", a, " button=", button, " flags=", flags);
                auto evt = new MouseEvent(a, button, mmods, kmods, cast(short)mx, cast(short)my);
                handleMouseEvent(evt);
                return true;
            }

            Key key;
            KeyMods mods;
            dstring text;
            if (s[0] == 27)
            {
                string escSequence = s[1 .. $];
                //Log.d("ESC ", escSequence);
                const char letter = escSequence[$ - 1];
                if (escSequence.startsWith("[") && escSequence.length > 1)
                {
                    import std.string : indexOf;

                    string options = escSequence[1 .. $ - 1];
                    if (letter == '~')
                    {
                        string code = options;
                        const semicolonPos = options.indexOf(";");
                        if (semicolonPos >= 0)
                        {
                            code = options[0 .. semicolonPos];
                            options = options[semicolonPos + 1 .. $];
                        }
                        else
                            options = null;

                        // dfmt off
                        switch (options)
                        {
                            case "5": mods = KeyMods.control; break;
                            case "2": mods = KeyMods.shift; break;
                            case "3": mods = KeyMods.alt; break;
                            case "4": mods = KeyMods.shift | KeyMods.alt; break;
                            case "6": mods = KeyMods.shift | KeyMods.control; break;
                            case "7": mods = KeyMods.alt | KeyMods.control; break;
                            case "8": mods = KeyMods.shift | KeyMods.alt | KeyMods.control; break;
                            default: break;
                        }
                        switch (code)
                        {
                            case "15": key = Key.F5; break;
                            case "17": key = Key.F6; break;
                            case "18": key = Key.F7; break;
                            case "19": key = Key.F8; break;
                            case "20": key = Key.F9; break;
                            case "21": key = Key.F10; break;
                            case "23": key = Key.F11; break;
                            case "24": key = Key.F12; break;
                            case "5":  key = Key.pageUp; break;
                            case "6":  key = Key.pageDown; break;
                            case "2":  key = Key.ins; break;
                            case "3":  key = Key.del; break;
                            default: break;
                        }
                        // dfmt on
                    }
                    else
                    {
                        // dfmt off
                        switch (options)
                        {
                            case "1;5": mods = KeyMods.control; break;
                            case "1;2": mods = KeyMods.shift; break;
                            case "1;3": mods = KeyMods.alt; break;
                            case "1;4": mods = KeyMods.shift | KeyMods.alt; break;
                            case "1;6": mods = KeyMods.shift | KeyMods.control; break;
                            case "1;7": mods = KeyMods.alt | KeyMods.control; break;
                            case "1;8": mods = KeyMods.shift | KeyMods.alt | KeyMods.control; break;
                            default: break;
                        }
                        switch (letter)
                        {
                            case 'A': key = Key.up; break;
                            case 'B': key = Key.down; break;
                            case 'D': key = Key.left; break;
                            case 'C': key = Key.right; break;
                            case 'H': key = Key.home; break;
                            case 'F': key = Key.end; break;
                            default: break;
                        }
                        switch (letter)
                        {
                            case 'P': key = Key.F1; break;
                            case 'Q': key = Key.F2; break;
                            case 'R': key = Key.F3; break;
                            case 'S': key = Key.F4; break;
                            default: break;
                        }
                        // dfmt on
                    }
                }
                else if (escSequence.startsWith("O"))
                {
                    // dfmt off
                    switch (letter)
                    {
                        case 'P': key = Key.F1; break;
                        case 'Q': key = Key.F2; break;
                        case 'R': key = Key.F3; break;
                        case 'S': key = Key.F4; break;
                        default: break;
                    }
                    // dfmt on
                }
            }
            else
            {
                import std.uni : toLower;

                try
                {
                    dstring s32 = toUTF32(s);
                    if (s32.length == 1)
                    {
                        const ch = toLower(s32[0]);
                        if (ch == ' ')
                        {
                            key = Key.space;
                            text = " ";
                        }
                        else if (ch == '\t')
                            key = Key.tab;
                        else if (ch == '\n')
                            key = Key.enter;
                        else if ('a' <= ch && ch <= 'z')
                        {
                            key = cast(Key)(Key.A + ch - 'a');
                            text = s32;
                        }
                        else if ('0' <= ch && ch <= '9')
                        {
                            key = cast(Key)(Key.alpha0 + ch - '0');
                            text = s32;
                        }

                        if (1 <= s32[0] && s32[0] <= 26)
                        {
                            // ctrl + A..Z
                            key = cast(Key)(Key.A + s32[0] - 1);
                            mods = KeyMods.control;
                        }
                        if ('A' <= s32[0] && s32[0] <= 'Z')
                        {
                            // uppercase letter - with shift
                            mods = KeyMods.shift;
                        }
                    }
                    else if (s32[0] >= 32)
                        text = s32;
                }
                catch (Exception e)
                {
                    // skip invalid utf8 encoding
                }
            }
            if (key != Key.none)
            {
                auto keyDown = new KeyEvent(KeyAction.keyDown, key, mods);
                handleKeyEvent(keyDown);
                if (text.length)
                {
                    auto keyText = new KeyEvent(KeyAction.text, key, mods, text);
                    handleKeyEvent(keyText);
                }
                auto keyUp = new KeyEvent(KeyAction.keyUp, key, mods);
                handleKeyEvent(keyUp);
            }
        }
        return !_stopped;
    }
}
