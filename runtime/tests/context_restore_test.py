"""Exercise the runtime's actual context restore with a synthetic SDK memory layout.

The context contains full binary64 PS0 values in its FPR array, and packed
binary32 PS0/PS1 pairs in its paired-single array. No disc or game code is used.
The MIT runtime helper is extracted so this focused test needs no SDL or guest.
"""
import argparse
import pathlib
import struct
import subprocess
import sys


def extract_helper(text):
    start = text.index('static void context_to_cpu(')
    brace = text.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
        end += 1
    return text[start:end]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cc', required=True)
    ap.add_argument('--work', required=True)
    args = ap.parse_args()
    runtime = pathlib.Path(__file__).resolve().parents[1] / 'runtime'
    work = pathlib.Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    helper = extract_helper((runtime / 'threads.cpp').read_text())
    patterns = [0xc0200000, 0x80000000, 0x00000000, 0x3fa00000,
                0x00800000, 0x00000001, 0x80800000, 0x7f800000,
                0xff800000, 0x3f800001, 0xbf800001, 0x7f7fffff]
    lane_bits = [patterns[i % len(patterns)] for i in range(32)]
    double_bits = [struct.unpack('>Q', struct.pack('>d', struct.unpack('>f', struct.pack('>I', bits))[0]))[0]
                   for bits in lane_bits]
    first_bits = [struct.unpack('>Q', struct.pack('>d', (-1 if i & 1 else 1) * (1234.125 + i)))[0]
                  for i in range(32)]
    arrays = ('static const uint32_t paired_second[32] = {' + ','.join(f'0x{v:08x}u' for v in lane_bits) + '};\n'
              'static const uint64_t expected_second[32] = {' + ','.join(f'0x{v:016x}ull' for v in double_bits) + '};\n'
              'static const uint64_t full_first[32] = {' + ','.join(f'0x{v:016x}ull' for v in first_bits) + '};\n')
    source = r'''
#include "recomp.h"
#include <stdio.h>
#include <stdlib.h>
enum { CTX_GPR=0, CTX_CR=0x80, CTX_LR=0x84, CTX_CTR=0x88,
       CTX_XER=0x8c, CTX_FPR=0x90, CTX_FPSCR=0x194,
       CTX_SRR1=0x19c, CTX_GQR=0x1a4, CTX_PSF=0x1c8 };
static unsigned char memory[0x400];
static uint32_t mem_r32(uint32_t ea) {
    const uint32_t off=ea-0x80000000u;
    if (off > sizeof memory-4) abort();
    return ((uint32_t)memory[off]<<24)|((uint32_t)memory[off+1]<<16)|
           ((uint32_t)memory[off+2]<<8)|memory[off+3];
}
static void put(uint32_t off,uint32_t v) {
    if (off > sizeof memory-4) abort();
    memory[off]=(uint8_t)(v>>24); memory[off+1]=(uint8_t)(v>>16);
    memory[off+2]=(uint8_t)(v>>8); memory[off+3]=(uint8_t)v;
}
HELPER
ARRAYS
int main(void) {
    CPU c; memset(&c,0x5a,sizeof c);
    c.fprf_pending=2; c.fprf_v=NAN;
    for(unsigned i=0;i<32;++i) {
        put(CTX_GPR+4*i,0x12340000u+i);
        put(CTX_FPR+8*i,(uint32_t)(full_first[i]>>32));
        put(CTX_FPR+8*i+4,(uint32_t)full_first[i]);
        // Deliberately differ from the full PS0: restoring it from here would
        // destroy its binary64 precision. Only the low word supplies PS1.
        put(CTX_PSF+8*i,0x3e000000u+i*0x10000u);
        put(CTX_PSF+8*i+4,paired_second[i]);
    }
    for(unsigned i=0;i<8;++i)put(CTX_GQR+4*i,0x00040004u+i);
    put(CTX_CR,0x12345678u);put(CTX_LR,0x80001234u);put(CTX_CTR,0x80005678u);
    put(CTX_XER,0xe0000000u);put(CTX_SRR1,0x00003032u);put(CTX_FPSCR,0xa5a11004u);
    context_to_cpu(&c,0x80000000u);
    for(unsigned i=0;i<32;++i) {
        uint64_t got_second;memcpy(&got_second,&c.ps1[i],sizeof got_second);
        if(c.f[i].u!=full_first[i] || got_second!=expected_second[i]) {
            fprintf(stderr,"FPR%u: PS0=%016llX expected%016llX PS1=%016llX expected%016llX\n",i,
                    (unsigned long long)c.f[i].u,(unsigned long long)full_first[i],
                    (unsigned long long)got_second,(unsigned long long)expected_second[i]);return 1;
        }
        if(c.r[i]!=0x12340000u+i)return 1;
    }
    for(unsigned i=0;i<8;++i)if(c.gqr[i]!=0x00040004u+i)return 1;
    if(cpu_get_cr(&c)!=0x12345678u || c.lr!=0x80001234u || c.ctr!=0x80005678u ||
       c.msr!=0x00003032u || c.xer_ca!=1 || c.xer_so!=1 || c.xer_ov!=1 ||
       c.fpscr!=0xa5a11004u || c.fprf_pending!=0 || FPSCR_READ(&c)!=0xa5a11004u)return 1;
    puts("context restore: 32 full PS0 + 32 packed PS1 values and control state passed");
    return 0;
}
'''.replace('HELPER', helper).replace('ARRAYS', arrays)
    cfile = work / 'context_restore_test.c'
    cfile.write_text(source, encoding='utf-8')
    exe = work / ('context_restore_test.exe' if sys.platform == 'win32' else 'context_restore_test')
    command = [args.cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I', str(runtime), str(cfile), '-o', str(exe)]
    if sys.platform != 'win32':
        command += ['-lm']
    subprocess.run(command, check=True)
    subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
