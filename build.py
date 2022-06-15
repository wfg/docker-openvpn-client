#!/usr/bin/env python3

import argparse
import datetime
import subprocess


parser = argparse.ArgumentParser()
parser.add_argument('image_version', type=str)
args = parser.parse_args()

docker_build_cmd = [
    'docker', 'build',
    '--build-arg', f'BUILD_DATE={str(datetime.datetime.now())}',
    '--build-arg', f'IMAGE_VERSION={args.image_version}',
    '--tag', f'ghcr.io/wfg/openvpn-client:{args.image_version}',
    '--tag', 'ghcr.io/wfg/openvpn-client:latest',
    '.',
]
subprocess.run(docker_build_cmd)
