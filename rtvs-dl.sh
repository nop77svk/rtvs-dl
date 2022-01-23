#!/usr/bin/env bash

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
echo "Video title: ${full_title}"

# Download page and extract playlist
playlist=$(curl -s "${video_frame_url}" | grep -i //www.rtvs.sk/json/archive)
[ -n "${DEBUG:-}" ] && echo "Playlist: $playlist"

# Playlist to array
playlist_array=($playlist)

# Extract playlist link
playlist_link=$(echo 'https:'${playlist_array[3]} | sed 's/\"//g')
echo "Download playlist: $playlist_link"

# Extract line with link to stream
stream_tmp="$(curl -s $playlist_link)"
[ -n "${DEBUG:-}" ] && echo "{stream_tmp} = ${stream_tmp}"

stream_name=$(echo "${stream_tmp%x}" | grep "src\" :" | grep smil | head -1)
echo "Stream name: $stream_name"

stream_title=$(echo "${stream_tmp%x}" | grep "title")
[ -n "${DEBUG:-}" ] && echo "{stream_title} = ${stream_title}"

# Stream link name to array
stream_name_array=($stream_name)

# Extract link and remove quotes and commas
stream_link=$(echo "${stream_name_array[2]}" | sed 's/[\",]//g')
echo "Download stream link: $stream_link"

# Extract title
stream_title=$(echo "$stream_title" | cut -d ":" -f 2)
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

# the actual download
ffmpeg -i "${stream_link}" -c:a aac -map 0:a -c:v copy -map 0:v "${stream_title}.mp4"

# cleanup
if [ -z "${DEBUG:-}" ] ; then
	rm -f "${temp_file_prefix}.archive_page.html"
fi
