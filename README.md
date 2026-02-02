# OM1 deployment

This repository contains Docker Compose configurations for deploying the OM1 robot system.

## Instructions

For a fresh Thor (JetPack 7.0) system, follow these steps to set up OM1:

### Basic Setup

#### uv

Use `curl` to download and install `uv`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

#### Docker

The docker is pre-installed on JetPack 7.0 systems, but you need to give it proper permissions:

```bash
newgrp docker
sudo usermod -aG docker $USER
groups
```

You should see `docker` in the list of groups. If not, log out and log back in, then check again.

#### Docker Compose

Download and install Docker Compose with the following commands:

```
sudo curl -L "https://github.com/docker/compose/releases/download/v2.34.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
```

Set the executable permissions:

```
sudo chmod +x /usr/local/bin/docker-compose
```

Verify the installation:

```
docker-compose --version
```

#### Poetry (Optional)

Install Poetry using the official installation script:

```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Install `poetry shell` for the environment management:

```bash
poetry self add poetry-plugin-shell
```

#### Pyaudio (For microphone support)

Install the required packages:

```bash
sudo apt install portaudio19-dev python3-pyaudio
```

#### FFmpeg (For audio processing)

Install FFmpeg using the following command:

```bash
sudo apt install ffmpeg
```

#### Chrome (For web interface)

Download and install Google Chrome:

```bash
sudo snap install chromium
```

Hold snap updates to prevent automatic updates:

```bash
snap download snapd --revision=24724
sudo snap ack snapd_24724.assert
sudo snap install snapd_24724.snap
sudo snap refresh --hold snapd
```

#### ROS2 (Optional)

Follow the official ROS2 installation guide for Ubuntu: [ROS2 Installation](https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html).

After installing ROS2, source the ROS2 setup script:

```bash
source /opt/ros/jazzy/setup.bash
```

You can add this line to your `~/.bashrc` file to source it automatically on terminal startup.

#### CycloneDDS Binary (Optional)

Install CycloneDDS for ROS2 communication:

```bash
sudo apt install ros-jazzy-rmw-cyclonedds-cpp
sudo apt install ros-jazzy-rosidl-generator-dds-idl
```

Now, set CycloneDDS as the default RMW implementation by adding the following line to your `~/.bashrc` file:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
```

You can restart your ROS2 daemon with the following command:

```bash
ros2 daemon stop
ros2 daemon start
```

#### CycloneDDS Build from Source (Optional)

If you prefer to build CycloneDDS from source, use the following commands:

```
git clone https://github.com/eclipse-cyclonedds/cyclonedds -b releases/0.10.x
cd cyclonedds && mkdir build install && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=../install -DBUILD_EXAMPLES=ON
cmake --build . --target install
```
Then you need to set the following environment variables in your `~/.bashrc` file:

```bash
export CYCLONEDDS_HOME=$HOME/Documents/GitHub/cyclonedds/install
```

#### Configure Network Settings (Unitree Only)

You need to open the network settings and find the network interface that the robot connected. In IPv4 settings, set the method to `Manual` and add the following IP address:

```
192.168.123.xxx
```

and set the subnet mask to

```
255.255.255.0
```

#### CycloneDDS Configuration (Optional)

You can create a CycloneDDS configuration file to customize its behavior. Create a file named `cyclonedds.xml` in your home directory:

```xml
<CycloneDDS>
  <Domain>
    <General>
      <Interfaces>
        <NetworkInterface name="enP2p1s0" priority="default" multicast="default" />
      </Interfaces>
    </General>
    <Discovery>
      <EnableTopicDiscoveryEndpoints>true</EnableTopicDiscoveryEndpoints>
    </Discovery>
  </Domain>
</CycloneDDS>
```

Then, set the `CYCLONEDDS_URI` environment variable in your `~/.bashrc` file:

```bash
export CYCLONEDDS_URI=file://$HOME/cyclonedds.xml
```

#### v4l2-ctl (For camera configuration)

Install `v4l2-ctl` using the following command:

```bash
sudo apt install v4l-utils
```

### System Services

