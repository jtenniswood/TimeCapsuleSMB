#ifndef TC_AIRPORT_ACCOUNT_H
#define TC_AIRPORT_ACCOUNT_H
#include "service.h"

/* One selected AirPort account supplies the shared SMB password. Access is
 * AirPort's 0=read/write, 1=read-only, 2=disabled (also absent/deleted).
 * Malformed/unavailable ACP fails without falling back to the device password. */
int airport_account_nt_hash(const char *name, char hash[33], int *access);
int airport_account_parse(const char *xml, size_t length, const char *name,
                         char hash[33], int *access);
int password_nt_hash(const char *password, size_t length, char hash[33]);
#endif
