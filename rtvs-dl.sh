#!/usr/bin/env bash

# ----------------------------------------------------------------------------

# If link is empty exit
[ -z "$1" ] && echo "Link is empty" && exit
echo "Download page: $1"

# some config
unique_token=${RANDOM}
temp_file_prefix=${TEMP}/rtvs-dl.${unique_token}

# RTVS archive page
curl -s "$1" > "${temp_file_prefix}.archive_page.html"

# extract the embedded video player URL
video_iframe_tag=$( grep -Ei '<iframe.*\s+class="player-iframe"' "${temp_file_prefix}.archive_page.html" )
[ -n "${DEBUG:-}" ] && echo "{video_iframe_tag} = ${video_iframe_tag}"

video_frame_url=$( echo "${video_iframe_tag}" | sed 's/^.*src="\([^"]*\)".*$/\1/g' )
echo "Video iframe URL: ${video_frame_url}"

# extract full stream title
full_title_tag=$( grep -Ei '<meta.*\s+property="og:title"' "${temp_file_prefix}.archive_page.html" )
[ -n "${DEBUG:-}" ] && echo "{full_title_tag} = ${full_title_tag}"

full_title=$( echo "${full_title_tag}" | sed 's/^.*content="\([^"]*\)".*$/\1/g' )
[ -n "${DEBUG:-}" ] && echo "{full_title} = ${full_title}"

# Download page and extract playlist
playlist=$(curl -s "${video_frame_url}" | grep -i //www.rtvs.sk/json/archive)
[ -n "${DEBUG:-}" ] && echo "{playlist} = $playlist"

# Playlist to array
playlist_array=($playlist)

# Extract playlist link
playlist_link=$(echo 'https:'${playlist_array[3]} | sed 's/\"//g')
[ -n "${DEBUG:-}" ] && echo "{playlist_link} = $playlist_link"

# Extract line with link to stream
stream_tmp="$(curl -s $playlist_link)"
[ -n "${DEBUG:-}" ] && echo "{stream_tmp} = ${stream_tmp}"

# ----------------------------------------------------------------------------

stream_title_node=$(echo "${stream_tmp%x}" | grep "title")
[ -n "${DEBUG:-}" ] && echo "{stream_title_node} = ${stream_title_node}"

# Extract title
stream_title=$(echo "${stream_title_node}" | cut -d ":" -f 2)
[ -n "${DEBUG:-}" ] && echo "{stream_title} = ${stream_title}"

# Remove ", from end
stream_title=$(echo "$stream_title" | sed 's/\",//g')
[ -n "${DEBUG:-}" ] && echo "{stream_title} = ${stream_title}"

# Reove quotes
stream_title=$(echo "$stream_title" | sed 's/\"//g')
[ -n "${DEBUG:-}" ] && echo "{stream_title} = ${stream_title}"

# Trim
stream_title=$(echo "$stream_title" | sed 's/^\s//g')
[ -n "${DEBUG:-}" ] && echo "{stream_title} = ${stream_title}"

stream_title=${full_title:-${stream_title}}
echo "Stream title: ${stream_title}"

# ----------------------------------------------------------------------------

stream_src_node=$(echo "${stream_tmp%x}" | grep "src\" :" | grep smil | head -1)
[ -n "${DEBUG:-}" ] && echo "{stream_src_node} = ${stream_src_node}"

# Stream link name to array
stream_src_node_array=(${stream_src_node})

# Extract link and remove quotes and commas
stream_link=$(echo "${stream_src_node_array[2]}" | sed 's/[\",]//g')
[ -n "${DEBUG:-}" ] && echo "{stream_link} = $stream_link"

track_choice=???
track_choice_opt=
track_resolution=???x???
track_resolution_opt=

if [[ "${stream_link}" =~ /playlist\.m3u8 ]] ; then
	url_base=$( echo "${stream_link}" | sed 's/^\(https\?:\/\/[^/]*\)\/.*$/\1/' )
	[ -n "${DEBUG:-}" ] && echo "{url_base} = ${url_base}"
	[ -n "${DEBUG:-}" ] && wget_log_output=/dev/stderr || wget_log_output=/dev/null

	highest_resolution=$(
		wget -O /dev/stdout -o ${wget_log_output} --no-cache "${stream_link}" \
			| tr '\r' '\n' \
			| grep -vE '^[[:space:]]*$' \
			| gawk -v "i_url_base=${url_base}" '
				BEGIN {
					o_fs = "\t";
					o_res_index = 0;
				}

				$0 ~ /^#EXT-X-STREAM-INF/ {
					match($0, /BANDWIDTH=([0-9]+)/, xx);
					bandwidth = xx[1];

					match($0, /RESOLUTION=([0-9]+x[0-9]+)/, xx);
					resolution = xx[1];

					nextline;
				}

				$0 ~ /^\// {
					o_res_index++;
					printf("%d	%s	%s	%s%s\n", o_res_index, bandwidth, resolution, i_url_base, $0);
				}
			' \
			| /bin/sort -b -n -r -k 2 \
			| head -n 1
	)

	highest_res_defs=( ${highest_resolution} )

	track_choice="${highest_res_defs[0]}"
	track_choice_opt=":"$(( track_choice - 1 ))

	track_resolution="${highest_res_defs[2]}"
	track_resolution_opt=" [${track_resolution}]"
fi

[ -n "${DEBUG:-}" ] && echo "{track_choice_opt} = ${track_choice_opt}"
[ -n "${DEBUG:-}" ] && echo "{track_resolution_opt} = ${track_resolution_opt}"

echo "Trying to download video stream #${track_choice}, resolution ${track_resolution:-???x???}"

if [[ "${stream_link}" =~ invalidtoken ]] ; then
	echo FATAL: RTVS web reported invalid token! Exiting!
	break
fi

# the actual download
if [ -z "${DEBUG:-}" ] ; then
	if ffmpeg -i "${stream_link}" -c:a copy -map 0:a${track_choice_opt} -c:v copy -map 0:v${track_choice_opt} "${stream_title}${track_resolution_opt}.mp4" ; then
		break
	fi
fi

# cleanup
if [ -z "${DEBUG:-}" ] ; then
	rm -f "${temp_file_prefix}.archive_page.html"
fi
