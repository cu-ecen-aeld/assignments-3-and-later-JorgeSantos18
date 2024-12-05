
CC ?= cc

all: aesdsocket
default: all

aesdsocket: aesdsocket.c
	$(CC) -o $@ $^

clean:
	rm -rf aesdsocket

.PHONY: all clean