"""Generate original synthetic media; no external films or account data."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
fixtures = root / 'Fixtures'
fixtures.mkdir(exist_ok=True)
manifest = []
for name, pixels, profile, audio in [('hevc8', 'yuv420p', 'main', 'eac3'), ('hevc10', 'yuv420p10le', 'main10', 'aac')]:
    output = fixtures / f'{name}.mkv'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc2=size=3840x1632:rate=25:duration=12',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=12',
        '-vf', f'format={pixels}', '-c:v', 'libx265', '-preset', 'ultrafast',
        '-profile:v', profile, '-crf', '28', '-x265-params', 'pools=2:frame-threads=2:log-level=error:keyint=25',
        '-c:a', audio, '-ac', '2', '-b:a', '192k', '-shortest', str(output)], check=True)
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(output)]))
    stream = next(s for s in probe['streams'] if s['codec_type'] == 'video')
    assert stream['codec_name'] == 'hevc' and stream['width'] == 3840 and stream['height'] == 1632
    assert stream['profile'] == {'main': 'Main', 'main10': 'Main 10'}[profile]
    manifest.append({'name': output.name, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'probe': probe})
(root / 'fixtures.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps([{'file': m['name'], 'sha256': m['sha256']} for m in manifest]))
