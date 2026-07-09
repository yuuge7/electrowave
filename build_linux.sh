#!/bin/bash

# 1. Compile the app
echo "🚀 Building Flutter Linux app..."
flutter build linux --release

# 2. Define our variables
APP_NAME="Electrowave"
APP_EXEC="$(pwd)/build/linux/x64/release/bundle/electrowave"
ICON_PATH="$(pwd)/web/music.png"
DESKTOP_FILE="$HOME/.local/share/applications/electrowave.desktop"

# 3. Generate the .desktop file and drop it into the system folder
echo "🐧 Generating Linux desktop shortcut..."

cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Name=$APP_NAME
GenericName=Media Player
Comment=Play local music
Exec=$APP_EXEC
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
EOF

# 4. Make the desktop file executable (required by some Linux distros)
chmod +x "$DESKTOP_FILE"

echo "✅ Done! $APP_NAME is now in your Linux app launcher."