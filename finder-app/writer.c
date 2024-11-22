#include <unistd.h> 
#include <syslog.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>

int main (int argc, char *argv[]){


    if(argc != 3){
         syslog(LOG_ERR, "No enough args were provided");
         return 1;
    }


    syslog(LOG_DEBUG, "Writing %s to %s", argv[2], argv[1]);

    int fd = open(argv[1], O_RDWR | O_CREAT); 
    if (fd == -1) { 
        syslog(LOG_ERR, "Not possible to create file");
        return 1;
    }

    int count = strlen(argv[2]);

    int nr = write(fd, argv[2], count);

    if(nr == -1) {
        syslog(LOG_ERR, "Error to write file");
        return 1;
    } else if (nr != count ){
        syslog(LOG_ERR, "Error to write file");
        return 1;
    }
    
    if (close (fd) == 1) {
        syslog(LOG_ERR, "Error to close file");
    }

    return 0;

}