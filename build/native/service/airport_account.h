#ifndef TC_AIRPORT_ACCOUNT_H
#define TC_AIRPORT_ACCOUNT_H
#include "service.h"

#define TC_AIRPORT_MAX_ACCOUNTS 128
#define TC_AIRPORT_ACCOUNT_NAME_MAX 255
/* IDs become distinct Samba RIDs, never operating-system users. Keep below
 * the algorithmic RID overflow limit; collisions reject the whole snapshot. */
#define TC_AIRPORT_ACCOUNT_ID_MIN 65536u
#define TC_AIRPORT_ACCOUNT_ID_MAX 0x2000ffffu
struct airport_account {
    char name[TC_AIRPORT_ACCOUNT_NAME_MAX + 1];
    char nt_hash[33];
    uint32_t userid;
    int access; /* AirPort: 0 read/write, 1 read-only, 2 denied. */
};
struct airport_accounts {
    size_t count;
    struct airport_account values[TC_AIRPORT_MAX_ACCOUNTS];
};
int airport_accounts_parse(const char *xml, size_t length, struct airport_accounts *out);
int airport_accounts_nt_hashes(struct airport_accounts *out);
/* Selected-account diagnostics retain their existing interface. */
int airport_account_nt_hash(const char *name, char hash[33], int *access);
int airport_account_parse(const char *xml, size_t length, const char *name,
                         char hash[33], int *access);
int password_nt_hash(const char *password, size_t length, char hash[33]);
int airport_sharing_flags(unsigned *flags);
int airport_disk_nt_hash(char hash[33]);
#endif
