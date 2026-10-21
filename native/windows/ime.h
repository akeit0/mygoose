/* Inline IMM composition. Coordinates are physical client pixels; the system
   caret is hidden, but exposes the same position to TSF-based Windows IMEs. */
static struct {
    uint8_t text[4096], result[4096];
    int length, result_length, cursor, target_start, target_end;
    bool composing, pending_update, system_caret;
    uint64_t owner;
    RECT caret;
    int caret_height;
    float font_size;
    HIMC context;
} ime;

static int ime_prefix(const WCHAR *s, int units) {
    if (units <= 0) return 0;
    return WideCharToMultiByte(CP_UTF8, 0, s, units, NULL, 0, NULL, NULL);
}
static void ime_decode(const WCHAR *s, int units, int cursor, const BYTE *attrs, int attr_count) {
    ime.length = WideCharToMultiByte(CP_UTF8, 0, s, units, (char *)ime.text, sizeof(ime.text), NULL, NULL);
    if (ime.length < 0) ime.length = 0;
    if (cursor < 0) cursor = 0;
    if (cursor > units) cursor = units;
    // Do not split a supplementary character's UTF-16 surrogate pair.
    if (cursor > 0 && cursor < units && s[cursor] >= 0xdc00 && s[cursor] <= 0xdfff) cursor--;
    ime.cursor = ime_prefix(s, cursor);
    int first = -1, end = 0;
    for (int i = 0; i < units && i < attr_count; i++) {
        if (attrs[i] == ATTR_TARGET_CONVERTED || attrs[i] == ATTR_TARGET_NOTCONVERTED) {
            if (first < 0) first = i;
            end = i + 1;
        }
    }
    ime.target_start = first < 0 ? ime.cursor : ime_prefix(s, first);
    ime.target_end = first < 0 ? ime.cursor : ime_prefix(s, end);
    if (ime.cursor > ime.length) ime.cursor = ime.length;
    if (ime.target_start > ime.length) ime.target_start = ime.length;
    if (ime.target_end > ime.length) ime.target_end = ime.length;
}
static void ime_position(HWND hwnd, HIMC context, DWORD candidates) {
    if (!ime.owner || !context) return;
    COMPOSITIONFORM composition = {CFS_POINT, {ime.caret.left, ime.caret.top}, {0,0,0,0}};
    ImmSetCompositionWindow(context, &composition);
    LOGFONTW font; memset(&font, 0, sizeof(font));
    font.lfHeight = -edge(ime.font_size); wcscpy(font.lfFaceName, L"Segoe UI");
    ImmSetCompositionFontW(context, &font);
    for (DWORD i = 0; i < 4; i++) if (candidates & (1u << i)) {
        CANDIDATEFORM candidate = {i, CFS_EXCLUDE,
            {ime.caret.left, ime.caret.bottom}, ime.caret};
        ImmSetCandidateWindow(context, &candidate);
    }
    // CreateCaret remains hidden (no ShowCaret); MyGoose paints the caret.
    // Modern Microsoft IMEs can query this location rather than IMM's point.
    if (GetFocus() == hwnd) {
        int height = ime.caret.bottom - ime.caret.top;
        if (!ime.system_caret || height != ime.caret_height) {
            if (ime.system_caret) DestroyCaret();
            ime.system_caret = CreateCaret(hwnd, NULL, 1, height) != 0;
            ime.caret_height = height;
        }
        if (ime.system_caret) SetCaretPos(ime.caret.left, ime.caret.top);
    }
}
void mg_ime_anchor(uint64_t owner, float x, float y, float w, float h, float font_size) {
    if (owner != ime.owner && ime.composing && mg.window) {
        HIMC context = ImmGetContext(mg.window);
        if (context) { ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0); ImmReleaseContext(mg.window, context); }
        ime.composing = false; ime.length = 0; ime.pending_update = false;
    }
    ime.owner = owner; ime.font_size = font_size;
    ime.caret = (RECT){px(x), px(y), edge(x+w), edge(y+h)};
    if (!mg.window) return;
    // Retain the window's original input context; disable IME on controls
    // which cannot accept text, then restore it when an editor takes focus.
    if (!owner) {
        if (ime.system_caret) { DestroyCaret(); ime.system_caret = false; }
        ImmAssociateContext(mg.window, NULL); return;
    }
    if (ime.context) ImmAssociateContext(mg.window, ime.context);
    HIMC context = ImmGetContext(mg.window);
    if (context) { ime_position(mg.window, context, 1); ImmReleaseContext(mg.window, context); }
}
static bool ime_capture(HWND hwnd, LPARAM flags) {
    HIMC context = ImmGetContext(hwnd); if (!context) return false;
    WCHAR text[2048]; BYTE attrs[2048];
    bool result = false;
    if (flags & GCS_RESULTSTR) {
        LONG bytes = ImmGetCompositionStringW(context, GCS_RESULTSTR, NULL, 0);
        if (bytes > 0 && bytes <= (LONG)sizeof(text)) {
            bytes = ImmGetCompositionStringW(context, GCS_RESULTSTR, text, sizeof(text));
            ime.result_length = bytes > 0 ? WideCharToMultiByte(CP_UTF8, 0, text, bytes/2,
                (char *)ime.result, sizeof(ime.result), NULL, NULL) : 0;
            result = ime.result_length > 0;
        }
        ime.length = 0;
    }
    bool update = (flags & (GCS_COMPSTR | GCS_CURSORPOS | GCS_COMPATTR)) != 0;
    if (update) {
        LONG bytes = ImmGetCompositionStringW(context, GCS_COMPSTR, NULL, 0);
        if (bytes >= 0 && bytes <= (LONG)sizeof(text)) {
            bytes = ImmGetCompositionStringW(context, GCS_COMPSTR, text, sizeof(text));
            LONG count = ImmGetCompositionStringW(context, GCS_COMPATTR, attrs, sizeof(attrs));
            LONG cursor = ImmGetCompositionStringW(context, GCS_CURSORPOS, NULL, 0);
            ime_decode(text, bytes > 0 ? bytes/2 : 0, (int)cursor, attrs, count > 0 ? (int)count : 0);
        } else ime.length = 0;
    }
    ime.composing = true; ime_position(hwnd, context, 1); ImmReleaseContext(hwnd, context);
    if (result) { mg.event = 11; ime.pending_update = update; }
    else mg.event = 10;
    if (!flags) { ime.composing = false; ime.length = 0; mg.event = 12; }
    return true;
}
int64_t mg_ime_read(mg_bytes out, bool result) {
    int n = result ? ime.result_length : ime.length;
    if (n < 0 || n > out.len) return 0;
    memcpy(out.data, result ? ime.result : ime.text, (size_t)n); return n;
}
int32_t mg_ime_cursor(void) { return ime.cursor; }
int32_t mg_ime_target_start(void) { return ime.target_start; }
int32_t mg_ime_target_end(void) { return ime.target_end; }
