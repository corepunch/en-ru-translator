#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DICT_SIZE 4096
#define HEADER_SIZE 14

static unsigned char dict[DICT_SIZE];

int decompress(FILE *in, FILE *out, long original_size)
{
    unsigned char *obuf = malloc(original_size);
    if (!obuf) return -1;

    int di = 0, oi = 0, flags = 0, bits = 0;
    memset(dict, 0, DICT_SIZE);

    while (oi < original_size) {
        if (bits == 0) {
            int c = fgetc(in);
            if (c == EOF) break;
            flags = c;
            bits = 8;
        }
        bits--;

        if (flags & 0x80) {
            int c = fgetc(in);
            if (c == EOF) break;
            obuf[oi++] = c;
            dict[di] = c;
            di = (di + 1) & (DICT_SIZE - 1);
        } else {
            int a = fgetc(in);
            int b = fgetc(in);
            if (a == EOF || b == EOF) break;
            int len = (a >> 4) + 3;
            int off = ((a & 0x0F) << 8) | b;
            for (int i = 0; i < len && oi < original_size; i++) {
                unsigned char c = dict[(off + i) & (DICT_SIZE - 1)];
                obuf[oi++] = c;
                dict[di] = c;
                di = (di + 1) & (DICT_SIZE - 1);
            }
        }
        flags <<= 1;
    }

    if (oi != original_size) {
        fprintf(stderr, "expected %ld bytes, got %d\n", original_size, oi);
        free(obuf);
        return -1;
    }

    fwrite(obuf, 1, original_size, out);
    free(obuf);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 4) {
        fprintf(stderr, "Usage: %s input [output]\n", argv[0]);
        fprintf(stderr, "  If output is omitted, strips trailing _ from input name\n");
        return 1;
    }

    FILE *in = fopen(argv[1], "rb");
    if (!in) { perror(argv[1]); return 1; }

    unsigned char hdr[HEADER_SIZE];
    if (fread(hdr, 1, HEADER_SIZE, in) != HEADER_SIZE) {
        fprintf(stderr, "%s: truncated header\n", argv[1]);
        fclose(in); return 1;
    }
    if (memcmp(hdr, "SZDD", 4) != 0) {
        fprintf(stderr, "%s: not an SZDD file (signature: %c%c%c%c)\n",
                argv[1], hdr[0], hdr[1], hdr[2], hdr[3]);
        fclose(in); return 1;
    }
    if (hdr[8] != 0x41) {
        fprintf(stderr, "%s: unsupported format byte 0x%02X (expected 0x41)\n",
                argv[1], hdr[8]);
        fclose(in); return 1;
    }

    long orig_size = (long)hdr[10] | ((long)hdr[11] << 8)
                   | ((long)hdr[12] << 16) | ((long)hdr[13] << 24);

    char ext_last = hdr[9];
    printf("%s: %ld bytes -> %c%c%c\n", argv[1], orig_size,
           hdr[8], ext_last, ext_last);

    char outname[1024];
    if (argc >= 3) {
        strncpy(outname, argv[2], sizeof(outname) - 1);
        outname[sizeof(outname) - 1] = 0;
    } else {
        size_t len = strlen(argv[1]);
        if (len > 0 && argv[1][len - 1] == '_' && ext_last) {
            strncpy(outname, argv[1], sizeof(outname) - 1);
            outname[sizeof(outname) - 1] = 0;
            outname[len - 1] = ext_last;
        } else {
            snprintf(outname, sizeof(outname), "%s.out", argv[1]);
        }
    }

    FILE *out = fopen(outname, "wb");
    if (!out) { perror(outname); fclose(in); return 1; }

    int ret = decompress(in, out, orig_size);
    fclose(in); fclose(out);

    if (ret == 0)
        printf("-> %s\n", outname);
    return ret;
}
