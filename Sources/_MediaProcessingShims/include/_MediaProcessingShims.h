#ifdef __cplusplus
extern "C" {
#endif

#define HEADER_SHIM static inline __attribute__((__always_inline__))

// MARK: - math functions for float
HEADER_SHIM float libm_cosf(float x) {
    return __builtin_cosf(x);
}

// MARK: - math functions for double

HEADER_SHIM double libm_cos(double x) {
    return __builtin_cos(x);
}

#undef CLANG_RELAX_FP

#ifdef __cplusplus
}
#endif
