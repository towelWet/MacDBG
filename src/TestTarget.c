#include <stdio.h>

int main() {
    printf("Hello from TestTarget! Waiting for debugger...\n");
    // This will keep the process alive until you press Enter in the terminal
    // where it's running.
    getchar(); 
    printf("TestTarget exiting.\n");
    return 0;
}
