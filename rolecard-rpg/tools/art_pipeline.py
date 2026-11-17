"""Local, resumable art modules. No image API, network, installation or acceptance mutation."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
JOBS = ROOT / 'art-source/jobs'


def local(path):
    target = (ROOT / path).resolve()
    if not target.is_relative_to(ROOT):
        raise ValueError('job path outside project')
    return target


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def job_data(job_id):
    if not re.fullmatch(r'[a-z0-9-]+', job_id):
        raise ValueError('invalid job id')
    value = json.loads((JOBS / (job_id + '.json')).read_text('utf-8'))
    if value['schema_version'] != 1 or value['id'] != job_id:
        raise ValueError('job contract mismatch')
    return value


def validate_inputs(job):
    for source in job['source_inputs']:
        if digest(local(source['path'])) != source['sha256']:
            raise ValueError('input changed; create/review a new job: ' + source['path'])
    generated = job['image_generation']
    if digest(local(generated['output'])) != generated['output_sha256']:
        raise ValueError('candidate changed; existing analysis is not reusable')


def analyze(job):
    # Analysis only. All image transformations and exports remain in Aseprite.
    from PIL import Image
    image = Image.open(local(job['image_generation']['output'])).convert('RGBA')
    width, height = image.size
    pixels = image.get_flattened_data()
    mask = bytearray(1 if a >= 128 and not (b > 200 and r < 35 and g < 80) else 0
                     for r, g, b, a in pixels)
    found = []
    for start in range(width * height):
        if mask[start] != 1:
            continue
        mask[start] = 0
        stack = [start]
        count = 0
        left = right = start % width
        top = bottom = start // width
        while stack:
            index = stack.pop()
            x, y = index % width, index // width
            count += 1
            left, right, top, bottom = min(left, x), max(right, x), min(top, y), max(bottom, y)
            for neighbor in (index-1 if x else -1, index+1 if x < width-1 else -1,
                             index-width if y else -1, index+width if y < height-1 else -1):
                if neighbor >= 0 and mask[neighbor] == 1:
                    mask[neighbor] = 0
                    stack.append(neighbor)
        if count >= job['analysis']['minimum_component_pixels']:
            found.append({'pixels': count, 'bounds': [left, top, right+1, bottom+1]})
    columns, rows = job['analysis']['grid']
    if len(found) != columns * rows:
        raise ValueError('expected complete separate silhouettes; manual review required')
    found.sort(key=lambda item: (int(item['bounds'][1] / (height/rows)), item['bounds'][0]))
    target = local(job['analysis']['components'])
    target.write_text(json.dumps(found, indent=2) + '\n', 'utf-8')
    return {'module': 'M2-analysis', 'components': len(found), 'output': str(target)}


def run_local(command):
    kwargs = {'cwd': ROOT}
    if os.name == 'nt':
        kwargs['creationflags'] = subprocess.CREATE_NO_WINDOW
    subprocess.run(command, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module', choices=['status', 'profile', 'prompt', 'analyze', 'build', 'check'])
    parser.add_argument('--job', default='rin-motion-05')
    parser.add_argument('--actor', default=None)
    args = parser.parse_args()
    if args.module == 'status':
        print(json.dumps({'job': args.job, 'retired': True, 'reason': '用户2026-10-28废弃旧连续动画路线', 'next_module': '五关键帧→外部视频→video_assets.py；工程重点游戏机制', 'contract': 'docs/video-art-strategy.md'}, ensure_ascii=False, indent=2))
        return
    if args.module in ['build', 'analyze']:
        raise ValueError('2026-10-28旧连续动画路线已废弃；改用五关键帧→外部视频→video_assets.py，历史文件仅供追踪')
    job = job_data(args.job)
    if args.module == 'profile':
        profiles = json.loads((ROOT / 'art-source/personality-profiles.json').read_text('utf-8'))
        print(json.dumps(profiles['profiles'][args.actor or job['actor_id']], ensure_ascii=False, indent=2))
        return
    if args.module == 'prompt':
        print(local(job['image_generation']['exact_prompt_file']).read_text('utf-8'))
        print('\n[receipt] Provider: built-in image_gen; calls_used:', job['image_generation']['calls_used'])
        print('[receipt] Existing prompt is historical; personality requirement added later:', job['image_generation']['personality_requirement_added_after_call'])
        return
    validate_inputs(job)
    if args.module == 'analyze':
        result = analyze(job)
    elif args.module == 'build':
        target = local(job['aseprite']['source'])
        if not target.name.endswith('.generated.aseprite'):
            raise ValueError('automatic build cannot overwrite hand-finished source')
        shell = shutil.which('pwsh') or shutil.which('powershell')
        if not shell:
            raise ValueError('PowerShell not found; no automatic install')
        run_local([shell, '-NoProfile', '-File', str(local(job['aseprite']['wrapper']))])
        result = {'module': 'M3-Aseprite', 'source': str(target), 'acceptance': 'unchanged-unapproved'}
    elif args.module == 'check':
        run_local([sys.executable, str(local(job['check']['script']))])
        result = {'module': 'M4-structure', 'visual_findings': job['visual_findings'], 'activation': job['activation']}
    else:
        result = {'job': job['id'], 'inputs_unchanged': True,
                  'image_calls_used': job['image_generation']['calls_used'],
                  'prompt': job['image_generation']['exact_prompt_file'],
                  'source_exists': local(job['aseprite']['source']).is_file(),
                  'outputs_exist': all(local(job['aseprite'][key]).is_file() for key in ['runtime_sheet', 'runtime_metadata']),
                  'activation': job['activation'], 'visual_findings': job['visual_findings'],
                  'next_module': 'M4-motion/personality-review; attack requires refinement, not another whole-grid generation'}
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print('ART MODULE STOPPED: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
