#include "airport_account.h"
#define TC_PLIST_VALUE_CAPACITY (NT_HASH_MAX_PASSWORD_BYTES + 1)
#include "../common/plist.h"

#define ACCOUNT_XML_MAX 65536

static void wipe(void *memory, size_t length) {
    volatile unsigned char *p = memory;
    while (length--) *p++ = 0;
}

static int skip(struct parser *p) {
    enum token_kind end;
    if (++p->depth > 32) return -1;
    if (p->token == DICT || p->token == ARRAY) {
        end = p->token == DICT ? END_DICT : END_ARRAY;
        next(p);
        while (p->token != end) {
            if (end == END_DICT) {
                if (p->token != STRING) return -1;
                next(p);
            }
            if (skip(p)) return -1;
        }
        next(p);
    } else if (p->token == STRING || p->token == DATA) next(p);
    else return -1;
    p->depth--;
    return 0;
}

static int xml_begin(struct parser *p) {
    whitespace(p);
    if (at(p, "<?xml")) {
        while (p->p < p->end && !at(p, "?>")) p->p++;
        if (!at(p, "?>")) return -1;
        p->p += 2;
    }
    whitespace(p);
    if (at(p, "<!DOCTYPE")) {
        /* Never expand entities or read external resources. */
        while (p->p < p->end && *p->p != '>') {
            if (*p->p++ == '[') return -1;
        }
        if (p->p == p->end) return -1;
        p->p++;
    }
    whitespace(p);
    if (!at(p, "<plist") || p->p + 6 >= p->end ||
        (!isspace((unsigned char)p->p[6]) && p->p[6] != '>')) return -1;
    while (p->p < p->end && *p->p != '>') p->p++;
    if (p->p == p->end) return -1;
    p->p++;
    p->xml = 1;
    next(p);
    return p->token == DICT ? 0 : -1;
}

static int user(struct parser *p, const char *name, char hash[33], int *access, int *found) {
    char password[NT_HASH_MAX_PASSWORD_BYTES + 1] = {0};
    int matched = 0, seen = 0, permission = -1, result = -1;
    if (p->token != DICT) goto done;
    next(p);
    while (p->token != END_DICT) {
        int field = 0;
        if (p->token != STRING) goto done;
        if (!strcmp(p->value, "name")) field = 1;
        else if (!strcmp(p->value, "password")) field = 2;
        else if (!strcmp(p->value, "fileSharingAccess")) field = 4;
        if (seen & field) goto done;
        seen |= field;
        next(p);
        if (!field) {
            if (skip(p)) goto done;
            continue;
        }
        if (p->token != STRING) goto done;
        if (field == 1) matched = !strcmp(p->value, name);
        else if (field == 2) strcpy(password, p->value);
        else if (!strcmp(p->value, "0")) permission = 0;
        else if (!strcmp(p->value, "1")) permission = 1;
        else if (!strcmp(p->value, "2")) permission = 2;
        else goto done;
        next(p);
    }
    if (matched) {
        if (*found || seen != 7) goto done;
        *found = 1;
        *access = permission;
        if (permission != 2 && password_nt_hash(password, strlen(password), hash)) goto done;
    }
    next(p);
    result = 0;
done:
    wipe(password, sizeof(password));
    return result;
}

int airport_account_parse(const char *xml, size_t length, const char *name,
                         char hash[33], int *access) {
    struct parser p = {0};
    int found = 0, users = 0, result = -1;
    memset(hash, '0', 32);
    hash[32] = 0;
    *access = 2;
    if (!xml || !length || length > ACCOUNT_XML_MAX || memchr(xml, 0, length) || !name || !*name)
        goto done;
    p.p = xml;
    p.end = xml + length;
    if (xml_begin(&p)) goto done;
    next(&p);
    while (p.token != END_DICT) {
        int is_users;
        if (p.token != STRING) goto done;
        is_users = !strcmp(p.value, "users");
        next(&p);
        if (!is_users) {
            if (skip(&p)) goto done;
            continue;
        }
        if (users++ || p.token != ARRAY) goto done;
        next(&p);
        while (p.token != END_ARRAY)
            if (user(&p, name, hash, access, &found)) goto done;
        next(&p);
    }
    next(&p);
    if (users != 1 || !at(&p, "</plist>")) goto done;
    p.p += 8;
    whitespace(&p);
    if (p.p != p.end) goto done;
    result = 0;
done:
    wipe(&p, sizeof(p));
    if (result) {
        memset(hash, 0, 33);
        *access = 2;
    }
    return result;
}

int airport_account_nt_hash(const char *name, char hash[33], int *access) {
    char *xml = malloc(ACCOUNT_XML_MAX + 1);
    struct acp_request request = {0};
    int result = -1;
    hash[0] = 0;
    *access = 2;
    if (!xml) return -1;
    request.key = "usrd";
    request.multiline = 1;
    request.output = xml;
    request.capacity = ACCOUNT_XML_MAX + 1;
    (void)acp_collect_run(&request, 1, (long long)TC_ACP_TIMEOUT_SECONDS * 1000,
                        (long long)TC_ACP_COLLECTION_BUDGET_SECONDS * 1000);
    if (request.status == ACP_OK)
        result = airport_account_parse(xml, request.length, name, hash, access);
    wipe(xml, ACCOUNT_XML_MAX + 1);
    free(xml);
    return result;
}
