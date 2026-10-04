#!/bin/bash
set -e

# ================================================
# COLORES Y ESTILOS
# ================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▶${RESET}"

# ================================================
# HELPERS UI
# ================================================
print_header() {
  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

print_section() {
  echo -e "\n${MAGENTA}${BOLD}── $1 ──────────────────────────────────────${RESET}\n"
}

print_step()  { echo -e "  ${ARROW} $1"; }
print_ok()    { echo -e "  ${CHECK} ${GREEN}$1${RESET}"; }
print_skip()  { echo -e "  ${DIM}⊘  $1 — omitido${RESET}"; }
print_error() { echo -e "  ${CROSS} ${RED}$1${RESET}"; }
print_warn()  { echo -e "  ${YELLOW}⚠  $1${RESET}"; }

# ================================================
# SUDO — capturar y mantener vivo
# ================================================
require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo -e "\n  ${YELLOW}Se necesita contraseña de sudo para continuar.${RESET}"
    sudo -v
  fi
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
  SUDO_KEEPER_PID=$!
}

# ================================================
# TRAP — limpieza al salir (normal, error o Ctrl+C)
# ================================================
cleanup() {
  tput cnorm 2>/dev/null || true   # FIX: restaurar cursor aunque sea Ctrl+C
  stty sane  2>/dev/null || true   # FIX: restaurar terminal si quedó en raw mode
  [[ -n "${SUDO_KEEPER_PID:-}" ]] && kill "$SUDO_KEEPER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM   # FIX: también atrapa Ctrl+C (INT) y TERM

# ================================================
# CONFIRM — con restauración de terminal previa
# ================================================
confirm() {
  local default="${2:-n}"
  local prompt
  stty sane 2>/dev/null || true  # FIX: asegurar terminal sana antes de leer
  [[ "$default" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
  echo -ne "  ${YELLOW}?${RESET} $1 ${DIM}$prompt${RESET} "
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ================================================
# DEPENDENCIAS DEL WIZARD
# ================================================
ensure_deps() {
  for dep in curl wget git gpg unzip; do
    if ! command -v "$dep" &>/dev/null; then
      sudo apt-get install -y -qq "$dep"
    fi
  done
}

# ================================================
# GITHUB API — helper con manejo de rate limit
# ================================================
github_latest_url() {
  local repo="$1" filter="$2"
  local response url

  # FIX: sin -f para poder leer errores HTTP (rate limit, etc.) antes de fallar
  response=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
  if [[ -z "$response" ]]; then
    print_error "Sin respuesta de GitHub API (¿sin internet?)"
    return 1
  fi

  # Ahora sí llega aquí el JSON de error
  if echo "$response" | grep -q '"message"'; then
    local msg
    msg=$(echo "$response" | grep '"message"' | cut -d '"' -f 4)
    print_error "GitHub API: $msg"
    return 1
  fi

  url=$(echo "$response" | grep browser_download_url | grep "$filter" | cut -d '"' -f 4 | head -n 1)
  if [[ -z "$url" ]]; then
    print_error "No se encontró release para '$filter' en $repo"
    return 1
  fi
  echo "$url"
}

# ================================================
# INSTALADORES INDIVIDUALES
# ================================================

install_base() {
  print_step "Actualizando sistema y paquetes base..."
  sudo apt update -qq && sudo apt upgrade -y -qq
  sudo apt install -y -qq \
    build-essential curl wget git unzip zsh \
    software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release
  print_ok "Base del sistema lista"
}

install_zsh_ohmyzsh() {
  print_step "Instalando Zsh + Oh My Zsh..."
  sudo apt install -y -qq zsh fonts-powerline

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    sudo chsh -s "$(which zsh)" "$USER"
  else
    print_skip "Oh My Zsh ya instalado"
  fi

  # FIX: verificar si el plugin ya existe antes de clonar
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  fi
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --quiet https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  fi

  print_ok "Zsh + Oh My Zsh instalados"
}

install_ohmyposh() {
  if command -v oh-my-posh &>/dev/null; then
    print_skip "Oh My Posh ya está instalado"
    return
  fi
  print_step "Instalando Oh My Posh..."
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  print_ok "Oh My Posh instalado"
}

install_nerd_fonts() {
  print_step "Instalando Nerd Fonts (Hack + Cascadia Code)..."
  local FONT_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONT_DIR"
  local changed=false

  # Cascadia Code
  if ! fc-list | grep -qi "CascadiaCode"; then
    local cascadia_url
    if cascadia_url=$(github_latest_url "microsoft/cascadia-code" "CascadiaCode.*\.zip"); then
      wget -q "$cascadia_url" -O "$FONT_DIR/CascadiaCode.zip"
      # FIX: extraer a subdirectorio para no mezclar con otras fuentes
      mkdir -p "$FONT_DIR/CascadiaCode"
      unzip -q -o "$FONT_DIR/CascadiaCode.zip" -d "$FONT_DIR/CascadiaCode"
      rm -f "$FONT_DIR/CascadiaCode.zip"
      changed=true
      print_ok "Cascadia Code instalada"
    fi
  else
    print_skip "Cascadia Code ya instalada"
  fi

  # Hack Nerd Font
  if ! fc-list | grep -qi "HackNerdFont\|Hack Nerd"; then
    local hack_url
    if hack_url=$(github_latest_url "ryanoasis/nerd-fonts" "Hack\.zip"); then
      wget -q "$hack_url" -O "$FONT_DIR/Hack.zip"
      # FIX: extraer a subdirectorio
      mkdir -p "$FONT_DIR/HackNerdFont"
      unzip -q -o "$FONT_DIR/Hack.zip" -d "$FONT_DIR/HackNerdFont"
      rm -f "$FONT_DIR/Hack.zip"
      changed=true
      print_ok "Hack Nerd Font instalada"
    fi
  else
    print_skip "Hack Nerd Font ya instalada"
  fi

  if [[ "$changed" == true ]]; then
    fc-cache -f "$FONT_DIR"
    print_ok "Caché de fuentes actualizado"
  fi
}

install_vscode() {
  if command -v code &>/dev/null; then
    print_skip "VS Code ya está instalado"
    return
  fi
  print_step "Instalando Visual Studio Code..."
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
  sudo install -o root -g root -m 644 /tmp/packages.microsoft.gpg /usr/share/keyrings/
  sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
    https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  sudo apt update -qq
  sudo apt install -y -qq code
  rm -f /tmp/packages.microsoft.gpg
  print_ok "VS Code instalado"
}

install_vscodium() {
  if command -v codium &>/dev/null; then
    print_skip "VSCodium ya está instalado"
    return
  fi
  print_step "Instalando VSCodium..."
  wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
    | gpg --dearmor | sudo dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg status=none
  sudo tee /etc/apt/sources.list.d/vscodium.sources >/dev/null <<'EOF'
Types: deb
URIs: https://download.vscodium.com/debs
Suites: vscodium
Components: main
Architectures: amd64 arm64
Signed-by: /usr/share/keyrings/vscodium-archive-keyring.gpg
EOF
  sudo apt update -qq
  sudo apt install -y -qq codium
  print_ok "VSCodium instalado"
}

# Crea (o actualiza) en VSCodium cada perfil de perfiles-de-desarrollo/<carpeta>/
# usando su perfil.conf, settings.json y extensions.txt
configure_vscodium_profiles() {
  local profiles_dir
  profiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perfiles-de-desarrollo"
  local user_dir="$HOME/.config/VSCodium/User"
  local storage="$user_dir/globalStorage/storage.json"

  if ! command -v codium &>/dev/null; then
    print_error "VSCodium no está instalado — no se pueden configurar perfiles"
    return 0
  fi
  if [[ ! -d "$profiles_dir" ]]; then
    print_error "No se encontró $profiles_dir"
    return 0
  fi
  # VSCodium reescribe storage.json al cerrarse; si está abierto pisaría el perfil nuevo
  if pgrep -x codium &>/dev/null; then
    print_warn "VSCodium está abierto — ciérralo para configurar los perfiles"
    while pgrep -x codium &>/dev/null; do
      confirm "¿Ya lo cerraste?" "y" || { print_skip "Perfiles de VSCodium"; return 0; }
    done
  fi

  # Todo Tree usa el ripgrep del sistema (todo-tree.ripgrep.ripgrep = /usr/bin/rg)
  if ! command -v rg &>/dev/null; then
    sudo apt install -y -qq ripgrep
  fi

  mkdir -p "$user_dir/globalStorage"

  local dir
  for dir in "$profiles_dir"/*/; do
    [[ -f "$dir/perfil.conf" ]] || continue
    local NOMBRE="" ICONO=""
    # shellcheck source=/dev/null
    source "$dir/perfil.conf"
    [[ -n "$NOMBRE" ]] || { print_error "Falta NOMBRE en $dir/perfil.conf"; continue; }

    print_step "Configurando perfil de VSCodium \"$NOMBRE\"..."

    # Registrar el perfil en storage.json (o reutilizar el existente) y obtener su carpeta
    local location
    location=$(python3 - "$storage" "$NOMBRE" "${ICONO:-}" <<'PY'
import json, os, secrets, sys
path, name, icon = sys.argv[1:4]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
profiles = data.setdefault("userDataProfiles", [])
for p in profiles:
    if p.get("name") == name:
        print(p["location"])
        sys.exit()
entry = {"location": secrets.token_hex(4), "name": name}
if icon:
    entry["icon"] = icon
profiles.append(entry)
with open(path, "w") as f:
    json.dump(data, f, indent=4)
print(entry["location"])
PY
    ) || { print_error "No se pudo registrar el perfil $NOMBRE"; continue; }

    local profile_path="$user_dir/profiles/$location"
    mkdir -p "$profile_path"

    if [[ -f "$dir/settings.json" ]]; then
      if [[ -s "$profile_path/settings.json" ]] && ! cmp -s "$dir/settings.json" "$profile_path/settings.json"; then
        local backup="$profile_path/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$profile_path/settings.json" "$backup"
        print_warn "Backup de ajustes previos en $backup"
      fi
      cp "$dir/settings.json" "$profile_path/settings.json"
    fi

    if [[ -f "$dir/extensions.txt" ]]; then
      local ext failed=0
      while read -r ext; do
        [[ -z "$ext" || "$ext" == \#* ]] && continue
        codium --profile "$NOMBRE" --install-extension "$ext" &>/dev/null \
          || { print_error "No se pudo instalar $ext"; failed=$(( failed + 1 )); }
      done < "$dir/extensions.txt"
      (( failed == 0 )) || print_warn "$failed extensiones fallaron en \"$NOMBRE\""
    fi

    print_ok "Perfil \"$NOMBRE\" listo"
  done
}

# Apps de la tienda COSMIC (Flatpak). Para agregar otra, añade una línea:
#   "id_menu|remoto|id_flatpak|Texto del menú"
# El id_flatpak se busca con: flatpak search <nombre>
FLATPAK_APPS=(
  "spotify|flathub|com.spotify.Client|Spotify"
  "obsidian|flathub|md.obsidian.Obsidian|Obsidian"
  "cosmic_tweaks|flathub|dev.edfloreshz.CosmicTweaks|COSMIC Tweaks — ajustes extra del escritorio"
  "clipboard_applet|cosmic|io.github.cosmic_utils.cosmic-ext-applet-clipboard-manager|Applet de portapapeles para el panel de COSMIC"
)

ensure_flatpak_remotes() {
  if ! command -v flatpak &>/dev/null; then
    sudo apt install -y -qq flatpak
  fi
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-add --user --if-not-exists cosmic https://apt.pop-os.org/cosmic/cosmic.flatpakrepo
}

# Se instalan para el usuario (--user), igual que desde la tienda COSMIC
install_flatpak_apps() {
  local entry key remote app_id label remotes_ready=false
  for entry in "${FLATPAK_APPS[@]}"; do
    IFS='|' read -r key remote app_id label <<< "$entry"
    [[ "${SELECTIONS[$key]:-off}" == "on" ]] || continue

    if flatpak info --user "$app_id" &>/dev/null; then
      print_skip "${label%% —*} ya está instalado"
      continue
    fi
    if [[ "$remotes_ready" == false ]]; then
      ensure_flatpak_remotes
      remotes_ready=true
    fi
    print_step "Instalando ${label%% —*} (Flatpak)..."
    if flatpak install --user -y --noninteractive "$remote" "$app_id" &>/dev/null; then
      print_ok "${label%% —*} instalado"
    else
      print_error "No se pudo instalar ${label%% —*} ($app_id)"
    fi
  done
}

install_steam() {
  if command -v steam &>/dev/null; then
    print_skip "Steam ya está instalado"
    return
  fi
  print_step "Instalando Steam..."
  sudo apt install -y -qq steam
  print_ok "Steam instalado"
}

install_copyq() {
  if command -v copyq &>/dev/null; then
    print_skip "CopyQ ya está instalado"
    return
  fi
  print_step "Instalando CopyQ..."
  sudo apt install -y -qq copyq
  print_ok "CopyQ instalado"
}

install_kdeconnect() {
  # kdeconnectd vive en libexec (fuera del PATH); kdeconnect-cli sí está en /usr/bin
  if command -v kdeconnect-cli &>/dev/null; then
    print_skip "KDE Connect ya está instalado"
  else
    print_step "Instalando KDE Connect..."
    sudo apt install -y -qq kdeconnect
    print_ok "KDE Connect instalado"
  fi
  configure_kdeconnect_sendto
}

# "Enviar a dispositivo (KDE Connect)" en el clic derecho de los archivos.
# COSMIC Files lee sus acciones del menú contextual de
# ~/.config/cosmic/com.system76.CosmicFiles/v1/context_actions (formato RON).
configure_kdeconnect_sendto() {
  local script_src actions_file entry
  script_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kdeconnect-enviar.sh"
  if [[ ! -f "$script_src" ]]; then
    print_error "No se encontró $script_src"
    return 0
  fi

  print_step "Agregando \"Enviar a dispositivo\" al menú de archivos..."
  # zenity muestra la ventana para elegir el dispositivo
  if ! command -v zenity &>/dev/null; then
    sudo apt install -y -qq zenity
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 755 "$script_src" "$HOME/.local/bin/kdeconnect-enviar"

  # Versiones anteriores lo registraban como aplicación; COSMIC Files no lo mostraba
  rm -f "$HOME/.local/share/applications/kdeconnect-enviar.desktop"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

  actions_file="$HOME/.config/cosmic/com.system76.CosmicFiles/v1/context_actions"
  entry="    (
        name: \"Enviar a dispositivo (KDE Connect)\",
        selection: Files,
        steps: [\"$HOME/.local/bin/kdeconnect-enviar %F\"],
    ),"
  mkdir -p "$(dirname "$actions_file")"

  if [[ -f "$actions_file" ]] && grep -q 'kdeconnect-enviar' "$actions_file"; then
    print_skip "\"Enviar a dispositivo\" ya está en el menú de archivos"
    return 0
  elif [[ -s "$actions_file" ]] && [[ "$(grep -v '^[[:space:]]*$' "$actions_file" | tail -n 1)" == "]" ]]; then
    # Ya hay otras acciones: agregar la nuestra antes del "]" final
    local tmp
    tmp="$(mktemp)"
    { sed '$!b; /^[[:space:]]*\][[:space:]]*$/d' <(grep -v '^[[:space:]]*$' "$actions_file")
      printf '%s\n]\n' "$entry"; } > "$tmp"
    mv "$tmp" "$actions_file"
  elif [[ -s "$actions_file" ]]; then
    print_warn "No se pudo modificar $actions_file (formato inesperado); agrega la acción a mano"
    return 0
  else
    printf '[\n%s\n]\n' "$entry" > "$actions_file"
  fi

  print_ok "\"Enviar a dispositivo\" disponible en el clic derecho de los archivos (reabre COSMIC Files)"
}

install_noir_theme() {
  local theme_file
  theme_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/caelestia-noir.ron"
  if ! command -v cosmic-settings &>/dev/null; then
    print_warn "cosmic-settings no encontrado — el tema Noir requiere COSMIC"
    return
  fi
  if [[ ! -f "$theme_file" ]]; then
    print_error "No se encontró $theme_file"
    return
  fi
  print_step "Instalando tema COSMIC caelestia-noir..."
  if cosmic-settings appearance import "$theme_file" &>/dev/null; then
    print_ok "Tema caelestia-noir aplicado (modo oscuro)"
  else
    print_error "No se pudo importar el tema caelestia-noir"
  fi
}

install_candy_icons() {
  local ICONS_DIR="$HOME/.local/share/icons"
  local ICON_THEME_FILE="$HOME/.config/cosmic/com.system76.CosmicTk/v1/icon_theme"

  if [[ -f "$ICONS_DIR/candy-icons/index.theme" ]]; then
    print_skip "Candy Icons ya está instalado"
  else
    print_step "Descargando Candy Icons..."
    mkdir -p "$ICONS_DIR"
    local tmp
    tmp=$(mktemp -d)
    if ! wget -q "https://github.com/EliverLara/candy-icons/archive/refs/heads/master.tar.gz" -O "$tmp/candy.tar.gz"; then
      print_error "No se pudo descargar Candy Icons"
      rm -rf "$tmp"
      return 0
    fi
    tar -xzf "$tmp/candy.tar.gz" -C "$tmp"
    rm -rf "$ICONS_DIR/candy-icons"
    mv "$tmp/candy-icons-master" "$ICONS_DIR/candy-icons"
    rm -rf "$tmp"
    gtk-update-icon-cache "$ICONS_DIR/candy-icons" 2>/dev/null || true
    print_ok "Candy Icons instalado en $ICONS_DIR/candy-icons"
  fi

  # Activarlo en COSMIC (Ajustes → Apariencia → Iconos) y en apps GTK
  mkdir -p "$(dirname "$ICON_THEME_FILE")"
  echo '"candy-icons"' > "$ICON_THEME_FILE"
  gsettings set org.gnome.desktop.interface icon-theme 'candy-icons' 2>/dev/null || true
  print_ok "Candy Icons activado como tema de iconos"
}

install_bat() {
  if command -v bat &>/dev/null || command -v batcat &>/dev/null; then
    print_skip "bat ya está instalado"
    return
  fi
  print_step "Instalando bat..."
  sudo apt install -y -qq bat
  # FIX: crear ~/.local/bin antes del symlink
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
    print_ok "bat instalado (symlink batcat → bat)"
  else
    print_ok "bat instalado"
  fi
}

install_eza() {
  if command -v eza &>/dev/null; then
    print_skip "eza ya está instalado"
    return
  fi
  print_step "Instalando eza..."
  sudo apt install -y -qq eza 2>/dev/null || {
    if command -v cargo &>/dev/null; then
      cargo install eza
    else
      print_error "eza no disponible en repos y cargo no está instalado — omitiendo"
      return 0  # FIX: no matar el script, solo reportar
    fi
  }
  print_ok "eza instalado"
}

install_rvm_ruby() {
  if command -v rvm &>/dev/null || [[ -s "/etc/profile.d/rvm.sh" ]]; then
    print_skip "RVM ya está instalado"
    return
  fi
  print_step "Instalando RVM + Ruby..."
  sudo apt install -y -qq gnupg2

  # FIX: fallback si el keyserver falla
  gpg --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || \
  gpg --keyserver hkp://keys.openpgp.org \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || \
    print_warn "No se pudieron importar las claves GPG de RVM — continuando igual"

  sudo apt-add-repository -y ppa:rael-gc/rvm
  sudo apt update -qq
  sudo apt install -y -qq rvm
  sudo usermod -a -G rvm "$USER"
  print_ok "RVM instalado (cierra sesión para activarlo)"
}

install_nvm_node() {
  print_step "Instalando NVM + Node.js (LTS)..."
  export NVM_DIR="$HOME/.nvm"

  if [ ! -d "$NVM_DIR" ]; then
    git clone --quiet https://github.com/nvm-sh/nvm.git "$NVM_DIR"
    # FIX: usar la última tag disponible en vez de versión hardcodeada
    local nvm_latest
    nvm_latest=$(cd "$NVM_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "v0.39.7")
    cd "$NVM_DIR" && git checkout "$nvm_latest" -q && cd -
  fi

  \. "$NVM_DIR/nvm.sh"

  # FIX: grep pattern corregido — nvm ls muestra "v22.x.x" con "(lts/name)" al lado
  if nvm ls --no-colors 2>/dev/null | grep -qE "v[0-9]+\.[0-9]+\.[0-9]+ \(lts/"; then
    print_skip "Node.js LTS ya instalado"
  else
    nvm install --lts
    nvm use --lts
    print_ok "Node.js $(node -v) instalado via NVM"
  fi
}

install_docker() {
  if command -v docker &>/dev/null; then
    print_skip "Docker ya está instalado"
    return
  fi
  print_step "Instalando Docker..."
  # get.docker.com no reconoce Pop!_OS (ID=pop) y lo toma por Debian; se usa el
  # repo oficial de Ubuntu con el codename base (p. ej. noble en Pop!_OS 24.04)
  local codename
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt update -qq
  sudo apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  print_ok "Docker instalado (cierra sesión para usarlo sin sudo)"
}

install_vlc() {
  if command -v vlc &>/dev/null; then
    print_skip "VLC ya está instalado"
    return
  fi
  print_step "Instalando VLC..."
  sudo apt install -y -qq vlc
  print_ok "VLC instalado"
}

install_gimp() {
  if command -v gimp &>/dev/null; then
    print_skip "GIMP ya está instalado"
    return
  fi
  print_step "Instalando GIMP..."
  sudo apt install -y -qq gimp
  print_ok "GIMP instalado"
}

install_flameshot() {
  if command -v flameshot &>/dev/null; then
    print_skip "Flameshot ya está instalado"
    return
  fi
  print_step "Instalando Flameshot..."
  sudo apt install -y -qq flameshot
  print_ok "Flameshot instalado"
}

install_htop() {
  if command -v htop &>/dev/null; then
    print_skip "htop ya está instalado"
    return
  fi
  print_step "Instalando htop..."
  sudo apt install -y -qq htop
  print_ok "htop instalado"
}

configure_zshrc() {
  print_step "Configurando ~/.zshrc..."

  # FIX: backup si ya existe un .zshrc con contenido
  if [[ -f "$HOME/.zshrc" && -s "$HOME/.zshrc" ]]; then
    local backup="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HOME/.zshrc" "$backup"
    print_warn "Backup guardado en $backup"
  fi

  # FIX: if/fi en vez de [[ ]] && para evitar set -e cuando rvm_ruby=off
  local plugins="git zsh-syntax-highlighting zsh-autosuggestions"
  if [[ "${SELECTIONS[rvm_ruby]:-off}" == "on" ]]; then
    plugins="$plugins rails git-flow"
  fi

  cat > "$HOME/.zshrc" <<ZSHRC
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=($plugins)
source \$ZSH/oh-my-zsh.sh

# PATH
export PATH="\$HOME/.local/bin:\$HOME/.local/share/bin:\$PATH"

# Oh My Posh
if command -v oh-my-posh &>/dev/null && [ "\$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "\$(oh-my-posh init zsh --config \$HOME/.cache/oh-my-posh/themes/clean-detailed.omp.json)"
fi

# NVM
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

# RVM
[[ -s "/etc/profile.d/rvm.sh" ]] && source /etc/profile.d/rvm.sh

# eza
if command -v eza &>/dev/null; then
  alias ls='eza --icons --color=auto'
  alias ll='eza -la --icons --color=auto'
  alias la='eza -la --icons --color=auto --git'
  alias lt='eza --tree --icons'
fi

# bat
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
  alias bat='batcat'
fi
ZSHRC

  print_ok "~/.zshrc configurado"
}

# ================================================
# MENÚ INTERACTIVO — Navegación con teclado
# ================================================
declare -A SELECTIONS

_menu_title() {
  case "$1" in
    base)  echo "PASO 1 / 5 — Herramientas Base" ;;
    shell) echo "PASO 2 / 5 — Terminal & Shell" ;;
    dev)   echo "PASO 3 / 5 — Desarrollo" ;;
    apps)  echo "PASO 4 / 5 — Aplicaciones" ;;
    store) echo "PASO 5 / 5 — Tienda COSMIC (Flatpak)" ;;
  esac
}

# FIX: _draw_menu ya no recibe parámetros muertos — solo category y cursor
_draw_menu() {
  local category="$1" cursor="$2"
  local total="${#MENU_IDS[@]}"

  clear
  print_header
  echo -e "  ${WHITE}${BOLD}$(_menu_title "$category")${RESET}\n"
  echo -e "  ${DIM}↑↓ mover  •  Space marcar  •  a todo  •  n nada  •  Enter continuar  •  q salir${RESET}\n"

  for (( i=0; i<total; i++ )); do
    local id="${MENU_IDS[$i]}"
    local label="${MENU_LABELS[$i]}"
    local checked="${SELECTIONS[$id]:-off}"

    if (( i == cursor )); then
      if [[ "$checked" == "on" ]]; then
        echo -e "  ${CYAN}${BOLD}❯ ${GREEN}[✔]${CYAN} $label${RESET}"
      else
        echo -e "  ${CYAN}${BOLD}❯ [ ] $label${RESET}"
      fi
    else
      if [[ "$checked" == "on" ]]; then
        echo -e "    ${GREEN}[✔]${RESET} $label"
      else
        echo -e "    ${DIM}[ ] $label${RESET}"
      fi
    fi
  done
  echo ""
}

MENU_IDS=()
MENU_LABELS=()

show_menu() {
  local category="$1"
  shift

  MENU_IDS=()
  MENU_LABELS=()
  for opt in "$@"; do
    MENU_IDS+=("${opt%%:*}")
    MENU_LABELS+=("${opt#*:}")
  done

  local total="${#MENU_IDS[@]}"
  local cursor=0

  tput civis 2>/dev/null || true

  while true; do
    _draw_menu "$category" "$cursor"

    local key
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
      local seq1 seq2
      IFS= read -rsn1 -t 0.1 seq1 2>/dev/null || true
      IFS= read -rsn1 -t 0.1 seq2 2>/dev/null || true
      if [[ "$seq1" == '[' ]]; then
        case "$seq2" in
          'A') (( cursor > 0 ))         && (( cursor-- )) || true ;;
          'B') (( cursor < total - 1 )) && (( cursor++ )) || true ;;
        esac
      fi

    elif [[ "$key" == ' ' ]]; then
      local id="${MENU_IDS[$cursor]}"
      if [[ "${SELECTIONS[$id]:-off}" == "on" ]]; then
        SELECTIONS[$id]="off"
      else
        SELECTIONS[$id]="on"
      fi
      (( cursor < total - 1 )) && (( cursor++ )) || true

    elif [[ "$key" == 'a' || "$key" == 'A' ]]; then
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="on"; done

    elif [[ "$key" == 'n' || "$key" == 'N' ]]; then
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="off"; done

    elif [[ "$key" == '' ]]; then
      break

    elif [[ "$key" == 'q' || "$key" == 'Q' ]]; then
      tput cnorm 2>/dev/null || true
      echo -e "\n  ${YELLOW}Instalación cancelada.${RESET}\n"
      exit 0
    fi
  done

  tput cnorm 2>/dev/null || true
}

# ================================================
# RESUMEN
# ================================================
show_summary() {
  clear
  print_header
  echo -e "  ${WHITE}${BOLD}Resumen de instalación${RESET}\n"

  declare -A LABEL_MAP=(
    [base]="Actualizar sistema + paquetes esenciales"
    [eza]="eza — ls mejorado"
    [bat]="bat — cat con syntax highlighting"
    [htop]="htop — monitor de procesos"
    [zsh_ohmyzsh]="Zsh + Oh My Zsh + plugins"
    [ohmyposh]="Oh My Posh"
    [nerd_fonts]="Nerd Fonts (Hack + Cascadia Code)"
    [zshrc]="Generar ~/.zshrc preconfigurado"
    [vscode]="Visual Studio Code"
    [vscodium]="VSCodium"
    [vscodium_profiles]="Perfiles de desarrollo de VSCodium"
    [nvm_node]="NVM + Node.js LTS"
    [rvm_ruby]="RVM + Ruby"
    [docker]="Docker Engine"
    [steam]="Steam"
    [copyq]="CopyQ — gestor de portapapeles"
    [kdeconnect]="KDE Connect + \"Enviar a dispositivo\" en el menú de archivos"
    [noir_theme]="Tema COSMIC caelestia-noir"
    [candy_icons]="Candy Icons — tema de iconos"
    [vlc]="VLC"
    [gimp]="GIMP"
    [flameshot]="Flameshot"
  )

  local count=0
  # FIX: mostrar en orden definido, no el aleatorio de las claves del asociativo
  local ordered=(base eza bat htop zsh_ohmyzsh ohmyposh nerd_fonts zshrc
                 vscode vscodium vscodium_profiles nvm_node rvm_ruby docker
                 steam copyq kdeconnect noir_theme candy_icons vlc gimp flameshot)
  local entry fp_key fp_label
  for entry in "${FLATPAK_APPS[@]}"; do
    IFS='|' read -r fp_key _ _ fp_label <<< "$entry"
    LABEL_MAP[$fp_key]="$fp_label (Flatpak)"
    ordered+=("$fp_key")
  done
  for key in "${ordered[@]}"; do
    if [[ "${SELECTIONS[$key]:-off}" == "on" ]]; then
      echo -e "  ${CHECK} ${LABEL_MAP[$key]:-$key}"
      count=$(( count + 1 ))
    fi
  done

  if (( count == 0 )); then
    echo -e "  ${YELLOW}No seleccionaste nada. Saliendo...${RESET}\n"
    exit 0
  fi

  echo ""
  echo -e "  ${DIM}Se instalarán $count componentes.${RESET}\n"

  if ! confirm "¿Continuar con la instalación?" "y"; then
    echo -e "\n  ${YELLOW}Instalación cancelada.${RESET}\n"
    exit 0
  fi
}

# ================================================
# EJECUTAR INSTALACIONES
# ================================================
run_installations() {
  clear
  print_header
  print_section "Instalando..."

  require_sudo
  ensure_deps
  # FIX: solo hacer apt update aquí si NO se seleccionó install_base
  # (install_base ya lo hace internamente)
  if [[ "${SELECTIONS[base]:-off}" != "on" ]]; then
    sudo apt update -qq
  fi

  # FIX: if/fi en vez de [[ ]] && fn — evita que set -e mate el script
  #      cuando una selección es "off" (exit code 1)
  if [[ "${SELECTIONS[base]:-off}"       == "on" ]]; then install_base;       fi
  if [[ "${SELECTIONS[zsh_ohmyzsh]:-off}" == "on" ]]; then install_zsh_ohmyzsh; fi
  if [[ "${SELECTIONS[ohmyposh]:-off}"   == "on" ]]; then install_ohmyposh;  fi
  if [[ "${SELECTIONS[nerd_fonts]:-off}" == "on" ]]; then install_nerd_fonts; fi
  if [[ "${SELECTIONS[eza]:-off}"        == "on" ]]; then install_eza;        fi
  if [[ "${SELECTIONS[bat]:-off}"        == "on" ]]; then install_bat;        fi
  if [[ "${SELECTIONS[htop]:-off}"       == "on" ]]; then install_htop;       fi
  if [[ "${SELECTIONS[zshrc]:-off}"      == "on" ]]; then configure_zshrc;    fi
  if [[ "${SELECTIONS[vscode]:-off}"     == "on" ]]; then install_vscode;     fi
  if [[ "${SELECTIONS[vscodium]:-off}"   == "on" ]]; then install_vscodium;   fi
  if [[ "${SELECTIONS[vscodium_profiles]:-off}" == "on" ]]; then configure_vscodium_profiles; fi
  if [[ "${SELECTIONS[nvm_node]:-off}"   == "on" ]]; then install_nvm_node;   fi
  if [[ "${SELECTIONS[rvm_ruby]:-off}"   == "on" ]]; then install_rvm_ruby;   fi
  if [[ "${SELECTIONS[docker]:-off}"     == "on" ]]; then install_docker;     fi
  if [[ "${SELECTIONS[steam]:-off}"      == "on" ]]; then install_steam;      fi
  if [[ "${SELECTIONS[copyq]:-off}"      == "on" ]]; then install_copyq;      fi
  if [[ "${SELECTIONS[kdeconnect]:-off}" == "on" ]]; then install_kdeconnect; fi
  if [[ "${SELECTIONS[noir_theme]:-off}" == "on" ]]; then install_noir_theme; fi
  if [[ "${SELECTIONS[candy_icons]:-off}" == "on" ]]; then install_candy_icons; fi
  if [[ "${SELECTIONS[vlc]:-off}"        == "on" ]]; then install_vlc;        fi
  if [[ "${SELECTIONS[gimp]:-off}"       == "on" ]]; then install_gimp;       fi
  if [[ "${SELECTIONS[flameshot]:-off}"  == "on" ]]; then install_flameshot;  fi
  install_flatpak_apps
}

# ================================================
# FLUJO PRINCIPAL
# ================================================
clear
print_header
echo -e "  ${DIM}Bienvenido al instalador interactivo para Pop!_OS / Ubuntu.${RESET}"
echo -e "  ${DIM}Navega con ${RESET}${BOLD}↑ ↓${RESET}${DIM}, marca con ${RESET}${BOLD}Space${RESET}${DIM}, confirma con ${RESET}${BOLD}Enter${RESET}${DIM}.${RESET}\n"
sleep 2

show_menu "base" \
  "base:Actualizar sistema + paquetes esenciales (recomendado)" \
  "eza:eza — ls con esteroides e íconos" \
  "bat:bat — cat con syntax highlighting" \
  "htop:htop — monitor de procesos interactivo"

show_menu "shell" \
  "zsh_ohmyzsh:Zsh + Oh My Zsh + plugins (syntax, autosuggestions)" \
  "ohmyposh:Oh My Posh (prompt bonito para Zsh)" \
  "nerd_fonts:Nerd Fonts — Hack + Cascadia Code" \
  "zshrc:Generar ~/.zshrc preconfigurado"

show_menu "dev" \
  "vscode:Visual Studio Code" \
  "vscodium:VSCodium" \
  "vscodium_profiles:Perfiles de desarrollo de VSCodium (ajustes + extensiones)" \
  "nvm_node:NVM + Node.js LTS" \
  "rvm_ruby:RVM + Ruby (vía PPA rael-gc)" \
  "docker:Docker Engine"

show_menu "apps" \
  "steam:Steam (gaming)" \
  "copyq:CopyQ — gestor de portapapeles avanzado" \
  "kdeconnect:KDE Connect — sincronización con Android + \"Enviar a\" en archivos" \
  "noir_theme:Tema COSMIC caelestia-noir (oscuro, esquinas rectas)" \
  "candy_icons:Candy Icons — tema de iconos con degradados" \
  "vlc:VLC — reproductor multimedia" \
  "gimp:GIMP — editor de imágenes" \
  "flameshot:Flameshot — capturas de pantalla"

flatpak_options=()
for entry in "${FLATPAK_APPS[@]}"; do
  IFS='|' read -r fp_key _ _ fp_label <<< "$entry"
  flatpak_options+=("$fp_key:$fp_label")
done
show_menu "store" "${flatpak_options[@]}"

show_summary
run_installations

echo ""
print_section "¡Todo listo!"
echo -e "  ${CHECK} ${GREEN}${BOLD}Instalación completada.${RESET}\n"
echo -e "  ${YELLOW}Próximos pasos:${RESET}"
echo -e "  ${DIM}• Cambia a zsh:${RESET}                    ${CYAN}exec zsh${RESET}"
echo -e "  ${DIM}• Si instalaste RVM o Docker:${RESET}       cierra y vuelve a abrir sesión"
echo -e "  ${DIM}• Para explorar temas de Oh My Posh:${RESET} ${CYAN}ls ~/.cache/oh-my-posh/themes/${RESET}"
echo ""
