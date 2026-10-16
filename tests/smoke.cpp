#include <array>

extern "C" int test_main()
{
    volatile int first = 17;
    volatile int second = 25;
    std::array<int, 2> values = {first, second};
    return values[0] + values[1] == 42 ? 0 : 1;
}
