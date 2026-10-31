#!/bin/bash
# Composes the promo videos from the last take (build/promo/raw.mov and events.json): the recording scaled to
# 1920 × 1080 at a constant 30 fps, held on its last frame, with the rendered overlay track on top.
#
#   build/promo/pasteup-appstore.mp4  App Store preview: H.264 High@4.0 at a constant 11 Mbps (Apple asks for
#                                     10–12; a screen recording would come out far lower), silent stereo AAC 256 kbps.
#   build/promo/pasteup-web.mp4       Web page: the same with the GitHub URL on the end card, no audio track.
#   docs/demo.gif                     README animation: the take without the end card.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
promo="$root/build/promo"
ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

if [ ! -x "$promo/render" ] || [ "$root/Promo/render.swift" -nt "$promo/render" ]; then
	swiftc -swift-version 5 -O "$root/Promo/render.swift" -o "$promo/render"
fi
"$ictool" "$root/Pasteup/AppIcon.icon" --export-image --output-file "$promo/icon.png" \
	--platform macOS --rendition Default --width 512 --height 512 --scale 1 >/dev/null

done_time="$(jq '.events[] | select(.kind == "done") | .time' "$promo/events.json")"

compose() {
	local variant="$1" output="$2"
	shift 2
	"$promo/render" "$promo/events.json" "$promo/icon.png" "$variant" "$promo/overlay-$variant.mov"
	# ScreenCaptureKit writes frames only when the screen changes, so the static end needs the last frame held.
	ffmpeg -y -v error -i "$promo/raw.mov" -i "$promo/overlay-$variant.mov" "$@" \
		-filter_complex "[0:v]fps=30,scale=1920:1080:flags=lanczos,tpad=stop_mode=clone:stop_duration=10,setsar=1[base];[base][1:v]overlay=0:0:shortest=1,format=yuv420p[video]" \
		-map "[video]" -r 30 -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
		-movflags +faststart "$output"
}

compose appstore "$promo/pasteup-appstore.mp4" \
	-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 -map 2:a -shortest \
	-c:v libx264 -profile:v high -level:v 4.0 -preset slow -b:v 11M -minrate 11M -maxrate 11M -bufsize 11M \
	-x264-params nal-hrd=cbr -g 60 \
	-c:a aac_at -aac_at_mode cbr -b:a 256k -ar 48000 -ac 2

compose web "$promo/pasteup-web.mp4" \
	-c:v libx264 -profile:v high -preset slow -crf 20 -an

ffmpeg -y -v error -t "$done_time" -i "$promo/pasteup-web.mp4" \
	-filter_complex "fps=12,scale=800:-1:flags=lanczos,split[frames][copy];[copy]palettegen=stats_mode=diff[palette];[frames][palette]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
	"$root/docs/demo.gif"

for output in "$promo/pasteup-appstore.mp4" "$promo/pasteup-web.mp4" "$root/docs/demo.gif"; do
	printf '%s: %s\n' "$(basename "$output")" "$(du -h "$output" | cut -f1)"
done
