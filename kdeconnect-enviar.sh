#!/bin/bash
# Envía uno o más archivos a un dispositivo vinculado con KDE Connect,
# dejando elegir el dispositivo en una ventana.
# Uso: kdeconnect-enviar ARCHIVO...
# Lo instala setup_wizard.sh (opción KDE Connect) en ~/.local/bin/kdeconnect-enviar.

TITLE="Enviar a dispositivo"

error() {
  zenity --error --title="$TITLE" --width=360 --text="$1" 2>/dev/null
  exit 1
}

(( $# > 0 )) || error "No se seleccionó ningún archivo."
command -v kdeconnect-cli &>/dev/null || error "KDE Connect no está instalado."

# Solo dispositivos vinculados y conectados ahora mismo ("<id> <nombre>")
mapfile -t devices < <(kdeconnect-cli --list-available --id-name-only 2>/dev/null)

if (( ${#devices[@]} == 0 )); then
  error "No hay dispositivos vinculados disponibles.\n\nAbre KDE Connect en el teléfono, conéctalo a la misma red y vincúlalo desde la app KDE Connect de este equipo."
fi

rows=()
first=TRUE
for line in "${devices[@]}"; do
  rows+=("$first" "${line%% *}" "${line#* }")
  first=FALSE
done

if (( $# == 1 )); then
  what="«$(basename "$1")»"
else
  what="$# archivos"
fi

device_id=$(zenity --list --radiolist \
  --title="$TITLE" --text="¿A qué dispositivo envío $what?" \
  --column="" --column="ID" --column="Dispositivo" \
  --hide-column=2 --print-column=2 \
  --width=380 --height=280 \
  "${rows[@]}" 2>/dev/null) || exit 0   # Cancelar
[[ -n "$device_id" ]] || exit 0

failed=()
for file in "$@"; do
  kdeconnect-cli --device "$device_id" --share "$(realpath "$file")" &>/dev/null \
    || failed+=("$(basename "$file")")
done

if (( ${#failed[@]} > 0 )); then
  error "No se pudieron enviar:\n$(printf '• %s\n' "${failed[@]}")"
fi
