#!/usr/bin/env bash
set -euo pipefail

APP_NAME="baixadorimagens"
APP_DISPLAY_NAME="Baixador de Imagens"
APP_VERSION="${1:-1.0.0}"
ARCH="amd64"

BUNDLE_DIR="build/linux/x64/release/bundle"
DIST_DIR="dist"
STAGE_DIR="build/deb_stage/${APP_NAME}_${APP_VERSION}_${ARCH}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Erro: Diretório de bundle não encontrado em $BUNDLE_DIR."
  echo "Execute 'flutter build linux --release' antes deste script."
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$STAGE_DIR/DEBIAN"
mkdir -p "$STAGE_DIR/opt/$APP_NAME"
mkdir -p "$STAGE_DIR/usr/bin"
mkdir -p "$STAGE_DIR/usr/share/applications"

# Copia o bundle do Flutter para /opt/baixadorimagens
cp -r "$BUNDLE_DIR/"* "$STAGE_DIR/opt/$APP_NAME/"
chmod +x "$STAGE_DIR/opt/$APP_NAME/$APP_NAME"

# Cria link simbólico em /usr/bin
ln -s "/opt/$APP_NAME/$APP_NAME" "$STAGE_DIR/usr/bin/$APP_NAME"

# Cria atalho .desktop para o menu do sistema
cat > "$STAGE_DIR/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=$APP_DISPLAY_NAME
Comment=Baixador de imagens em lote a partir de lista de URLs
Exec=/opt/$APP_NAME/$APP_NAME
Icon=folder-download
Terminal=false
Type=Application
Categories=Utility;Network;
StartupWMClass=$APP_NAME
EOF

# Cria arquivo de controle do pacote Debian
cat > "$STAGE_DIR/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $APP_VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0
Maintainer: MedasDev <dev@example.com>
Description: $APP_DISPLAY_NAME
 Aplicativo desktop em Flutter para download em lote de imagens.
EOF

# Gera o instalador .deb
dpkg-deb --build --root-owner-group "$STAGE_DIR" "$DIST_DIR/BaixadorImagens-Linux-x64.deb"

# Gera também um pacote portátil .tar.gz
tar -czf "$DIST_DIR/BaixadorImagens-Linux-x64-Portable.tar.gz" -C "$BUNDLE_DIR" .

echo "Instaladores gerados em $DIST_DIR/:"
ls -lh "$DIST_DIR"

