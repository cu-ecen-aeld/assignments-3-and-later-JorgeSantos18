
CROSS_COMPILE ?=

all: writer

writer: writer.c
	$(CROSS_COMPILE)gcc -o $@ $^

clean:
	rm -rf writer

.PHONY: all clean