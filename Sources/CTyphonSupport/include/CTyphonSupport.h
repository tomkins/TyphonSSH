#ifndef CTYPHON_SUPPORT_H
#define CTYPHON_SUPPORT_H

#include <sys/types.h>

/// Starts `argv[0]` (searched for on PATH) as the session leader of a new
/// pseudo-terminal of the given size, with the pty as its controlling terminal.
///
/// The fork and exec happen entirely in C so that no Swift runtime code runs in
/// the child between the two.
///
/// Returns the child's pid and stores the primary side's descriptor in
/// `*primary_fd`, or returns -1 and sets errno. If exec fails, the child exits
/// with status 127 after writing a message to the pty. Signal dispositions
/// and the signal mask are reset to their defaults in the child.
pid_t typhon_spawn_pty(char *const argv[], unsigned short rows, unsigned short columns, int *primary_fd);

/// Sets the window size of a terminal. Returns 0 on success, or -1 and sets errno.
int typhon_set_window_size(int fd, unsigned short rows, unsigned short columns);

/// Reads the window size of a terminal. Returns 0 on success, or -1 and sets errno.
int typhon_get_window_size(int fd, unsigned short *rows, unsigned short *columns);

#endif
