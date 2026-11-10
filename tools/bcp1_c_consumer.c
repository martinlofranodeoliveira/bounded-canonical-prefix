/*
 * Independent Native C11 Consumer & Verifier for the BCP1 Format.
 *
 * Parses the 268-byte BCP1 header, validates Kraft's inequality, reconstructs
 * the canonical prefix tree independently without importing Nim code, decodes
 * the bitstream, and optionally compares against an expected raw payload file.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BCP1_HEADER_SIZE 268
#define MAX_DECODED_BYTES 1048576U
#define MAX_MEANINGFUL_BITS 16777216U
#define MAX_CODE_LEN 16

typedef struct {
    int left;
    int right;
    int sym;
} TrieNode;

static uint32_t read_le32(const uint8_t *p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <encoded.bcp1> [<expected.bin>]\n", argv[0]);
        return 2;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Cannot open encoded file\n");
        return 2;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return 2;
    }
    long fsize = ftell(f);
    if (fsize < BCP1_HEADER_SIZE || fsize > 2097420L) {
        fclose(f);
        fprintf(stderr, "ERR_HEADER_OR_FILE_SIZE\n");
        return 1;
    }
    rewind(f);

    uint8_t *buf = (uint8_t *)malloc((size_t)fsize);
    if (!buf) {
        fclose(f);
        return 2;
    }
    if (fread(buf, 1, (size_t)fsize, f) != (size_t)fsize) {
        free(buf);
        fclose(f);
        return 2;
    }
    fclose(f);

    if (memcmp(buf, "BCP1", 4) != 0) {
        free(buf);
        fprintf(stderr, "ERR_INVALID_MAGIC\n");
        return 1;
    }

    uint32_t decoded_len = read_le32(buf + 4);
    uint32_t meaningful_bits = read_le32(buf + 8);
    if (decoded_len > MAX_DECODED_BYTES || meaningful_bits > MAX_MEANINGFUL_BITS) {
        free(buf);
        fprintf(stderr, "ERR_LIMIT_EXCEEDED\n");
        return 1;
    }

    const uint8_t *lengths = buf + 12;
    int active_count = 0;
    uint32_t kraft_sum = 0;
    for (int s = 0; s < 256; s++) {
        uint8_t L = lengths[s];
        if (L > MAX_CODE_LEN) {
            free(buf);
            fprintf(stderr, "ERR_INVALID_CODE_LENGTH\n");
            return 1;
        }
        if (L > 0) {
            active_count++;
            kraft_sum += (1U << (MAX_CODE_LEN - L));
        }
    }

    if (active_count == 1) {
        if (kraft_sum != (1U << (MAX_CODE_LEN - 1))) {
            free(buf);
            fprintf(stderr, "ERR_SINGLETON_KRAFT\n");
            return 1;
        }
    } else if (active_count >= 2) {
        if (kraft_sum != (1U << MAX_CODE_LEN)) {
            free(buf);
            fprintf(stderr, "ERR_INVALID_KRAFT_SUM\n");
            return 1;
        }
    }

    size_t expected_payload = (size_t)((meaningful_bits + 7U) >> 3);
    if ((size_t)fsize != BCP1_HEADER_SIZE + expected_payload) {
        free(buf);
        fprintf(stderr, "ERR_BYTE_LENGTH_MISMATCH\n");
        return 1;
    }

    int unused_bits = (8 - (int)(meaningful_bits & 7U)) & 7;
    if (unused_bits > 0 && expected_payload > 0) {
        uint8_t last_byte = buf[fsize - 1];
        uint8_t mask = (uint8_t)((1U << unused_bits) - 1U);
        if ((last_byte & mask) != 0) {
            free(buf);
            fprintf(stderr, "ERR_NONZERO_PADDING\n");
            return 1;
        }
    }

    if (active_count == 0 && (decoded_len != 0 || meaningful_bits != 0)) {
        free(buf);
        fprintf(stderr, "ERR_EMPTY_ALPHABET_NONZERO\n");
        return 1;
    }

    /* Sort active symbols by (length ASC, symbol ASC) */
    int syms[256];
    int n = 0;
    for (int len = 1; len <= MAX_CODE_LEN; len++) {
        for (int s = 0; s < 256; s++) {
            if (lengths[s] == len) {
                syms[n++] = s;
            }
        }
    }

    uint16_t codes[256];
    memset(codes, 0, sizeof(codes));
    if (n > 0) {
        uint32_t cur_code = 0;
        int prev_len = lengths[syms[0]];
        for (int i = 0; i < n; i++) {
            int s = syms[i];
            int cur_len = lengths[s];
            if (i > 0) {
                cur_code = (cur_code + 1U) << (cur_len - prev_len);
                prev_len = cur_len;
            }
            codes[s] = (uint16_t)cur_code;
        }
    }

    TrieNode trie[4096];
    int trie_len = 1;
    trie[0].left = -1;
    trie[0].right = -1;
    trie[0].sym = -1;

    for (int i = 0; i < n; i++) {
        int s = syms[i];
        int L = lengths[s];
        uint16_t c = codes[s];
        int curr = 0;
        for (int shift = L - 1; shift >= 0; shift--) {
            int bit = (c >> shift) & 1;
            int next = bit ? trie[curr].right : trie[curr].left;
            if (next == -1) {
                next = trie_len++;
                trie[next].left = -1;
                trie[next].right = -1;
                trie[next].sym = -1;
                if (bit)
                    trie[curr].right = next;
                else
                    trie[curr].left = next;
            }
            curr = next;
        }
        trie[curr].sym = s;
    }

    uint8_t *decoded = (uint8_t *)malloc(decoded_len > 0 ? decoded_len : 1);
    if (!decoded) {
        free(buf);
        return 2;
    }

    uint32_t out_pos = 0;
    int curr = 0;
    for (uint32_t bit_idx = 0; bit_idx < meaningful_bits; bit_idx++) {
        size_t byte_idx = BCP1_HEADER_SIZE + (size_t)(bit_idx >> 3);
        int shift = 7 - (int)(bit_idx & 7U);
        int bit = (buf[byte_idx] >> shift) & 1;
        curr = bit ? trie[curr].right : trie[curr].left;
        if (curr == -1) {
            free(decoded);
            free(buf);
            fprintf(stderr, "ERR_INVALID_CODEWORD\n");
            return 1;
        }
        if (trie[curr].sym >= 0) {
            if (out_pos >= decoded_len) {
                free(decoded);
                free(buf);
                fprintf(stderr, "ERR_DECODED_LENGTH_OVERFLOW\n");
                return 1;
            }
            decoded[out_pos++] = (uint8_t)trie[curr].sym;
            curr = 0;
        }
    }

    if (curr != 0 || out_pos != decoded_len) {
        free(decoded);
        free(buf);
        fprintf(stderr, "ERR_DECODED_LENGTH_MISMATCH\n");
        return 1;
    }

    if (argc >= 3) {
        FILE *ef = fopen(argv[2], "rb");
        if (!ef) {
            free(decoded);
            free(buf);
            return 2;
        }
        if (fseek(ef, 0, SEEK_END) != 0) {
            fclose(ef);
            free(decoded);
            free(buf);
            return 2;
        }
        long esize = ftell(ef);
        rewind(ef);
        if ((uint32_t)esize != decoded_len) {
            fclose(ef);
            free(decoded);
            free(buf);
            fprintf(stderr, "ERR_EXPECTED_SIZE_MISMATCH\n");
            return 1;
        }
        uint8_t *ebuf = (uint8_t *)malloc(esize > 0 ? (size_t)esize : 1);
        if (esize > 0 && fread(ebuf, 1, (size_t)esize, ef) != (size_t)esize) {
            free(ebuf);
            fclose(ef);
            free(decoded);
            free(buf);
            return 2;
        }
        fclose(ef);
        if (esize > 0 && memcmp(decoded, ebuf, (size_t)esize) != 0) {
            free(ebuf);
            free(decoded);
            free(buf);
            fprintf(stderr, "ERR_PAYLOAD_MISMATCH\n");
            return 1;
        }
        free(ebuf);
    }

    free(decoded);
    free(buf);
    printf("C_CONSUMER_OK decoded_len=%u meaningful_bits=%u\n", decoded_len, meaningful_bits);
    return 0;
}
