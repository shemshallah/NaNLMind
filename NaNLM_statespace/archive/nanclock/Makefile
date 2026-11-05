CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic
TARGET = temporal_nan
SRC = main.c temporal_nan.c

all: $(TARGET)

$(TARGET): $(SRC) temporal_nan.h
	$(CC) $(CFLAGS) -o $@ $(SRC)

test: $(TARGET)
	./test.sh

clean:
	rm -f $(TARGET) *.o