We assume you have bought the [brain pack](https://openmind.org/store). If you don't have it, you can skip this section based on your needs.

#### Screen Animation Service

To enable the screen animation service, install `unclutter` first to hide the mouse cursor:

```bash
sudo apt install unclutter
```

Then, add the script to `/usr/local/bin/start-kiosk.sh` and make it executable:

```bash
#!/bin/bash

unclutter -display :0 -idle 0.1 -root &

HOST=localhost
PORT=4173

# Wait for Docker service to listen
while ! nc -z $HOST $PORT; do
  echo "Waiting for $HOST:$PORT..."
  sleep 0.1
done

# Launch with autoplay permissions
exec chromium \
  --kiosk http://$HOST:$PORT \
  --disable-infobars \
  --noerrdialogs \
  --autoplay-policy=no-user-gesture-required \
  --disable-features=PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/start-kiosk.sh
```

Add the script to `/etc/systemd/system/kiosk.service` to launch the kiosk mode automatically on boot.

```
# /etc/systemd/system/kiosk.service
[Unit]
Description=Kiosk Browser
After=docker.service
Requires=docker.service

[Service]
Environment=DISPLAY=:0
ExecStart=/usr/local/bin/start-kiosk.sh
Restart=always
User=openmind

[Install]
WantedBy=graphical.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kiosk.service
sudo systemctl start kiosk.service
```

> [!NOTE]
> To stop the kiosk service, use `sudo systemctl stop kiosk.service`.

#### AEC Service

To enable the Acoustic Echo Cancellation (AEC) service, uninstall `PipWire` if it's installed and install `PulseAudio`

```bash
sudo apt remove --purge pipewire-audio-client-libraries pipewire-pulse wireplumber
```

Then install `PulseAudio`:

```bash
sudo apt install pulseaudio pulseaudio-module-bluetooth pulseaudio-utils pavucontrol
```

Next, stop the `PipWire` daemon and start the `PulseAudio` daemon if it's not already running:

```bash
systemctl --user mask pipewire.service
systemctl --user mask pipewire.socket
systemctl --user mask pipewire-pulse.service
systemctl --user mask pipewire-pulse.socket
systemctl --user mask wireplumber.service
systemctl --user stop pipewire-pulse.service
systemctl --user stop pipewire.service wireplumber.service
systemctl --user disable pipewire.service wireplumber.service
systemctl --user enable --now pulseaudio.service
```

Next, add the script to prevent `PulseAudio` from going into `auto-exit` mode.

```bash
mkdir -p ~/.config/pulse
cat > ~/.config/pulse/client.conf << 'EOF'
autospawn = yes
daemon-binary = /usr/bin/pulseaudio
EOF

# Create daemon config to disable idle timeout
cat > ~/.config/pulse/daemon.conf << 'EOF'
exit-idle-time = -1
EOF
```

Now, you can restart the system to ensure `PulseAudio` is running properly.

```bash
sudo reboot
```

> [!NOTE]
> After reboot, if the audio devices are not automatically detected, you may need to manually start `PulseAudio` with the command:
> ```bash
> systemctl --user restart pulseaudio
> ```

Now, you can add the script to `/usr/local/bin/set-audio-defaults.sh` and make it executable:

```bash
#!/bin/bash
set -e

sleep 5

# First, set the master source volume to 200%
pactl set-source-volume "alsa_input.usb-R__DE_R__DE_VideoMic_GO_II_FEB0C614-00.mono-fallback" 131072
pactl set-source-mute "alsa_input.usb-R__DE_R__DE_VideoMic_GO_II_FEB0C614-00.mono-fallback" 0

# Unload then load AEC module
pactl unload-module module-echo-cancel || true
pactl load-module module-echo-cancel \
  use_master_format=1 \
  aec_method=webrtc \
  source_master="alsa_input.usb-R__DE_R__DE_VideoMic_GO_II_FEB0C614-00.mono-fallback" \
  sink_master="alsa_output.platform-88090b0000.hda.hdmi-stereo" \
  source_name="default_mic_aec" \
  sink_name="default_output_aec" \
  source_properties="device.description=Microphone_with_AEC" \
  sink_properties="device.description=Speaker_with_AEC"

# Wait a moment for the module to fully initialize
sleep 2

# Set defaults
pactl set-default-source default_mic_aec
pactl set-default-sink default_output_aec

# Retry volume setting until device appears and volume is set correctly
for i in {1..15}; do
  if pactl list short sources | grep -q default_mic_aec; then
    # Set volume to 200% (131072)
    pactl set-source-volume default_mic_aec 131072
    pactl set-source-mute default_mic_aec 0

    # Verify the volume was set
    CURRENT_VOL=$(pactl list sources | grep -A 7 "Name: default_mic_aec" | grep "Volume:" | awk '{print $3}')

    if [ "$CURRENT_VOL" = "131072" ]; then
      echo "Microphone volume successfully set to 200%"
      break
    else
      echo "Volume is $CURRENT_VOL, retrying... ($i/15)"
    fi
  else
    echo "Waiting for AEC source to appear... ($i/15)"
  fi
  sleep 1
done

# Final verification
pactl list sources | grep -A 7 "Name: default_mic_aec" | grep -E "Name:|Volume:"
```

Use the following command to get the list of audio sources and sinks:

```bash
pactl list short
```

> [!NOTE]
> Replace `alsa_output.platform-88090b0000.hda.hdmi-stereo` with your speaker source and   `alsa_input.usb-R__DE_R__DE_VideoMic_GO_II_FEB0C614-00.mono-fallback` with mic source


Make it executable:

```bash
sudo chmod +x /usr/local/bin/set-audio-defaults.sh
```

Create a systemd user service to run the script on login:

```bash
mkdir -p ~/.config/systemd/user
sudo vim ~/.config/systemd/user/audio-defaults.service
```

Add the following content:

```
[Unit]
Description=Set Default Audio Devices
After=pulseaudio.service
Wants=pulseaudio.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/set-audio-defaults.sh

[Install]
WantedBy=default.target
```

Enable and start the service:

```bash
systemctl --user daemon-reload
systemctl --user enable audio-defaults.service
systemctl --user start audio-defaults.service
```

### Enable Cloud Docker Management Service

The cloud docker management service allows remote management of Docker containers via a web interface. To enable this service, follow these steps:

1. Sign up for an account on [OpenMind Portal](https://portal.openmind.org).

2. Create your OpenMind API key from the [Dashboard](https://portal.openmind.org) page.

3. Set the API key as an environment variable in your `Bash` profile:

```bash
vim ~/.bashrc

export OM_API_KEY="your_api_key_here"
```

4. Get the API Key ID from the [Dashboard](https://portal.openmind.org) page. The API Key ID is a 16-digit character string, such as `om1_live_<16 characters>`. Now, export the API Key ID as an environment variable:

```bash
vim ~/.bashrc

export OM_API_KEY_ID="your_api_key_id_here"
```

Now, reload your `Bash` profile to apply the changes:

```bash
source ~/.bashrc
```

#### Setup OTA Update Services

To enable the Over-The-Air (OTA) update service for Docker containers, you need to set up two docker services: `ota_agent` and `ota_updater`. These services will allow you to manage and update your Docker containers remotely via the [OpenMind Portal](https://portal.openmind.org).

To create a `ota_upater.yml` file, follow these steps:

```bash
cd ~

vim ota_updater.yml
```

Add the following content from this [ota_upater.yml](https://github.com/OpenMind/OM1-deployment/blob/main/latest/ota_updater.yml) to the `ota_updater.yml` file.

>[!NOTE]
> You can use the stable version as well. The file example provided on the top is the latest version.

Save and close the file. Now, you can start the OTA updater service using Docker Compose:

```bash
docker-compose -f ota_updater.yml up -d
```

A `.ota` directory will be created in your home directory to store the OTA configuration files.

Now, you can set up the `ota_agent` service. Create an `ota_agent.yml` file:

```bash
cd .ota

vim ota_agent.yml
```

Add the following content from this [ota_agent.yml](https://github.com/OpenMind/OM1-deployment/blob/main/latest/ota_agent.yml) to the `ota_agent.yml` file.

>[!NOTE]
> You can use the stable version as well. The file example provided on the top is the latest version.

Save and close the file. Now, you can start the OTA agent service using Docker Compose:

```bash
docker-compose -f ota_agent.yml up -d
```

Now, both the OTA updater and agent services should be running. You can verify their status using the following commands:

```bash
docker ps | grep ota_updater
docker ps | grep ota_agent
```

You can now manage and update your Docker containers remotely via the [OpenMind Portal](https://portal.openmind.org).

### Model Downloads

#### Riva Models

Riva models are encrypted and require authentication to download. To download Riva models, you need to set up the NVIDIA NGC CLI tool.

##### Install NGC CLI

> [!WARNING]
> Please run the following command in your **root** directory. Otherwise, the `docker-compose` file we provide for `Riva` services may not work properly.

To generate your own NGC api key, check this [video](https://www.youtube.com/watch?v=yBNt4qSnn0k).

```
wget --content-disposition https://ngc.nvidia.com/downloads/ngccli_arm64.zip && unzip ngccli_arm64.zip && chmod u+x ngc-cli/ngc
find ngc-cli/ -type f -exec md5sum {} + | LC_ALL=C sort | md5sum -c ngc-cli.md5
echo export PATH=\"\$PATH:$(pwd)/ngc-cli\" >> ~/.bash_profile
source ~/.bash_profile
ngc config set
```

This will ask several questions during the install. Choose these values:

```
Enter API key [no-apikey]. Choices: [<VALID_APIKEY>, 'no-apikey']: <YOUR_API_KEY>
Enter CLI output format type [ascii]. Choices: ['ascii', 'csv', 'json']: ascii
Enter org [no-org]. Choices: ['<YOUR_ORG>']: <YOUR_ORG>
Enter team [no-team]. Choices: ['<YOUR_TEAM>', 'no-team']: <YOUR_TEAM>
Enter ace [no-ace]. Choices: ['no-ace']: no-ace
```

> [!WARNING]
> `ngc cli` will create  a `.bash_profile` file if it does not exist. If you already have a `.bashrc` file, please make sure to merge the two files properly. Otherwise, your `bash` environment may not work as expected.

##### Download Riva Models

Download Riva Embedded version models for `Jetson 7.0`:

```bash
ngc registry resource download-version nvidia/riva/riva_quickstart_arm64:2.24.0

cd riva_quickstart_arm64_v2.24.0
sudo bash riva_init.sh

# initialize riva model locally
# this will ask the NGC api key to download the model, use <YOUR_API_KEY>
# this will take a while to download
```

> [!NOTE]
> The following command is for testing.

Run Riva locally:

```bash
cd riva_quickstart_arm64_v2.24.0
bash riva_start.sh
```

Now, please expose these environment variables in your `~/.bashrc` file to use Riva service:

```bash
export RIVA_API_KEY=<YOUR_API_KEY>
export RIVA_API_NGC_ORG=<YOUR_ORG>
export RIVA_EULA=accept

source ~/.bashrc
```

##### OpenMind Riva Docker Image for Jetson

We create a `openmindagi/riva-speech-server:2.24.0-l4t-aarch64` docker image that has Riva ASR and TTS endpoints with the example code to run Riva services on Jetson devices. You can pull the image directly without downloading the models from NGC:

```bash
docker pull openmindagi/riva-speech-server:2.24.0-l4t
```

The dockerfile can be found [here](https://github.com/OpenMind/OM1-modules/blob/main/docker/Dockerfile.riva) and the docker-compose file can be found [here](https://github.com/OpenMind/OM1-deployment/blob/main/latest/riva_speech.yml).

>[!NOTE]
> Once you download the models from NGC and export the environment variables, you can use [OpenMind Portal](https://portal.openmind.org) to download Riva dockerfile and run Riva services.

Once you have Riva services running, you can use the following script to test the ASR and TTS endpoints:

```bash
git clone https://github.com/OpenMind/OM1-modules.git

cd OM1-modules

# Activate poetry shell
poetry shell

# Install dependencies
poetry install

# Test ASR
python3 -m om1_speech.main --remote-url=ws://localhost:6790

# Test TTS
poetry run om1_tts --tts-url=https://api-dev.openmind.org/api/core/tts --device=<optional> --rate=<optional>
```

## Port Usage

- 1935: MediaMTX RTMP Server
- 6790: OM Riva ASR Websocket Server API
- 6791: OM Riva TTS HTTP Server API
- 8000: MediaMTX RTMP Server API
- 8001: MediaMTX HLS Server API
- 8554: MediaMTX RTSP Server API
- 8860: Qwen 30B Quantized API
- 8880: Kokoro TTS API
- 8888: MediaMTX Streaming Server API
- 50000: Riva Server API
- 50051: Riva NMT Remote TTS/ASR API
