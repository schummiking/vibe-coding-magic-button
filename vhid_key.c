// vhid_key - Minimal VirtualHID key sender
// Reads commands from stdin: "down\n" or "up\n"
// Build: cc -O2 -o vhid_key vhid_key.c

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/select.h>
#include <dirent.h>
#include <time.h>
#include <stdint.h>

#define FRAMING_USER_DATA 0x01
#define REQ_KB_INIT 1
#define REQ_POST_KB 7
#define RESP_KB_READY 4
#define KB_REPORT_SIZE 67

static int vhid_fd = -1;
static struct sockaddr_un vhid_server;
static char client_path[256];

static void vhid_send(uint8_t req, const void *data, size_t len) {
    uint8_t buf[256]; size_t off = 0;
    buf[off++] = FRAMING_USER_DATA;
    buf[off++] = 0x63; buf[off++] = 0x70;
    uint16_t v = 5; memcpy(buf + off, &v, 2); off += 2;
    buf[off++] = req;
    if (data && len) { memcpy(buf + off, data, len); off += len; }
    sendto(vhid_fd, buf, off, 0, (struct sockaddr *)&vhid_server, sizeof(vhid_server));
}

static void send_report(uint8_t mods, uint16_t key) {
    uint8_t rpt[KB_REPORT_SIZE];
    memset(rpt, 0, sizeof(rpt));
    rpt[0] = 1; // report_id
    rpt[1] = mods;
    if (key) {
        rpt[3] = key & 0xFF;
        rpt[4] = (key >> 8) & 0xFF;
    }
    vhid_send(REQ_POST_KB, rpt, sizeof(rpt));
}

static int init(void) {
    const char *dir = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server";
    DIR *d = opendir(dir);
    if (!d) { fprintf(stderr, "Cannot open vhidd_server dir\n"); return -1; }
    struct dirent *ent; char best[256] = {0};
    while ((ent = readdir(d)))
        if (strstr(ent->d_name, ".sock") && strcmp(ent->d_name, best) > 0)
            strncpy(best, ent->d_name, sizeof(best) - 1);
    closedir(d);
    if (!best[0]) { fprintf(stderr, "No socket found\n"); return -1; }

    char sp[512]; snprintf(sp, sizeof(sp), "%s/%s", dir, best);
    vhid_fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (vhid_fd < 0) { perror("socket"); return -1; }

    struct sockaddr_un ca = {0}; ca.sun_family = AF_UNIX;
    snprintf(client_path, sizeof(client_path),
        "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_client/%lx%x.sock",
        (unsigned long)time(NULL), getpid());
    strncpy(ca.sun_path, client_path, sizeof(ca.sun_path) - 1);
    if (bind(vhid_fd, (struct sockaddr *)&ca, sizeof(ca)) < 0) { perror("bind"); close(vhid_fd); return -1; }

    memset(&vhid_server, 0, sizeof(vhid_server));
    vhid_server.sun_family = AF_UNIX;
    strncpy(vhid_server.sun_path, sp, sizeof(vhid_server.sun_path) - 1);

    uint8_t params[24] = {0};
    uint64_t vendor = 0x16c0, product = 0x27db;
    memcpy(params, &vendor, 8); memcpy(params + 8, &product, 8);
    vhid_send(REQ_KB_INIT, params, sizeof(params));

    for (int i = 0; i < 100; i++) {
        fd_set fds; FD_ZERO(&fds); FD_SET(vhid_fd, &fds);
        struct timeval tv = {0, 50000};
        if (select(vhid_fd + 1, &fds, NULL, NULL, &tv) > 0) {
            uint8_t rb[256]; ssize_t n = recv(vhid_fd, rb, sizeof(rb), 0);
            if (n >= 3 && rb[0] == FRAMING_USER_DATA && rb[1] == RESP_KB_READY && rb[2]) {
                fprintf(stderr, "[vhid_key] Keyboard ready\n");
                return 0;
            }
        }
    }
    fprintf(stderr, "[vhid_key] Warning: ready timeout\n");
    return 0;
}

int main(void) {
    if (getuid() != 0) { fprintf(stderr, "Need root\n"); return 1; }
    if (init() < 0) return 1;

    // Left Option/Alt: HID usage 0xE2, modifier bit 0x04
    const uint8_t MOD = 0x04;
    const uint16_t KEY = 0xE2;

    char line[64];
    while (fgets(line, sizeof(line), stdin)) {
        if (strncmp(line, "tap", 3) == 0) {
            // Simulate a full key press: down then up
            send_report(MOD, KEY);
            usleep(150000); // 150ms hold
            send_report(0, 0);
            fprintf(stderr, "[vhid_key] Key TAP (down+up)\n");
            fflush(stderr);
        } else if (strncmp(line, "enter", 5) == 0) {
            // Enter/Return key: HID usage 0x28, no modifier
            send_report(0, 0x28);
            usleep(100000); // 100ms hold
            send_report(0, 0);
            fprintf(stderr, "[vhid_key] ENTER\n");
            fflush(stderr);
        } else if (strncmp(line, "escape", 6) == 0) {
            // Escape key: HID usage 0x29, no modifier
            send_report(0, 0x29);
            usleep(100000); // 100ms hold
            send_report(0, 0);
            fprintf(stderr, "[vhid_key] ESCAPE\n");
            fflush(stderr);
        }
    }

    send_report(0, 0);
    close(vhid_fd);
    unlink(client_path);
    return 0;
}
