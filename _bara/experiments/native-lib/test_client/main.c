#include <stdio.h>

// Declarations from the shared library
extern int c_square(int x);
extern int c_factorial(int n);
extern int c_add(int a, int b);
extern const char* c_greet(const char* name);

// Nim runtime init
extern void NimMain(void);

int main(void) {
    NimMain();

    printf("=== Bara Lang Native Library Test ===\n\n");

    printf("c_square(7) = %d\n", c_square(7));
    printf("c_add(10, 20) = %d\n", c_add(10, 20));
    printf("c_factorial(5) = %d\n", c_factorial(5));
    printf("c_greet(\"World\") = %s\n", c_greet("World"));

    printf("\nAll tests passed! Bara Lang in a .so file.\n");
    return 0;
}
