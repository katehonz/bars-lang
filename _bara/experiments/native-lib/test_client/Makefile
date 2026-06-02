CC = gcc
CFLAGS = -I../build -L../build
LDFLAGS = -lmath -Wl,-rpath,'$$ORIGIN/../build'

all: test_client

test_client: main.c
	$(CC) $(CFLAGS) main.c $(LDFLAGS) -o test_client

clean:
	rm -f test_client
