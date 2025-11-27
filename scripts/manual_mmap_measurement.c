#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <string.h>

#define ITERATIONS 33
#define FILE_SIZE (1024 * 1024) // 1MB
#define FILENAME "test_file.dat"

// Function to create a dummy file for mmap
void create_dummy_file() {
    int fd = open(FILENAME, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror("Error creating dummy file");
        exit(1);
    }
    char *data = malloc(FILE_SIZE);
    if (data == NULL) {
        perror("Error allocating memory");
        close(fd);
        exit(1);
    }
    memset(data, 'A', FILE_SIZE);
    write(fd, data, FILE_SIZE);
    free(data);
    close(fd);
}

// Function to measure time for a syscall
double measure_syscall_time(void (*syscall_func)(), const char* syscall_name) {
    struct timeval start, end;
    double total_time_ms = 0.0;

    for (int i = 0; i < ITERATIONS; ++i) {
        gettimeofday(&start, NULL);
        syscall_func();
        gettimeofday(&end, NULL);

        long seconds = end.tv_sec - start.tv_sec;
        long microseconds = end.tv_usec - start.tv_usec;
        total_time_ms += (seconds * 1000.0) + (microseconds / 1000.0);
    }

    double average_time_ms = total_time_ms / ITERATIONS;
    printf("Average time for %s over %d iterations: %.5f ms\n", syscall_name, ITERATIONS, average_time_ms);
    return average_time_ms;
}

// Dummy functions for receive and mmap to be passed to measure_syscall_time
void dummy_receive() {
    // A simplified 'receive' operation without a real network connection.
    // In a real-world scenario, you'd have a socket.
    // Here, we simulate reading from a file as a proxy for I/O.
    int fd = open(FILENAME, O_RDONLY);
    if (fd < 0) {
        perror("Error opening dummy file for receive");
        return;
    }
    char buffer[1024];
    read(fd, buffer, sizeof(buffer));
    close(fd);
}

void dummy_mmap() {
    int fd = open(FILENAME, O_RDONLY);
    if (fd < 0) {
        perror("Error opening dummy file for mmap");
        return;
    }
    void *addr = mmap(NULL, FILE_SIZE, PROT_READ, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) {
        perror("Error with mmap");
        close(fd);
        return;
    }
    // We just access a byte to ensure the mapping is effective
    char byte = ((char *)addr)[0]; 
    munmap(addr, FILE_SIZE);
    close(fd);
}

int main() {
    create_dummy_file();

    printf("Starting performance measurement...\n");
    printf("-----------------------------------\n");

    measure_syscall_time(dummy_receive, "receive (simulated)");
    measure_syscall_time(dummy_mmap, "mmap");

    printf("-----------------------------------\n");
    printf("Measurements complete.\n");

    // Clean up the dummy file
    unlink(FILENAME);

    return 0;
}
