#ifndef TC_PLIST_H
#define TC_PLIST_H
#include "platform.h"

/* The bounded ACP plist lexer shared by volume and selected-account reads.
 * Native PrintFUtils strings are not escaped; XML reads preserve passwords. */
#ifndef TC_PLIST_VALUE_CAPACITY
#define TC_PLIST_VALUE_CAPACITY 1024
#endif

enum token_kind { END, DICT, ARRAY, END_DICT, END_ARRAY, STRING, DATA, EQUAL, BAD };
struct parser {
    const char *p, *end;
    /* native: acp -A's own text form, an array opened with '['. */
    int xml, native, depth;
    enum token_kind token;
    enum token_kind pending;
    char value[TC_PLIST_VALUE_CAPACITY];
};
static int at(struct parser *p, const char *s) {
    size_t n = strlen(s);
    return (size_t)(p->end - p->p) >= n && !memcmp(p->p, s, n);
}
static void whitespace(struct parser *p) {
    while (p->p < p->end && isspace((unsigned char)*p->p))
        p->p++;
}
static int put(char *out, size_t *n, unsigned char c) {
    if (!c || *n >= TC_PLIST_VALUE_CAPACITY - 1)
        return -1;
    out[(*n)++] = (char)c;
    out[*n] = 0;
    return 0;
}
static int codepoint(char *out, size_t *n, unsigned long cp) {
    if (!cp || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
        return -1;
    if (cp < 0x80)
        return put(out, n, cp);
    if (cp < 0x800)
        return put(out, n, 0xc0 | (cp >> 6)) || put(out, n, 0x80 | (cp & 63));
    if (cp < 0x10000)
        return put(out, n, 0xe0 | (cp >> 12)) || put(out, n, 0x80 | ((cp >> 6) & 63)) ||
               put(out, n, 0x80 | (cp & 63));
    return put(out, n, 0xf0 | (cp >> 18)) || put(out, n, 0x80 | ((cp >> 12) & 63)) ||
           put(out, n, 0x80 | ((cp >> 6) & 63)) || put(out, n, 0x80 | (cp & 63));
}
static int xml_text(struct parser *p, const char *closing) {
    size_t n = 0;
    while (p->p < p->end && !at(p, closing)) {
        unsigned char ch = *p->p++;
        if (ch == '<')
            return -1;
        if (ch == '&') {
            char entity[24];
            size_t k = 0;
            unsigned long cp = 0;
            char *tail;
            while (p->p < p->end && *p->p != ';' && k + 1 < sizeof(entity))
                entity[k++] = *p->p++;
            if (p->p == p->end || *p->p++ != ';')
                return -1;
            entity[k] = 0;
            if (!strcmp(entity, "amp"))
                cp = '&';
            else if (!strcmp(entity, "lt"))
                cp = '<';
            else if (!strcmp(entity, "gt"))
                cp = '>';
            else if (!strcmp(entity, "quot"))
                cp = '"';
            else if (!strcmp(entity, "apos"))
                cp = '\'';
            else if (entity[0] == '#') {
                const char *digits = entity + 1;
                int base = 10;
                if (*digits == 'x') {
                    digits++;
                    base = 16;
                }
                errno = 0;
                cp = strtoul(digits, &tail, base);
                if (errno || !*digits || *tail)
                    return -1;
            } else
                return -1;
            if (codepoint(p->value, &n, cp))
                return -1;
        } else if (put(p->value, &n, ch))
            return -1;
    }
    if (!at(p, closing))
        return -1;
    p->p += strlen(closing);
    return 0;
}
/* An empty element, "<name/>" or "<name />" as the v3.0.0 shell reader
 * accepted; Apple itself writes the compact form. */
static int empty_tag(struct parser *p, const char *name) {
    const char *save = p->p;
    size_t n = strlen(name);
    if ((size_t)(p->end - p->p) > n && *p->p == '<' && !memcmp(p->p + 1, name, n)) {
        p->p += n + 1;
        whitespace(p);
        if (at(p, "/>")) {
            p->p += 2;
            return 1;
        }
    }
    p->p = save;
    return 0;
}
static enum token_kind xml_token(struct parser *p) {
    static const struct {
        const char *open, *close;
        enum token_kind kind;
    } tags[] = {{"<key>", "</key>", STRING},         {"<string>", "</string>", STRING},
                {"<integer>", "</integer>", STRING}, {"<real>", "</real>", STRING},
                {"<data>", "</data>", DATA},         {"<date>", "</date>", STRING}};
    static const struct {
        const char *name, *value;
        enum token_kind kind, then;
    } empty[] = {{"array", "", ARRAY, END_ARRAY}, {"dict", "", DICT, END_DICT},
                 {"string", "", STRING, END},     {"data", "", DATA, END},
                 {"true", "true", STRING, END},   {"false", "false", STRING, END}};
    size_t i;
    whitespace(p);
    if (p->p == p->end)
        return END;
    for (i = 0; i < sizeof(empty) / sizeof(empty[0]); i++)
        if (empty_tag(p, empty[i].name)) {
            strcpy(p->value, empty[i].value);
            p->pending = empty[i].then;
            return empty[i].kind;
        }
    if (at(p, "<dict>")) {
        p->p += 6;
        return DICT;
    }
    if (at(p, "</dict>")) {
        p->p += 7;
        return END_DICT;
    }
    if (at(p, "<array>")) {
        p->p += 7;
        return ARRAY;
    }
    if (at(p, "</array>")) {
        p->p += 8;
        return END_ARRAY;
    }
    for (i = 0; i < sizeof(tags) / sizeof(tags[0]); i++)
        if (at(p, tags[i].open)) {
            p->p += strlen(tags[i].open);
            return xml_text(p, tags[i].close) ? BAD : tags[i].kind;
        }
    return BAD;
}
static void next(struct parser *p) {
    size_t n = 0;
    char ch;
    p->value[0] = 0;
    if (p->pending) {
        p->token = p->pending;
        p->pending = END;
        return;
    }
    if (p->xml) {
        p->token = xml_token(p);
        return;
    }
    while (p->p < p->end && (isspace((unsigned char)*p->p) || *p->p == ',' || *p->p == ';'))
        p->p++;
    if (p->p == p->end) {
        p->token = END;
        return;
    }
    ch = *p->p++;
    switch (ch) {
    case '{':
        p->token = DICT;
        return;
    case '}':
        p->token = END_DICT;
        return;
    case '[':
    case '(':
        p->token = ARRAY;
        return;
    case ']':
    case ')':
        p->token = END_ARRAY;
        return;
    case '=':
        p->token = EQUAL;
        return;
    case '"':
        if (p->native) {
            /* acp -A (Apple's PrintFUtils) writes a string value as its raw
             * UTF-8 between quotes and then ends the line. Nothing is
             * escaped, so a name may itself hold quotes, backslashes or line
             * breaks: the value runs to the first quote that only spaces
             * separate from a line break or the end of the text. */
            const char *q = p->p;
            for (;;) {
                const char *e;
                q = memchr(q, '"', (size_t)(p->end - q));
                if (!q) {
                    p->token = BAD;
                    return;
                }
                for (e = q + 1; e < p->end && (*e == ' ' || *e == '\t' || *e == '\r'); e++)
                    ;
                if (e == p->end || *e == '\n')
                    break;
                q++;
            }
            while (p->p < q)
                if (put(p->value, &n, (unsigned char)*p->p++)) {
                    p->token = BAD;
                    return;
                }
            p->p = q + 1;
            p->token = STRING;
            return;
        }
        /* The OpenStep form escapes quotes and backslashes. */
        while (p->p < p->end && *p->p != '"') {
            ch = *p->p++;
            if (ch == '\\') {
                if (p->p == p->end) {
                    p->token = BAD;
                    return;
                }
                ch = *p->p++;
                if (ch == 'n')
                    ch = '\n';
                else if (ch == 'r')
                    ch = '\r';
                else if (ch == 't')
                    ch = '\t';
            }
            if (put(p->value, &n, ch)) {
                p->token = BAD;
                return;
            }
        }
        if (p->p == p->end) {
            p->token = BAD;
            return;
        }
        p->p++;
        p->token = STRING;
        return;
    case '<':
        while (p->p < p->end && *p->p != '>')
            if (put(p->value, &n, *p->p++)) {
                p->token = BAD;
                return;
            }
        if (p->p == p->end) {
            p->token = BAD;
            return;
        }
        p->p++;
        p->token = STRING;
        return;
    default:
        p->p--;
    }
    while (p->p < p->end && !strchr("=;,\r\n{}[]()", *p->p)) {
        /* acp -A prints data as hex, then " |", the same bytes as text
         * (0x20-0x7e as themselves, so braces and brackets too, anything
         * else as '^') and "| (N bytes)". None of that is part of a UUID. */
        if (*p->p == '|') {
            while (p->p < p->end && *p->p != '\n')
                p->p++;
            break;
        }
        if (put(p->value, &n, *p->p++)) {
            p->token = BAD;
            return;
        }
    }
    while (n && isspace((unsigned char)p->value[n - 1]))
        p->value[--n] = 0;
    p->token = n ? STRING : BAD;
}

#endif
