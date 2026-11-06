#include "samba/staging.h"
#include <assert.h>

int tc_samba_identity_read(struct tc_samba_identity *identity, const char *hostname) {
    memset(identity, 0, sizeof(*identity));
    strcpy(identity->netbios, "CAPSULE");
    strcpy(identity->server, "Time Capsule");
    strcpy(identity->model, "TimeCapsule6,116");
    (void)hostname;
    return 0;
}
int device_nt_hash(char hash[33]) {
    strcpy(hash, "0123456789ABCDEF0123456789ABCDEF");
    return getenv("FAIL_HASH") ? -1 : 0;
}
int airport_disk_nt_hash(char hash[33]) { strcpy(hash, "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"); return 0; }
int airport_sharing_flags(unsigned *flags) {
    if (getenv("FAIL_SHARING")) return -1;
    *flags = getenv("SHARING_FLAGS") ? (unsigned)strtoul(getenv("SHARING_FLAGS"), NULL, 0) : 0x410;
    return 0;
}
int airport_accounts_nt_hashes(struct airport_accounts *out) {
    memset(out, 0, sizeof(*out));
    out->count = getenv("EMPTY_ACCOUNTS") ? 0 : 2;
    strcpy(out->values[0].name, "jtenniswood");
    strcpy(out->values[0].nt_hash, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
    out->values[0].userid = 65537;
    out->values[0].access = getenv("ACCOUNT_ACCESS") ? atoi(getenv("ACCOUNT_ACCESS")) : 0;
    strcpy(out->values[1].name, "Other % user");
    strcpy(out->values[1].nt_hash, "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB");
    out->values[1].userid = 65538;
    out->values[1].access = 1;
    return getenv("FAIL_ACCOUNT") ? -1 : 0;
}
int main(int argc, char **argv) {
    struct tc_samba_settings settings;
    struct tc_storage_snapshot storage;
    struct tc_inventory inventory;
    struct tc_stage_copy how = {0, 0, 0, -1};
    struct tc_stage_result result;
    int failed, rsync;
    char text[TC_MAST_MAX + 1];
    size_t length = fread(text, 1, sizeof(text), stdin);
    assert(argc == 2);
    if (!strcmp(argv[1], "clear-locks")) return tc_samba_clear_locks() ? 5 : 0;
    if (tc_samba_settings_read(&settings, "capsule") || tc_mast_parse(&inventory, text, length))
        return 2;
    if (!strcmp(argv[1], "settings")) {
        printf("sharing=%d account=%s\n", settings.config.sharing_enabled, settings.config.smb_airport_account);
        return 0;
    }
    memset(&storage, 0, sizeof(storage));
    storage.inventory = inventory;
    storage.available = 1;
    storage.payload_index = 0;
    snprintf(storage.payload, sizeof(storage.payload), "%s/.samba4", inventory.volumes[0].root);
    snprintf(storage.smbd_source, sizeof(storage.smbd_source), "%s/smbd", storage.payload);
    assert(!tc_shares_build(&storage.shares, &inventory, 1, 0, 0));
    /* copy/reload/discard: Samba's run; rsync-copy/rsync: rsync's own. PROBE
     * and SEEN stand for an image the manager holds as damaged, MISSING for
     * the files the last run found missing. */
    rsync = !strncmp(argv[1], "rsync", 5);
    how.copy = !strcmp(argv[1], "copy") || !strcmp(argv[1], "rsync-copy");
    how.probe = getenv("PROBE") != NULL;
    if (getenv("SEEN"))
        how.seen = strtoll(getenv("SEEN"), NULL, 0);
    how.missing = getenv("MISSING") ? (int)strtol(getenv("MISSING"), NULL, 0) : 0;
    /* Every run reports its result, however early it fails: anything left
     * of this filler would show. BAD_HASH: settings whose hash smbpasswd
     * cannot take. */
    memset(&result, 0x55, sizeof(result));
    if (getenv("BAD_HASH"))
        strcpy(settings.nt_hash, "not a hash");
    if (getenv("BAD_ACCOUNT_HASH"))
        strcpy(settings.config.smb_accounts.values[0].nt_hash, "not a hash");
    failed = rsync ? tc_rsync_stage(&storage, &how, &result) : tc_samba_stage(&storage, &settings, &how, &result);
    /* What the manager learns about the image, even from a failed run. */
    printf("copy=%d crc=%lld read=%lld missing=%d\n", result.copy, result.crc32, result.read, result.missing);
    if (failed)
        return 3;
    if (!strcmp(argv[1], "discard")) {
        tc_samba_discard();
        return 0;
    }
    return (rsync ? tc_rsync_publish() : tc_samba_publish()) ? 4 : 0;
}
