#!/bin/bash

# Script to generate checksums for OTA deployment files
# Output format: JSON with service name, tag, S3 URL, and checksum

LATEST_DIR="latest"
BASE_S3_URL="https://assets.openmind.org/ota/latest"
OUTPUT_FILE="checksums.json"

if [ ! -d "$LATEST_DIR" ]; then
    echo "Error: $LATEST_DIR directory not found"
    exit 1
fi

echo "{" > "$OUTPUT_FILE"

file_count=0
total_files=$(find "$LATEST_DIR" -name "*.yml" | wc -l | tr -d ' ')

for file in "$LATEST_DIR"/*.yml; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        service_name="${filename%.yml}"

        if [[ "$service_name" == "ota_updater.yml" ]]; then
            service_name="ota_updater"
            filename="ota_updater.yml"
        fi

        checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)

        ((file_count++))

        echo "    \"$service_name\": {" >> "$OUTPUT_FILE"
        echo "        \"latest\": {" >> "$OUTPUT_FILE"
        echo "            \"tag\": \"latest\"," >> "$OUTPUT_FILE"
        echo "            \"s3_url\": \"$BASE_S3_URL/$filename\"," >> "$OUTPUT_FILE"
        echo "            \"checksum\": \"$checksum\"" >> "$OUTPUT_FILE"
        echo "        }" >> "$OUTPUT_FILE"

        if [ "$file_count" -lt "$total_files" ]; then
            echo "    }," >> "$OUTPUT_FILE"
        else
            echo "    }" >> "$OUTPUT_FILE"
        fi
    fi
done

echo "}" >> "$OUTPUT_FILE"

echo "Checksums generated successfully in $OUTPUT_FILE"
echo "Total files processed: $file_count"
