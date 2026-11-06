#include "service/airport_account.h"
#include <assert.h>

int main(int argc, char **argv) {
    char input[65538], hash[33];
    int access = -1, result;
    size_t length;
    assert(argc == 2);
    length = fread(input, 1, sizeof(input), stdin);
    result = airport_account_parse(input, length, argv[1], hash, &access);
    if (result) {
        assert(!hash[0] && access == 2);
        return 1;
    }
    printf("%d %s\n", access, hash);
    return 0;
}
