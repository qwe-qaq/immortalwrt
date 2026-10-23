#!/usr/bin/env python3
"""Build a signed, non-initramfs FIT for the existing TYFZA1 UBI slots.

Self-contained port of the PonWRT-TYFZA1 build helper: the compression
contract, boot script and dual-configuration ITS reproduce the OEM UBI FIT
ABI (kernel + both board DTs + shared script, conf-0 = 2.5G board,
conf-1 = four-GbE board).
"""
import argparse
import json
import lzma
import os
import shutil
import subprocess
import sys
from pathlib import Path


def compress(data, parameters):
    return lzma.compress(data, format=lzma.FORMAT_ALONE, filters=[{
        'id': lzma.FILTER_LZMA1, 'dict_size': parameters['dictionary_bytes'],
        'lc': parameters['lc'], 'lp': parameters['lp'], 'pb': parameters['pb'],
    }])


def board_boot_command():
    # OEM b1/b2 hand off b_conf; older 2.5G loaders use the FIT default.
    # Direct RAM boots may not have run the OEM selector yet.
    return '''if test -z "${b_conf}" && test -n "${conf_match}"; then
    run conf_match
fi
if test -n "${b_conf}"; then
    bootm ${unzip_src}#${b_conf}
else
    bootm ${unzip_src}
fi
'''


def make_its(load, entry, fdt_load, kernel_version, signed=False, board_variants=False):
    signature = ('signature { algo = "sha256,rsa2048"; key-name-hint = "dev"; };'
                 if signed else '')
    config_signature = ('signature { algo = "sha256,rsa2048"; key-name-hint = "dev"; '
                        'sign-images = "fdt", "kernel", "script"; };' if signed else '')
    label = 'SIGNED' if signed else 'UNSIGNED'
    its = f'''/dts-v1/;
/ {{
    description = "TYFZA1 native {label} boot-contract candidate";
    #address-cells = <1>;
    images {{
        kernel {{
            description = "Native Linux {kernel_version}";
            data = /incbin/("kernel.lzma");
            type = "kernel"; arch = "arm64"; os = "linux";
            compression = "lzma"; load = <{load:#x}>; entry = <{entry:#x}>;
            hash {{ algo = "sha256"; }};
            {signature}
        }};
        fdt-dts {{
            data = /incbin/("fdt.lzma");
            type = "flat_dt"; arch = "arm64";
            compression = "lzma"; load = <{fdt_load:#x}>;
            hash {{ algo = "sha256"; }};
            {signature}
        }};
        script {{
            data = /incbin/("boot.cmd");
            type = "script"; compression = "none";
            hash {{ algo = "sha256"; }};
            {signature}
        }};
    }};
    configurations {{
        default = "conf-dts";
        conf-dts {{ compatible = "realtek,taurus"; kernel = "kernel"; fdt = "fdt-dts"; script = "script"; {config_signature} }};
    }};
}};
'''
    if board_variants:
        fdt = f'''        fdt-2p5g {{
            data = /incbin/("fdt-2p5g.lzma");
            type = "flat_dt"; arch = "arm64";
            compression = "lzma"; load = <{fdt_load:#x}>;
            hash {{ algo = "sha256"; }};
            {signature}
        }}
'''
        its = its.replace('        script {', fdt + '        script {')
        its = its.replace('default = "conf-dts";', 'default = "conf-0";')
        its = its.replace('        conf-dts {',
                          '        conf-0 { compatible = "realtek,taurus"; kernel = "kernel"; '
                          'fdt = "fdt-2p5g"; script = "script"; ' + config_signature + ' };\n'
                          '        conf-1 {')
    return its


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('dtb', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--keys', type=Path, required=True)
    parser.add_argument('--dtb-2p5g', type=Path, required=True)
    parser.add_argument('--mkimage', default=os.environ.get('TYFZA1_MKIMAGE', 'mkimage'))
    parser.add_argument('--kernel-version', default='unknown')
    args = parser.parse_args()

    mkimage = shutil.which(args.mkimage) or args.mkimage
    if shutil.which(mkimage) is None and not Path(mkimage).is_file():
        sys.exit(f'mkimage not found: {args.mkimage} (build a crypto-enabled host mkimage '
                 'with scripts/tyfza1/build-fit-tools.sh)')

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    contract = json.loads((Path(__file__).parent / 'tyfza1-fit-compression.json').read_text())
    parameters = {item['name']: item['lzma_alone'] for item in contract['images']
                  if item['name'] in ('kernel', 'fdt-dts')}
    (out / 'kernel.lzma').write_bytes(compress(args.image.read_bytes(), parameters['kernel']))
    (out / 'fdt.lzma').write_bytes(compress(args.dtb.read_bytes(), parameters['fdt-dts']))
    (out / 'fdt-2p5g.lzma').write_bytes(compress(args.dtb_2p5g.read_bytes(), parameters['fdt-dts']))
    (out / 'boot.cmd').write_text('''if test "${root_mtd}" = "31:12"; then
    setenv tyfza1_slot 1
    setenv tyfza1_root ubi_r1
    setenv tyfza1_block /dev/ubiblock0_7
else
    setenv tyfza1_slot 0
    setenv tyfza1_root ubi_r0
    setenv tyfza1_block /dev/ubiblock0_4
fi
setenv bootargs "earlycon console=ttyS0,115200n8 clk_ignore_unused maxcpus=4 ubi.mtd=ubi_device ubi.block=0,${tyfza1_root} root=${tyfza1_block} rootfstype=squashfs ro tyfza1.slot=${tyfza1_slot}"
''' + board_boot_command())
    (out / 'image.its').write_text(make_its(0x200000, 0x200000, 0x2000000,
                                           args.kernel_version,
                                           signed=True, board_variants=True))
    subprocess.run([mkimage, '-f', 'image.its', '-k', str(args.keys.resolve()), 'image.itb'],
                   cwd=out, check=True, stdout=subprocess.DEVNULL)
    fdtget = shutil.which('fdtget')
    if fdtget:
        for node in ('/images/kernel/signature', '/images/fdt-dts/signature',
                     '/images/fdt-2p5g/signature', '/images/script/signature',
                     '/configurations/conf-0/signature', '/configurations/conf-1/signature'):
            subprocess.run([fdtget, '-t', 'bx', 'image.itb', node, 'value'],
                           cwd=out, check=True, stdout=subprocess.DEVNULL)
    else:
        print('warning: fdtget not found; skipped FIT signature node check', file=sys.stderr)
    size = (out / 'image.itb').stat().st_size
    if size > 0x600000:
        raise ValueError(f'FIT is {size} bytes; stock U-Boot reads at most 0x600000')
    print(f'UBI kernel FIT: {size} bytes; existing kernel volumes and root volume IDs retained')


if __name__ == '__main__':
    main()
