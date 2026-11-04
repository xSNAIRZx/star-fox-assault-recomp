"""Execute generated floating compares followed by mffs and mcrfs, without a ROM.

IBM specifies that fcmpu/fcmpo update FPSCR[FPCC] as well as the CR field:
https://www.ibm.com/docs/en/aix/7.1.0?topic=set-fcmpu-floating-compare-unordered-instruction
This checks condition codes and preservation, not floating exception emulation.
"""
import argparse
import math
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'recomp'))
import ppc


def number(value):
    if math.isnan(value):
        return 'NAN'
    if math.isinf(value):
        return '-INFINITY' if value < 0 else 'INFINITY'
    return repr(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', required=True)
    parser.add_argument('--work', required=True)
    args = parser.parse_args()
    work = pathlib.Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    runtime = pathlib.Path(__file__).resolve().parents[1] / 'runtime'
    # The paired lane-one compares use the reverse ordering of lane zero.
    comparisons = [(63, 0, False), (63, 32, False), (4, 0, False),
                   (4, 32, False), (4, 64, True), (4, 96, True)]
    operands = [(1., 2.), (2., 1.), (1., 1.), (-0., 0.),
                (float('inf'), -float('inf')), (float('nan'), 1.),
                (1., float('nan')), (float('nan'), float('nan'))]
    # Expected FPRF classifications are architecture codes, independent of the helper.
    pending = [(0, 1., None), (1, 1., 0x04), (1, float('nan'), 0x11),
               (2, 1.e-40, 0x14), (2, -0., 0x12), (1, float('inf'), 0x05)]
    functions = []
    checks = []
    mffs = ppc.translate(0x80001004, (63 << 26) | (31 << 21) | (583 << 1))
    mcrfs = ppc.translate(0x80001008, (63 << 26) | (28 << 21) | (16 << 16) | (64 << 1))
    for op, xo, lane_one in comparisons:
        instruction = (op << 26) | (12 << 21) | (1 << 16) | (2 << 11) | (xo << 1)
        name = f'op_{len(functions)}'
        code = ppc.translate(0x80001000, instruction)
        functions.append(f'static void {name}(CPU* c) {{ {code} {mffs} {mcrfs} }}')
        for a, b in operands:
            x, y = (b, a) if lane_one else (a, b)
            result = 8 if x < y else 4 if x > y else 2 if x == y else 1
            for mode, value, classification in pending:
                initial = 0xa5a1b12b
                materialized = initial if classification is None else (initial & ~0x1f000) | (classification << 12)
                expected = (materialized & ~0xf000) | (result << 12)
                # Ordered/signaling NaN exception flags are a separate, existing
                # emulation gap. Do not freeze their current omission into this
                # condition-code regression; finite cases preserve every FPSCR bit.
                status_mask = 0x1f007 if math.isnan(x) or math.isnan(y) else 0xffffffff
                checks.append(f'''{{
                    CPU cpu; memset(&cpu, 0x5a, sizeof cpu);
                    cpu.f[1].d = {number(a)}; cpu.f[2].d = {number(b)};
                    cpu.ps1[1] = {number(b)}; cpu.ps1[2] = {number(a)};
                    cpu.fpscr = 0x{initial:08x}u;
                    cpu.fprf_v = {number(value)}; cpu.fprf_pending = {mode};
                    CPU expected = cpu;
                    expected.cr[3] = expected.cr[7] = {result};
                    expected.fpscr = 0x{expected:08x}u; expected.fprf_pending = 0;
                    expected.f[31].u = 0xfff8000000000000ull | expected.fpscr;
                    {name}(&cpu);
                    cpu.fpscr &= 0x{status_mask:08x}u;
                    expected.fpscr &= 0x{status_mask:08x}u;
                    cpu.f[31].u &= 0xffffffff00000000ull | 0x{status_mask:08x}u;
                    expected.f[31].u &= 0xffffffff00000000ull | 0x{status_mask:08x}u;
                    if (memcmp(&cpu, &expected, sizeof cpu)) {{
                        fprintf(stderr, "compare check {len(checks)}: CR=%X FPSCR=%08X mffs=%08X mcrfs=%X expected FPCC {result:X}, FPSCR {expected:08X}\\n",
                            (unsigned)cpu.cr[3], (unsigned)cpu.fpscr, (unsigned)cpu.f[31].u, (unsigned)cpu.cr[7]);
                        return 1;
                    }}
                }}''')
    source = work / 'ppc_fp_compare_test.c'
    source.write_text('\n'.join([
        '#include "recomp.h"', '#include <stdio.h>', *functions,
        'int main(void) {', *checks,
        f'puts("floating compare generated-code checks: {len(checks)} passed");',
        'return 0; }',
    ]), encoding='utf-8')
    executable = work / ('ppc_fp_compare_test.exe' if sys.platform == 'win32' else 'ppc_fp_compare_test')
    subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-I', str(runtime), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()
