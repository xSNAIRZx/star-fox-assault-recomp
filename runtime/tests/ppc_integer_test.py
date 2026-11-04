"""Execute generated mulli instructions with signed-overflow trapping enabled.

No disc, symbols or generated game code are used. --cc selects a GCC/Clang-style
host C compiler; --work selects an isolated build directory (not the source tree).
Reference: IBM mulli/muli instruction: retain the low 32 bits of the product.
https://www.ibm.com/docs/en/aix/7.1.0?topic=set-mulli-muli-multiply-low-immediate-instruction
"""
import argparse
import pathlib
import random
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'recomp'))
import ppc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', required=True)
    parser.add_argument('--work', required=True)
    args = parser.parse_args()
    work = pathlib.Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    runtime = pathlib.Path(__file__).resolve().parents[1] / 'runtime'
    rng = random.Random(0x750)
    values = [0, 1, 2, 0x7fff, 0x8000, 0xffff, 0x10000, 0x7ffffffe,
              0x7fffffff, 0x80000000, 0x80000001, 0xfffffffe, 0xffffffff]
    values += [rng.getrandbits(32) for _ in range(512)]
    immediates = [-32768, -32767, -2, -1, 0, 1, 2, 32767]
    # Include destination/source overlap and r0 as a real multiplication operand.
    functions = []
    cases = []
    for imm in immediates:
        for dest, source in [(3, 4), (3, 3), (4, 0)]:
            name = f'op_{len(functions)}'
            instruction = (7 << 26) | (dest << 21) | (source << 16) | (imm & 0xffff)
            code = ppc.translate(0x80001000, instruction)
            functions.append(f'static void {name}(CPU* c) {{ {code} }}')
            expected = ','.join(f'0x{(v * imm) & 0xffffffff:08x}u' for v in values)
            cases.append(f'''{{
                static const uint32_t expected[] = {{{expected}}};
                for (unsigned i = 0; i < count; ++i) {{
                    CPU cpu; memset(&cpu, 0x5a, sizeof cpu);
                    cpu.r[{source}] = values[i];
                    CPU before = cpu;
                    {name}(&cpu);
                    if (cpu.r[{dest}] != expected[i]) {{
                        fprintf(stderr, "mulli {dest},{source},{imm}: input %08X got %08X expected %08X\\n",
                            (unsigned)values[i], (unsigned)cpu.r[{dest}], (unsigned)expected[i]);
                        return 1;
                    }}
                    before.r[{dest}] = expected[i];
                    if (memcmp(&cpu, &before, sizeof cpu)) {{
                        fprintf(stderr, "mulli altered other registers\\n"); return 1;
                    }}
                }}
            }}''')
    text = '\n'.join([
        '#include "recomp.h"', '#include <stdio.h>', *functions,
        'int main(void) {',
        'volatile uint32_t values[] = {' + ','.join(f'0x{v:08x}u' for v in values) + '};',
        'const unsigned count = sizeof values / sizeof values[0];', *cases,
        f'puts("mulli generated-code checks: {len(values) * len(functions)} passed");',
        'return 0; }',
    ])
    source = work / 'ppc_integer_test.c'
    executable = work / ('ppc_integer_test.exe' if sys.platform == 'win32' else 'ppc_integer_test')
    source.write_text(text, encoding='utf-8')
    subprocess.run([args.cc, '-std=c11', '-O2', '-ftrapv', '-Wall', '-Wextra',
                    '-Werror', '-I', str(runtime), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()
