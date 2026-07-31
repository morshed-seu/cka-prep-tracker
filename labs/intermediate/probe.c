/* probe.c — attempt exactly what each hardening control forbids, and report
   the error each one produces.  Static, so it runs in an image with no libc. */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

static void report(const char *what, int rc) {
    if (rc < 0)
        printf("  %-34s BLOCKED   errno=%-3d %s\n", what, errno, strerror(errno));
    else
        printf("  %-34s SUCCEEDED\n", what);
}

int main(void) {
    int fd;
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("identity: uid=%d euid=%d\n", getuid(), geteuid());
    printf("attempts:\n");

    /* read-only rootfs */
    fd = open("/escape", O_CREAT | O_WRONLY, 0644);
    report("write a file into /", fd);
    if (fd >= 0) close(fd);

    /* the tmpfs is meant to work */
    fd = open("/tmp/scratch", O_CREAT | O_WRONLY, 0644);
    report("write a file into /tmp", fd);
    if (fd >= 0) close(fd);

    /* dropped capabilities: CAP_CHOWN */
    report("chown /tmp/scratch to 99:99", chown("/tmp/scratch", 99, 99));

    /* seccomp: mkdirat is not in the allow-list */
    report("mkdir /tmp/d", mkdir("/tmp/d", 0755));

    /* noNewPrivileges: exec a setuid-root binary */
    {
        pid_t p = fork();
        if (p == 0) { execl("/suid", "/suid", (char *)NULL); _exit(127); }
        waitpid(p, NULL, 0);
    }
    return 0;
}
