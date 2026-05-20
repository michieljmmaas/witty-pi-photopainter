# encoding: utf-8

import sys
import os
from pathlib import Path
from PIL import Image, ImageOps
import argparse

try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    pass

from rich.console import Console
from rich.progress import (
    Progress, SpinnerColumn, BarColumn, TextColumn,
    TimeElapsedColumn, MofNCompleteColumn,
)

console = Console()

SCRIPT_DIR = Path(__file__).parent
INPUT_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.bmp', '.heic', '.heif'}


def convert_image(input_path, mode='scale', direction=None, dither=Image.Dither.FLOYDSTEINBERG, set_status=None):
    def status(msg):
        if set_status:
            set_status(msg)

    status('reading')
    img = Image.open(input_path)
    width, height = img.size

    if direction:
        target_w, target_h = (800, 480) if direction == 'landscape' else (480, 800)
    else:
        target_w, target_h = (800, 480) if width > height else (480, 800)

    if mode == 'scale':
        status('scaling')
        ratio = max(target_w / width, target_h / height)
        rw, rh = int(width * ratio), int(height * ratio)
        resized = img.resize((rw, rh))
        canvas = Image.new('RGB', (target_w, target_h), (255, 255, 255))
        canvas.paste(resized, ((target_w - rw) // 2, (target_h - rh) // 2))
        result = canvas
    else:
        status('cropping')
        result = ImageOps.pad(img.crop((0, 0, width, height)), size=(target_w, target_h),
                              color=(255, 255, 255), centering=(0.5, 0.5))

    status('dithering')
    pal_image = Image.new('P', (1, 1))
    pal_image.putpalette((0,0,0, 255,255,255, 0,255,0, 0,0,255, 255,0,0, 255,255,0, 255,128,0) + (0,0,0)*249)
    quantized = result.quantize(dither=dither, palette=pal_image).convert('RGB')

    status('saving')
    output_path = Path(input_path).with_name(Path(input_path).stem + f'_{mode}_output.bmp')
    quantized.save(output_path)
    return output_path


def batch_process(mode, direction, dither):
    input_dir = SCRIPT_DIR / 'photos_input'
    output_dir = SCRIPT_DIR / 'my_photos'

    images = [f for f in sorted(input_dir.iterdir()) if f.suffix.lower() in INPUT_EXTENSIONS]

    if not images:
        console.print('[yellow]No images found in photos_input/[/yellow]')
        return

    console.print(f'\n[bold]Found {len(images)} image(s) in photos_input/[/bold]\n')

    processed = 0
    skipped = 0
    failed = 0

    with Progress(
        SpinnerColumn(),
        TextColumn('[bold cyan]{task.fields[filename]}[/bold cyan]'),
        TextColumn('[dim]{task.fields[step]}[/dim]'),
        BarColumn(bar_width=30),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        console=console,
    ) as progress:
        task = progress.add_task('', total=len(images), filename='—', step='')

        for img_path in images:
            dest = output_dir / (img_path.stem + '.bmp')
            progress.update(task, filename=img_path.name, step='')

            if dest.exists():
                progress.log(f'[yellow]⚠  skipped[/yellow]  {img_path.name} — already exists in my_photos/')
                progress.advance(task)
                skipped += 1
                continue

            try:
                output_bmp = convert_image(
                    img_path, mode=mode, direction=direction, dither=dither,
                    set_status=lambda msg: progress.update(task, step=msg),
                )
                progress.update(task, step='moving')
                output_bmp.rename(dest)
                img_path.unlink()
                progress.log(f'[green]✓  done[/green]      {img_path.name} → my_photos/{dest.name}')
                processed += 1
            except Exception as e:
                progress.log(f'[red]✗  error[/red]     {img_path.name}: {e}')
                failed += 1

            progress.advance(task)

    parts = []
    if processed:
        parts.append(f'[bold green]{processed} processed[/bold green]')
    if skipped:
        parts.append(f'[bold yellow]{skipped} skipped (duplicate)[/bold yellow]')
    if failed:
        parts.append(f'[bold red]{failed} failed[/bold red]')
    console.print('\n' + ', '.join(parts) + '.')


def main():
    parser = argparse.ArgumentParser(description='Convert images to 7-color e-ink BMP format.')
    parser.add_argument('image_file', nargs='?', help='Single input image (omit to batch-process photos_input/)')
    parser.add_argument('--dir', choices=['landscape', 'portrait'], help='Force orientation')
    parser.add_argument('--mode', choices=['scale', 'cut'], default='scale')
    parser.add_argument('--dither', type=int, choices=[Image.NONE, Image.FLOYDSTEINBERG],
                        default=Image.FLOYDSTEINBERG)

    args = parser.parse_args()
    dither = Image.Dither(args.dither)

    if args.image_file:
        if not os.path.isfile(args.image_file):
            console.print(f'[red]Error: file {args.image_file} does not exist[/red]')
            sys.exit(1)
        console.print(f'[bold]{args.image_file}[/bold]')
        output = convert_image(
            args.image_file, mode=args.mode, direction=args.dir, dither=dither,
            set_status=lambda msg: console.print(f'  [dim]{msg}...[/dim]'),
        )
        console.print(f'[green]✓[/green] Saved → {output}')
    else:
        batch_process(mode=args.mode, direction=args.dir, dither=dither)


if __name__ == '__main__':
    main()
