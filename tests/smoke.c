/* A small bare-metal integration probe, not an architectural certification test. */
int test_main(void)
{
#ifdef EXPECT_FAIL
    return 1;
#else
    volatile unsigned int a = 17;
    volatile unsigned int b = 25;
    return (a + b == 42 && a * b == 425) ? 0 : 1;
#endif
}
