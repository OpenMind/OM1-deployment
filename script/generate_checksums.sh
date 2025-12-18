#!/bin/bash

# Script to generate checksums for OTA deployment files
# Output format: JSON with service name, tag, S3 URL, file checksum, and Docker image SHA256

BASE_S3_URL="https://assets.openmind.org/ota"
OUTPUT_FILE="checksums.json"

get_deployment_dirs() {
    find . -maxdepth 1 -type d ! -name "." ! -name "script" ! -name ".git" ! -name ".github" | sed 's|^\./||' | sort
}

extract_image_name() {
    local yaml_file="$1"

    local image_line=$(grep -E "^\s*image:" "$yaml_file" | head -1)
    if [ -z "$image_line" ]; then
        echo "Warning: No image found in $yaml_file" >&2
        return 1
    fi

    local full_image=$(echo "$image_line" | sed 's/^[[:space:]]*image:[[:space:]]*//' | tr -d '"'"'"'')

    echo "$full_image"
}

get_docker_sha256() {
    local full_image="$1"

    # Hardcoded SHA256 for nvidia vllm image
    case "$full_image" in
        "nvcr.io/nvidia/vllm:25.09-py3")
            echo "15f380ad9c32f0ac57ac16e4b778c6f733c88b9ffe3a936035d0a59ad17b1aab"
            return 0
            ;;
    esac

    local image_repo=$(echo "$full_image" | cut -d':' -f1)
    local tag=$(echo "$full_image" | cut -d':' -f2)

    if [ "$image_repo" = "$tag" ]; then
        tag="latest"
    fi

    local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image_repo}:pull" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

    if [ -z "$token" ]; then
        echo "Error: Failed to get Docker registry token for ${image_repo}" >&2
        return 1
    fi

    local sha256=$(curl -s -I \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://registry.hub.docker.com/v2/${image_repo}/manifests/${tag}" \
        | grep -i "docker-content-digest" \
        | sed 's/.*sha256:\([a-f0-9]*\).*/\1/' \
        | tr -d '\r')

    if [ -z "$sha256" ]; then
        echo "Error: Failed to get SHA256 for ${image_repo}:${tag}" >&2
        return 1
    fi

    echo "$sha256"
}

deployment_dirs=$(get_deployment_dirs)

if [ -z "$deployment_dirs" ]; then
    echo "Error: No deployment directories found"
    exit 1
fi

echo "Found deployment directories: $deployment_dirs" >&2

temp_data="/tmp/services_data.txt"
> "$temp_data"

for dir in $deployment_dirs; do
    if [ -d "$dir" ]; then
        echo "Processing directory: $dir" >&2

        for file in "$dir"/*.yml; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                service_name="${filename%.yml}"

                checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)

                docker_image=$(extract_image_name "$file")

                if [ $? -eq 0 ] && [ -n "$docker_image" ]; then
                    echo "Found Docker image in ${dir}/${filename}: ${docker_image}" >&2

                    echo "Getting Docker SHA256 for ${docker_image}..." >&2
                    docker_sha256=$(get_docker_sha256 "$docker_image")

                    if [ $? -eq 0 ] && [ -n "$docker_sha256" ]; then
                        echo "Successfully got SHA256 for ${docker_image}: ${docker_sha256}" >&2
                    else
                        echo "Error: Failed to get Docker SHA256 for ${docker_image}" >&2
                        echo "Exiting script due to missing Docker SHA256" >&2
                        exit 1
                    fi
                else
                    echo "Error: Could not extract Docker image from ${dir}/${filename}" >&2
                    echo "Exiting script due to missing Docker image" >&2
                    exit 1
                fi

                echo "${service_name}|${dir}|${checksum}|${docker_image}|${docker_sha256}|${filename}" >> "$temp_data"
            fi
        done
    fi
done

echo "{" > "$OUTPUT_FILE"
echo "    \"om1\": {" >> "$OUTPUT_FILE"

unique_dirs=$(cut -d'|' -f2 "$temp_data" | sort -u)
dir_count=0
total_unique_dirs=$(echo "$unique_dirs" | wc -l | tr -d ' ')

for dir in $unique_dirs; do
    ((dir_count++))

    echo "        \"$dir\": {" >> "$OUTPUT_FILE"

    dir_entries=$(grep "|${dir}|" "$temp_data")
    entry_count=0
    total_entries=$(echo "$dir_entries" | wc -l | tr -d ' ')

    while IFS='|' read -r sname sdir checksum docker_image docker_sha256 filename; do
        ((entry_count++))

        echo "            \"$sname\": {" >> "$OUTPUT_FILE"
        echo "                \"tag\": \"$sdir\"," >> "$OUTPUT_FILE"
        echo "                \"s3_url\": \"$BASE_S3_URL/$sdir/$filename\"," >> "$OUTPUT_FILE"
        echo "                \"checksum\": \"$checksum\"," >> "$OUTPUT_FILE"
        echo "                \"image\": \"$docker_image\"," >> "$OUTPUT_FILE"
        echo "                \"image_sha256\": \"$docker_sha256\"" >> "$OUTPUT_FILE"

        if [ "$entry_count" -lt "$total_entries" ]; then
            echo "            }," >> "$OUTPUT_FILE"
        else
            echo "            }" >> "$OUTPUT_FILE"
        fi
    done <<< "$dir_entries"

    if [ "$dir_count" -lt "$total_unique_dirs" ]; then
        echo "        }," >> "$OUTPUT_FILE"
    else
        echo "        }" >> "$OUTPUT_FILE"
    fi
done

echo "    }" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

# Clean up temp file
rm -f "$temp_data"

echo "Checksums generated successfully in $OUTPUT_FILE" >&2
echo "Total unique services processed: $total_unique_services" >&2
echo "Deployment directories processed: $(echo $deployment_dirs | wc -w | tr -d ' ')" >&2
