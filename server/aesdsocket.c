#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h> 
#include <syslog.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdbool.h>

#define PORT "9000"  // the port users will be connecting to

#define BACKLOG 10   // how many pending connections queue will hold

#define BUFFER_SIZE 1024

volatile bool keep_running = true;

void sigchld_handler(int s)
{
    // syslog(LOG_DEBUG, "Received signal %d, shutting down server", signal);
    syslog(LOG_DEBUG, "Caught signal, exiting");
    
    keep_running = false;
}

// get sockaddr, IPv4 or IPv6:
void *get_in_addr(struct sockaddr *sa)
{
    if (sa->sa_family == AF_INET) {
        return &(((struct sockaddr_in*)sa)->sin_addr);
    }

    return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

void daemonize() {
    pid_t pid = fork();

    if (pid < 0) {
        perror("Fork failed");
        exit(EXIT_FAILURE);
    }

    if (pid > 0) {
        // Parent process exits, leaving the child in the background
        exit(EXIT_SUCCESS);
    }

    // Child process continues
    if (setsid() < 0) {
        perror("Failed to create new session");
        exit(EXIT_FAILURE);
    }

    // Redirect standard file descriptors to /dev/null
    freopen("/dev/null", "r", stdin);
    freopen("/dev/null", "w", stdout);
    freopen("/dev/null", "w", stderr);
}

int main (int argc, char *argv[]){
    int sockfd, new_fd;  // listen on sock_fd, new connection on new_fd
    struct addrinfo hints, *servinfo, *p;
    struct sockaddr_storage their_addr; // connector's address information
    socklen_t sin_size;
    struct sigaction sa;
    int yes=1;
    char s[INET6_ADDRSTRLEN];
    int rv;
    int file_fd;

    char buffer[BUFFER_SIZE];
    ssize_t bytes_received, bytes_written;



    // Check for the `-d` argument
    bool daemon_mode = false;
    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        daemon_mode = true;
    } else if (argc > 1) {
        fprintf(stderr, "Usage: %s [-d]\n", argv[0]);
        exit(EXIT_FAILURE);
    }


    // Open or create the file
    const char *file_path = "/var/tmp/aesdsocketdata";
    file_fd = open(file_path, O_RDWR | O_CREAT | O_APPEND, 0644);
    if (file_fd == -1) {
        syslog(LOG_ERR, "Failed to open file: %s", strerror(errno));
        return -1;
    }

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE; // use my IP

    if ((rv = getaddrinfo(NULL, PORT, &hints, &servinfo)) != 0) {
        syslog(LOG_ERR, "getaddrinfo: %s\n", gai_strerror(rv));
        return -1;
    }

    // loop through all the results and bind to the first we can
    for(p = servinfo; p != NULL; p = p->ai_next) {
        if ((sockfd = socket(p->ai_family, p->ai_socktype,
                p->ai_protocol)) == -1) {
            perror("server: socket");
            continue;
        }

        if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes,
                sizeof(int)) == -1) {
            perror("setsockopt");
            exit(-1);
        }

        if (bind(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
            close(sockfd);
            perror("server: bind");
            continue;
        }

        break;
    }

    // If daemon mode is enabled, daemonize the process
    if (daemon_mode) {
        daemonize();
    }

    freeaddrinfo(servinfo); // all done with this structure

    if (p == NULL)  {
        fprintf(stderr, "server: failed to bind\n");
        exit(-1);
    }

    if (listen(sockfd, BACKLOG) == -1) {
        perror("listen");
        exit(-1);
    }

    sa.sa_handler = sigchld_handler; // reap all dead processes
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    if (sigaction(SIGINT, &sa, NULL) == -1) {
        perror("sigaction");
        exit(1);
    }

    if (sigaction(SIGTERM, &sa, NULL) == -1) {
        perror("sigaction");
        exit(1);
    }


    syslog(LOG_DEBUG, "waiting for connections...\n");
    
    while(keep_running) {  // main accept() loop
        sin_size = sizeof their_addr;
        new_fd = accept(sockfd, (struct sockaddr *)&their_addr, &sin_size);
        if (new_fd == -1) {
            perror("accept");
            continue;
        }

        inet_ntop(their_addr.ss_family,
            get_in_addr((struct sockaddr *)&their_addr),
            s, sizeof s);
        syslog(LOG_DEBUG, "Accepted connection from  %s\n", s);


                // Receive and process data
        while ((bytes_received = recv(new_fd, buffer, BUFFER_SIZE - 1, 0)) > 0) {
            buffer[bytes_received] = '\0'; // Null-terminate received data

            // Write received data to file
            bytes_written = write(file_fd, buffer, bytes_received);
            if (bytes_written != bytes_received) {
                syslog(LOG_ERR, "Failed to write to file: %s", strerror(errno));
                break;
            }

            // Check for newline to consider packet complete
            if (strchr(buffer, '\n')) {
                // Send file content back to client
                lseek(file_fd, 0, SEEK_SET); // Rewind file to the beginning
                char file_buffer[BUFFER_SIZE];
                ssize_t file_bytes_read;
                while ((file_bytes_read = read(file_fd, file_buffer, BUFFER_SIZE)) > 0) {
                    if (send(new_fd, file_buffer, file_bytes_read, 0) == -1) {
                        syslog(LOG_ERR, "Failed to send data to client: %s", strerror(errno));
                        break;
                    }
                }
            }
        }

        if (bytes_received == -1) {
            syslog(LOG_ERR, "Error receiving data: %s", strerror(errno));
        }

        // Close the client connection
        syslog(LOG_INFO, "Closed connection from %d", new_fd);
        close(new_fd);
    }

    if (sockfd != -1) close(sockfd);
    if (file_fd != -1) close(file_fd);

    if (remove(file_path) == -1) {
        syslog(LOG_ERR, "Failed to delete file %s: %s", file_path, strerror(errno));
    }

    return 0;
}