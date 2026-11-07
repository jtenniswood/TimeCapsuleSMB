#include "mast.h"
#include <limits.h>

/* A small streaming plist reader, not a general property-list object model.
 * Apple puts builtin/deviceName after partitions in some firmware versions.
 * Keep a disk's partitions until its dictionary has ended. */
#include "../common/plist.h"

struct part {
    char device[16], name[TC_VOLUME_NAME_MAX], format[16], uuid[37];
    int users;
};
struct disk {
    char device[16];
    int builtin;
    struct part parts[TC_MAX_VOLUMES];
    size_t count;
};
enum context { IGNORE, DISKS, DISK, PARTS, PART };

static int copy_value(char *out, size_t capacity, const char *value) {
    if (strlen(value) >= capacity)
        return -1;
    strcpy(out, value);
    return 0;
}
static int device_ok(const char *s) {
    return *s && strspn(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") == strlen(s);
}
static int uuid_value(char out[37], const char *s, int base64) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char hex[33];
    size_t n = 0;
    unsigned acc = 0, bits = 0;
    int padding = 0;
    while (*s) {
        unsigned char c = *s++;
        const char *found;
        if (isspace(c))
            continue;
        if (base64) {
            if (c == '=') {
                padding = 1;
                continue;
            }
            if (padding || !(found = strchr(alphabet, c)))
                return -1;
            acc = (acc << 6) | (unsigned)(found - alphabet);
            bits += 6;
            if (bits >= 8) {
                unsigned byte;
                bits -= 8;
                byte = (acc >> bits) & 255;
                if (n + 2 > 32)
                    return -1;
                hex[n++] = "0123456789abcdef"[byte >> 4];
                hex[n++] = "0123456789abcdef"[byte & 15];
            }
        } else {
            if (c == '-')
                continue;
            if (!isxdigit(c) || n == 32)
                return -1;
            hex[n++] = (char)tolower(c);
        }
    }
    if (n != 32 || !memcmp(hex, "00000000000000000000000000000000", 32))
        return -1;
    hex[n] = 0;
    snprintf(out, 37, "%.8s-%.4s-%.4s-%.4s-%.12s", hex, hex + 8, hex + 12, hex + 16, hex + 20);
    return 0;
}
static int append_disk(struct tc_inventory *out, const struct disk *disk) {
    size_t i, j;
    for (i = 0; i < disk->count; i++) {
        const struct part *part = &disk->parts[i];
        struct tc_volume *v;
        if (out->count == TC_MAX_VOLUMES || !device_ok(disk->device))
            return -1;
        for (j = 0; j < out->count; j++)
            if (!strcmp(out->volumes[j].device, part->device))
                return -1;
        v = &out->volumes[out->count++];
        strcpy(v->disk, disk->device);
        strcpy(v->device, part->device);
        strcpy(v->name, part->name);
        strcpy(v->uuid, part->uuid);
        if (snprintf(v->root, sizeof(v->root), "%s/%s", TC_VOLUMES_ROOT, part->device) >=
            (int)sizeof(v->root))
            return -1;
        v->builtin = disk->builtin;
        v->users = part->users;
    }
    return 0;
}
static int value(struct parser *, enum context, struct tc_inventory *, struct disk *, struct part *);
static int dictionary(struct parser *p, enum context ctx, struct tc_inventory *out, struct disk *d,
                      struct part *part) {
    next(p);
    while (p->token != END_DICT) {
        char key[80];
        enum context child = IGNORE;
        if (p->token != STRING || copy_value(key, sizeof(key), p->value))
            return -1;
        next(p);
        if (!p->xml) {
            if (p->token != EQUAL)
                return -1;
            next(p);
        }
        if (ctx == DISK && !strcmp(key, "partitions"))
            child = PARTS;
        if (child == PARTS) {
            if (p->token != ARRAY || value(p, child, out, d, NULL))
                return -1;
            continue;
        }
        if (p->token == STRING || p->token == DATA) {
            const char *s = p->value;
            int rc = 0;
            if (ctx == DISK) {
                if (!strcmp(key, "deviceName"))
                    rc = copy_value(d->device, sizeof(d->device), s);
                else if (!strcmp(key, "builtin")) {
                    if (!strcmp(s, "true") || !strcmp(s, "1"))
                        d->builtin = 1;
                    else if (!strcmp(s, "false") || !strcmp(s, "0"))
                        d->builtin = 0;
                    else
                        return -1;
                }
            } else if (ctx == PART) {
                if (!strcmp(key, "deviceName"))
                    rc = copy_value(part->device, sizeof(part->device), s);
                else if (!strcmp(key, "name"))
                    rc = copy_value(part->name, sizeof(part->name), s);
                else if (!strcmp(key, "format"))
                    rc = copy_value(part->format, sizeof(part->format), s);
                else if (!strcmp(key, "uuid")) {
                    if (uuid_value(part->uuid, s, p->token == DATA))
                        part->uuid[0] = 0;
                } else if (!strcmp(key, "users")) {
                    char *end;
                    long users;
                    errno = 0;
                    users = strtol(s, &end, 10);
                    part->users = !errno && *s && !*end && users >= 0 && users <= INT_MAX ? (int)users : -1;
                }
            }
            if (rc)
                return -1;
            next(p);
        } else if (value(p, IGNORE, out, NULL, NULL))
            return -1;
    }
    next(p);
    return 0;
}
static int value(struct parser *p, enum context ctx, struct tc_inventory *out, struct disk *disk,
                 struct part *part) {
    int result = 0;
    if (++p->depth > 32)
        return -1;
    if (p->token == ARRAY) {
        next(p);
        while (p->token != END_ARRAY) {
            if (ctx == DISKS) {
                struct disk d;
                memset(&d, 0, sizeof(d));
                if (p->token != DICT || value(p, DISK, out, &d, NULL) || append_disk(out, &d)) {
                    result = -1;
                    break;
                }
            } else if (ctx == PARTS) {
                struct part item;
                memset(&item, 0, sizeof(item));
                item.users = -1;
                if (p->token != DICT || value(p, PART, out, disk, &item)) {
                    result = -1;
                    break;
                }
                if (!strcasecmp(item.format, "hfs") && !strncmp(item.device, "dk", 2) &&
                    isdigit((unsigned char)item.device[2]) && device_ok(item.device) && item.name[0] &&
                    item.uuid[0]) {
                    if (disk->count == TC_MAX_VOLUMES) {
                        result = -1;
                        break;
                    }
                    disk->parts[disk->count++] = item;
                }
            } else if (value(p, IGNORE, out, NULL, NULL)) {
                result = -1;
                break;
            }
        }
        if (!result)
            next(p);
    } else if (p->token == DICT)
        result = dictionary(p, ctx, out, disk, part);
    else if (p->token == STRING || p->token == DATA)
        next(p);
    else
        result = -1;
    p->depth--;
    return result;
}

