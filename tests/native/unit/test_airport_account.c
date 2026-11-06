#include "service/airport_account.h"
#include <assert.h>

int main(int argc, char **argv) {
    char input[262146], hash[33];
    int access = -1, result;
    size_t length;
    assert(argc == 2);
    length = fread(input, 1, sizeof(input), stdin);
    if (!strcmp(argv[1], "--all")) {
        struct airport_accounts accounts;
        size_t i;
        if (airport_accounts_parse(input, length, &accounts)) {
            assert(!accounts.count && !accounts.values[0].name[0]);
            return 1;
        }
        for (i = 0; i < accounts.count; i++)
            printf("%u\t%d\t%s\t%s\n", (unsigned)accounts.values[i].userid,
                    accounts.values[i].access, accounts.values[i].name, accounts.values[i].nt_hash);
        return 0;
    }
    result = airport_account_parse(input, length, argv[1], hash, &access);
    if (result) {
        assert(!hash[0] && access == 2);
        return 1;
    }
    printf("%d %s\n", access, hash);
    return 0;
}
