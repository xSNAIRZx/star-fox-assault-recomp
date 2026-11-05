"""Execute generated paired sums and mffs without game code.

ps_sum1 classifies its sum in PS1, not the copied PS0. Primary reference:
https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/PowerPC/Interpreter/Interpreter_Paired.cpp
Also verify aliased source/destination registers see both original source lanes.
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
    # a0, b1, copied c0, copied c1, arithmetic sum, expected FPRF class.
    # Opposite classifications in the copied lanes expose selecting the wrong lane.
    cases = [(1., -1., 5., -5., 0., 0x02),
             (-4., 1., 5., 5., -3., 0x08),
             (2., 3., -5., -5., 5., 0x04),
             (float('inf'), 1., -5., -5., float('inf'), 0x05),
             (-float('inf'), 1., 5., 5., -float('inf'), 0x09),
             (float('nan'), 1., 5., 5., float('nan'), 0x11)]
    functions, checks = [], []
    mffs = ppc.translate(0x80001004, (63 << 26) | (31 << 21) | (583 << 1))
    for xo in (10, 11):
        for dest in (1, 2, 3, 4):
            name = f'op_{len(functions)}'
            instruction = (4 << 26) | (dest << 21) | (1 << 16) | (2 << 11) | (3 << 6) | (xo << 1)
            functions.append(f'static void {name}(CPU* c) {{ {ppc.translate(0x80001000, instruction)} {mffs} }}')
            for a, b, c0, c1, result, classification in cases:
                expected0, expected1 = (result, c1) if xo == 10 else (c0, result)
                checks.append(f'''{{
                    CPU cpu; memset(&cpu, 0, sizeof cpu);
                    cpu.f[1].d = {number(a)}; cpu.ps1[1] = 99.;
                    cpu.f[2].d = 77.; cpu.ps1[2] = {number(b)};
                    cpu.f[3].d = {number(c0)}; cpu.ps1[3] = {number(c1)};
                    cpu.fpscr = 0x80000000u;
                    {name}(&cpu);
                    if (!same(cpu.f[{dest}].d, {number(expected0)}) ||
                        !same(cpu.ps1[{dest}], {number(expected1)}) ||
                        ((cpu.f[31].u >> 12) & 0x1f) != 0x{classification:x}) {{
                        fprintf(stderr, "paired sum check {len(checks)}: op {xo} dest {dest} FPRF=%02X expected {classification:02X}\\n",
                                (unsigned)((cpu.f[31].u >> 12) & 0x1f));
                        return 1;
                    }}
                }}''')
    source = work / 'ppc_paired_sum_test.c'
    source.write_text('\n'.join([
        '#include "recomp.h"', '#include <stdio.h>',
        'static int same(double a, double b) { return (isnan(a) && isnan(b)) || a == b; }',
        *functions, 'int main(void) {', *checks,
        f'puts("paired sum generated-code checks: {len(checks)} passed");',
        'return 0; }',
    ]), encoding='utf-8')
    executable = work / ('ppc_paired_sum_test.exe' if sys.platform == 'win32' else 'ppc_paired_sum_test')
    subprocess.run([args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-I', str(runtime), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()
