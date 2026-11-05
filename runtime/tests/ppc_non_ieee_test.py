"""ROM-free generated-instruction tests for CPU-local non-IEEE result handling.

Single/double non-IEEE result behavior: MPC750 User's Manual, table 2-21.
https://www.nxp.com/docs/en/reference-manual/MPC750UM.pdf
No claim of complete FPSCR exception, rounding-mode or estimate fidelity.
"""
import argparse
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'recomp'))
import ppc


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cc', required=True)
    ap.add_argument('--work', required=True)
    args = ap.parse_args()
    work = pathlib.Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    instructions = {
        'add_s': (59 << 26) | (3 << 21) | (1 << 16) | (2 << 11) | (21 << 1),
        'mul_s': (59 << 26) | (3 << 21) | (1 << 16) | (2 << 6) | (25 << 1),
        'round_s': (63 << 26) | (3 << 21) | (1 << 11) | (12 << 1),
        'add_d': (63 << 26) | (3 << 21) | (1 << 16) | (2 << 11) | (21 << 1),
        'mul_d': (63 << 26) | (3 << 21) | (1 << 16) | (2 << 6) | (25 << 1),
        'pair_mul': (4 << 26) | (3 << 21) | (1 << 16) | (2 << 6) | (25 << 1),
        'pair_add': (4 << 26) | (3 << 21) | (1 << 16) | (2 << 11) | (21 << 1),
        # Deliberately alias the destination with a source for the length loop.
        'pair_square': (4 << 26) | (1 << 21) | (1 << 16) | (1 << 6) | (25 << 1),
        'pair_sum': (4 << 26) | (1 << 21) | (1 << 16) | (1 << 11) | (2 << 6) | (10 << 1),
    }
    functions = [f'static void {name}(CPU* c) {{ {ppc.translate(0x80001000, i)} }}'
                 for name, i in instructions.items()]
    source = r'''
#include "recomp.h"
#include <stdio.h>
FUNCTIONS
static int checks;
static int same(double a, double b) {
    if (isnan(b)) return isnan(a);
    return a == b && (a != 0.0 || (signbit(a) != 0) == (signbit(b) != 0));
}
static int check(const char* label, double got, double expected) {
    ++checks;
    if (same(got, expected)) return 1;
    fprintf(stderr, "%s: %.17g expected %.17g\n", label, got, expected);
    return 0;
}
int main(void) {
    for (int ni = 0; ni != 2; ++ni) {
        CPU c; memset(&c, 0, sizeof c);
        c.fpscr = ni ? 4u : 0u;
        c.f[1].d = FLT_MIN; c.f[2].d = -(double)FLT_MIN / 2;
        add_s(&c);
        if (!check("single positive subnormal", c.f[3].d, ni ? 0.0 : (double)FLT_MIN / 2)) return 1;
        if (!check("single duplicate lane", c.ps1[3], c.f[3].d)) return 1;
        c.f[1].d = -FLT_MIN; c.f[2].d = (double)FLT_MIN / 2;
        add_s(&c);
        if (!check("single negative subnormal", c.f[3].d, ni ? -0.0 : -(double)FLT_MIN / 2)) return 1;
        c.f[1].d = FLT_MIN; c.f[2].d = 1.0;
        mul_s(&c);
        if (!check("single minimum normal preserved", c.f[3].d, FLT_MIN)) return 1;
        c.f[1].d = 1.25; c.f[2].d = -2.0;
        mul_s(&c);
        if (!check("normal multiply unchanged", c.f[3].d, -2.5)) return 1;
        c.f[1].d = 0.0; c.f[2].d = -2.0;
        mul_s(&c);
        if (!check("negative zero preserved", c.f[3].d, -0.0)) return 1;
        c.f[1].d = INFINITY;
        round_s(&c);
        if (!check("infinity preserved", c.f[3].d, INFINITY)) return 1;
        c.f[1].d = NAN;
        round_s(&c);
        if (!check("NaN preserved", c.f[3].d, NAN)) return 1;
        c.f[1].d = (double)FLT_MIN - 0x1p-151;
        round_s(&c);
        if (!check("flush before round-to-normal", c.f[3].d, ni ? 0.0 : FLT_MIN)) return 1;
        c.f[1].d = -(double)FLT_MIN + 0x1p-151;
        round_s(&c);
        if (!check("negative flush before rounding", c.f[3].d, ni ? -0.0 : -FLT_MIN)) return 1;
        c.f[1].d = (double)FLT_MIN / 2;
        round_s(&c);
        if (!check("frsp flush", c.f[3].d, ni ? 0.0 : (double)FLT_MIN / 2)) return 1;
        c.f[1].d = DBL_MIN; c.f[2].d = -DBL_MIN / 2;
        c.ps1[3] = 123.0;
        add_d(&c);
        if (!check("double subnormal", c.f[3].d, ni ? 0.0 : DBL_MIN / 2)) return 1;
        if (!check("double leaves paired lane intact", c.ps1[3], 123.0)) return 1;
        c.f[1].d = -DBL_MIN; c.f[2].d = 0.5;
        mul_d(&c);
        if (!check("double negative subnormal", c.f[3].d, ni ? -0.0 : -DBL_MIN / 2)) return 1;
        c.f[1].d = DBL_MIN; c.f[2].d = 1.0;
        mul_d(&c);
        if (!check("double minimum normal preserved", c.f[3].d, DBL_MIN)) return 1;
        c.f[1].d = FLT_MIN; c.ps1[1] = -FLT_MIN;
        c.f[2].d = 0.5; c.ps1[2] = 0.5;
        pair_mul(&c);
        if (!check("paired lane0 flush", c.f[3].d, ni ? 0.0 : (double)FLT_MIN / 2)) return 1;
        if (!check("paired lane1 signed flush", c.ps1[3], ni ? -0.0 : -(double)FLT_MIN / 2)) return 1;
        c.f[1].d = FLT_MIN; c.ps1[1] = -FLT_MIN;
        c.f[2].d = -(double)FLT_MIN / 2; c.ps1[2] = (double)FLT_MIN / 2;
        pair_add(&c);
        if (!check("paired add lane0", c.f[3].d, ni ? 0.0 : (double)FLT_MIN / 2)) return 1;
        if (!check("paired add lane1", c.ps1[3], ni ? -0.0 : -(double)FLT_MIN / 2)) return 1;
        if (c.fpscr != (ni ? 4u : 0u)) { fputs("NI altered CPU FPSCR bits\n", stderr); return 1; }
    }
    // A tiny synthetic vector approaches zero. With IEEE results its nonzero
    // subnormal squared length enters inverse-square-root normalization and the
    // single inverse-square overflows; NI results make the caller's length>0
    // guard reject that normalization. No game instruction bytes are used.
    for (int ni = 0; ni != 2; ++ni) {
        CPU c; memset(&c, 0, sizeof c); c.fpscr = ni ? 4 : 0;
        c.f[1].d = 1.e-22; c.ps1[1] = -1.e-22;
        pair_square(&c); pair_sum(&c);
        const double len2 = c.f[1].d;
        if (ni) {
            if (!check("NI tiny-vector length guard", len2, 0.0)) return 1;
        } else {
            if (!(len2 > 0.0 && len2 < FLT_MIN)) return 1;
            c.f[1].d = 1.0 / sqrt(len2); c.f[2].d = c.f[1].d;
            mul_s(&c);
            if (!check("IEEE inverse square overflow reproduced", c.f[3].d, INFINITY)) return 1;
        }
    }
    printf("non-IEEE generated-code checks: %d passed\n", checks);
    return 0;
}
'''.replace('FUNCTIONS', '\n'.join(functions))
    cfile = work / 'ppc_non_ieee_test.c'
    cfile.write_text(source, encoding='utf-8')
    exe = work / ('ppc_non_ieee_test.exe' if sys.platform == 'win32' else 'ppc_non_ieee_test')
    runtime = pathlib.Path(__file__).resolve().parents[1] / 'runtime'
    cmd = [args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I', str(runtime), str(cfile), '-o', str(exe)]
    if sys.platform != 'win32':
        cmd += ['-lm']
    subprocess.run(cmd, check=True)
    subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