int tc_mast_parse(struct tc_inventory *out, const char *text, size_t length) {
    struct parser p;
    int result = -1;
    memset(out, 0, sizeof(*out));
    memset(&p, 0, sizeof(p));
    if (!text || !length || length > TC_MAST_MAX || memchr(text, 0, length))
        return -1;
    p.p = text;
    p.end = text + length;
    whitespace(&p);
    if (at(&p, "MaSt")) {
        p.p += 4;
        whitespace(&p);
        if (p.p == p.end || *p.p++ != '=')
            goto done;
        whitespace(&p);
    }
    if (at(&p, "<?xml") || at(&p, "<plist")) {
        p.xml = 1;
        if (at(&p, "<?xml")) {
            while (p.p < p.end && !at(&p, "?>"))
                p.p++;
            if (!at(&p, "?>"))
                goto done;
            p.p += 2;
        }
        whitespace(&p);
        if (at(&p, "<!DOCTYPE")) {
            while (p.p < p.end && *p.p != '>') {
                if (*p.p == '[')
                    goto done;
                p.p++;
            }
            if (p.p == p.end)
                goto done;
            p.p++;
        }
        whitespace(&p);
        if (!at(&p, "<plist"))
            goto done;
        while (p.p < p.end && *p.p != '>')
            p.p++;
        if (p.p == p.end)
            goto done;
        p.p++;
    } else
        p.native = at(&p, "[");
    next(&p);
    if (p.token != ARRAY || value(&p, DISKS, out, NULL, NULL))
        goto done;
    /* XML's closing plist envelope is not a value token. Native acp instead
     * prints a trailing empty MaSt= label after its complete array. */
    if (p.xml) {
        if (!at(&p, "</plist>"))
            goto done;
        p.p += 8;
        whitespace(&p);
    } else if (p.token == STRING && !strcmp(p.value, "MaSt")) {
        next(&p);
        if (p.token != EQUAL)
            goto done;
        next(&p);
    }
    if (p.p != p.end || (!p.xml && p.token != END))
        goto done;
    result = 0;
done:
    if (result)
        memset(out, 0, sizeof(*out));
    return result;
}

int tc_inventory_same_topology(const struct tc_inventory *a, const struct tc_inventory *b) {
    size_t i, j;
    if (a->count != b->count)
        return 0;
    for (i = 0; i < a->count; i++) {
        const struct tc_volume *v = &a->volumes[i];
        for (j = 0; j < b->count; j++) {
            const struct tc_volume *w = &b->volumes[j];
            if (!strcmp(v->device, w->device) && !strcmp(v->disk, w->disk) && !strcmp(v->uuid, w->uuid) &&
                !strcmp(v->name, w->name) && v->builtin == w->builtin)
                break;
        }
        if (j == b->count)
            return 0;
    }
    return 1;
}
