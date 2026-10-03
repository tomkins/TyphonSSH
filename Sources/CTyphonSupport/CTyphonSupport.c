#include "CTyphonSupport.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <util.h>

pid_t typhon_spawn_pty(char *const argv[], unsigned short rows, unsigned short columns, int *primary_fd) {
    struct winsize size = { .ws_row = rows, .ws_col = columns };
    pid_t pid = forkpty(primary_fd, NULL, NULL, &size);
    if (pid == 0) {
        // Ignored signals and the signal mask survive exec. The parent ignores
        // SIGWINCH (it handles it through a dispatch source), and ssh must not.
        for (int signal = 1; signal < NSIG; signal++) {
            if (signal != SIGKILL && signal != SIGSTOP) {
                sigaction(signal, &(struct sigaction){ .sa_handler = SIG_DFL }, NULL);
            }
        }
        sigset_t empty;
        sigemptyset(&empty);
        sigprocmask(SIG_SETMASK, &empty, NULL);

        execvp(argv[0], argv);
        dprintf(STDERR_FILENO, "tyssh: can't run %s: %s\r\n", argv[0], strerror(errno));
        _exit(127);
    }
    return pid;
}

int typhon_set_window_size(int fd, unsigned short rows, unsigned short columns) {
    struct winsize size = { .ws_row = rows, .ws_col = columns };
    return ioctl(fd, TIOCSWINSZ, &size);
}

int typhon_get_window_size(int fd, unsigned short *rows, unsigned short *columns) {
    struct winsize size;
    if (ioctl(fd, TIOCGWINSZ, &size) != 0) return -1;
    *rows = size.ws_row;
    *columns = size.ws_col;
    return 0;
}
