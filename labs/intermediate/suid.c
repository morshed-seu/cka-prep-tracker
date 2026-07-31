/* suid.c — installed setuid-root inside the image; prints what the kernel gave it. */
#include <stdio.h>
#include <unistd.h>
int main(void) {
    printf("  %-34s uid=%d euid=%d%s\n", "exec setuid-root /suid",
           getuid(), geteuid(), geteuid() == 0 ? "   <-- ESCALATED" : "   <-- no escalation");
    return 0;
}
