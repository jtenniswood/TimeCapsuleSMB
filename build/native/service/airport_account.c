#include "airport_account.h"
#define TC_PLIST_VALUE_CAPACITY (NT_HASH_MAX_PASSWORD_BYTES + 1)
#include "../common/plist.h"

#define ACCOUNT_XML_MAX 262144

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

static uint32_t account_id(const char *name) {
    uint32_t hash = 2166136261u;
    const unsigned char *p = (const unsigned char *)name;
    for (; *p; p++) {
        unsigned char ch = *p;
        /* Preserve an ASCII case-only rename's identity. Samba performs the
         * authoritative Unicode case comparison during authentication. */
        if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
        hash = (hash ^ ch) * 16777619u;
    }
    return TC_AIRPORT_ACCOUNT_ID_MIN + (hash & 0x1fffffffu);
}

static int user(struct parser *p, struct airport_account *account) {
    char password[NT_HASH_MAX_PASSWORD_BYTES + 1] = {0}, check[33];
    int seen = 0, result = -1;
    const unsigned char *name;
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
        if (field == 1) {
            if (strlen(p->value) > TC_AIRPORT_ACCOUNT_NAME_MAX) goto done;
            strcpy(account->name, p->value);
        } else if (field == 2) strcpy(password, p->value);
        else if (!strcmp(p->value, "0")) account->access = 0;
        else if (!strcmp(p->value, "1")) account->access = 1;
        else if (!strcmp(p->value, "2")) account->access = 2;
        else goto done;
        next(p);
    }
    if (seen != 7 || !account->name[0]) goto done;
    /* A smbpasswd name is a UTF-8 field, not shell/configuration syntax.
     * Colons and line breaks cannot be represented in that file. Domain/path
     * separators cannot be a standalone SMB account name. */
    for (name = (const unsigned char *)account->name; *name; name++)
        if (*name < 32 || *name == 127 || strchr(":/\\", *name)) goto done;
    if (password_nt_hash(account->name, strlen(account->name), check)) goto done;
    memset(account->nt_hash, '0', 32);
    account->nt_hash[32] = 0;
    if (account->access != 2 && password_nt_hash(password, strlen(password), account->nt_hash)) goto done;
    account->userid = account_id(account->name);
    next(p);
    result = 0;
done:
    wipe(check, sizeof(check));
    wipe(password, sizeof(password));
    return result;
}

static int compare_accounts(const void *a, const void *b) {
    return strcmp(((const struct airport_account *)a)->name,
                  ((const struct airport_account *)b)->name);
}

int airport_accounts_parse(const char *xml, size_t length, struct airport_accounts *out) {
    struct parser p = {0};
    int users = 0, result = -1;
    size_t i;
    memset(out, 0, sizeof(*out));
    if (!xml || !length || length > ACCOUNT_XML_MAX || memchr(xml, 0, length)) goto done;
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
        while (p.token != END_ARRAY) {
            struct airport_account *account;
            if (out->count == TC_AIRPORT_MAX_ACCOUNTS) goto done;
            account = &out->values[out->count];
            if (user(&p, account)) goto done;
            for (i = 0; i < out->count; i++)
                if (!strcasecmp(out->values[i].name, account->name) ||
                    out->values[i].userid == account->userid) goto done;
            out->count++;
        }
        next(&p);
    }
    next(&p);
    if (users != 1 || !at(&p, "</plist>")) goto done;
    p.p += 8;
    whitespace(&p);
    if (p.p != p.end) goto done;
    qsort(out->values, out->count, sizeof(out->values[0]), compare_accounts);
    result = 0;
done:
    wipe(&p, sizeof(p));
    if (result) wipe(out, sizeof(*out));
    return result;
}

int airport_accounts_nt_hashes(struct airport_accounts *out) {
    char *xml = malloc(ACCOUNT_XML_MAX + 1);
    struct acp_request request = {0};
    int result = -1;
    memset(out, 0, sizeof(*out));
    if (!xml) return -1;
    request.key = "usrd";
    request.multiline = 1;
    request.output = xml;
    request.capacity = ACCOUNT_XML_MAX + 1;
    (void)acp_collect_run(&request, 1, (long long)TC_ACP_TIMEOUT_SECONDS * 1000,
                        (long long)TC_ACP_COLLECTION_BUDGET_SECONDS * 1000);
    if (request.status == ACP_OK)
        result = airport_accounts_parse(xml, request.length, out);
    wipe(xml, ACCOUNT_XML_MAX + 1);
    free(xml);
    return result;
}

static int select_account(const struct airport_accounts *accounts, const char *name,
                          char hash[33], int *access) {
    size_t i;
    memset(hash, '0', 32);
    hash[32] = 0;
    *access = 2;
    if (!name || !*name) return -1;
    for (i = 0; i < accounts->count; i++)
        if (!strcmp(accounts->values[i].name, name)) {
            strcpy(hash, accounts->values[i].nt_hash);
            *access = accounts->values[i].access;
            break;
        }
    return 0;
}

int airport_account_parse(const char *xml, size_t length, const char *name,
                         char hash[33], int *access) {
    struct airport_accounts *accounts = malloc(sizeof(*accounts));
    int result = -1;
    if (accounts) {
        result = airport_accounts_parse(xml, length, accounts);
        if (!result) result = select_account(accounts, name, hash, access);
        wipe(accounts, sizeof(*accounts));
        free(accounts);
    }
    if (result) {
        memset(hash, 0, 33);
        *access = 2;
    }
    return result;
}

int airport_account_nt_hash(const char *name, char hash[33], int *access) {
    struct airport_accounts *accounts = malloc(sizeof(*accounts));
    int result = -1;
    if (accounts) {
        result = airport_accounts_nt_hashes(accounts);
        if (!result) result = select_account(accounts, name, hash, access);
        wipe(accounts, sizeof(*accounts));
        free(accounts);
    }
    if (result) {
        memset(hash, 0, 33);
        *access = 2;
    }
    return result;
}
