# Perfiles de desarrollo (VSCodium)

Cada subcarpeta es un **perfil de VSCodium**: sus ajustes y sus extensiones.
El asistente `setup_wizard.sh` los instala solo (opción *Perfiles de desarrollo* en el paso 3),
pero aquí está también cómo hacerlo **a mano** en un equipo nuevo.

```
perfiles-de-desarrollo/
└── ventor/
    ├── perfil.conf      # nombre e ícono del perfil en VSCodium
    ├── settings.json    # ajustes del perfil
    └── extensions.txt   # una extensión por línea
```

Para agregar un perfil nuevo, crea otra carpeta con esos mismos tres archivos.

---

## Perfil Ventor

POS en TypeScript + SQLite (`~/projects/ventor`).

### Extensiones

| Extensión | Para qué |
|---|---|
| `biomejs.biome` | Formatea y ordena imports al guardar |
| `yoavbls.pretty-ts-errors` | Errores de TypeScript legibles |
| `usernamehw.errorlens` | Errores y warnings al final de la línea |
| `eamodio.gitlens` | Autor y commit de cada línea |
| `qwtel.sqlite-viewer` | Abrir `pos.sqlite` como tabla |
| `mtxr.sqltools` + `mtxr.sqltools-driver-sqlite` | Consultas SQL contra `pos.sqlite` |
| `christian-kohler.path-intellisense` | Autocompletar rutas en imports |
| `editorconfig.editorconfig` | Respeta el `.editorconfig` del repo |
| `yzhang.markdown-all-in-one` | Atajos y vista previa de Markdown |
| `bierner.markdown-mermaid` | Diagramas Mermaid en la vista previa |
| `streetsidesoftware.code-spell-checker` (+ `-spanish`) | Ortografía en inglés y español |
| `gruntfuggly.todo-tree` | Lista de `TODO` / `FIXME` en la barra lateral |
| `zhuangtongfa.material-theme` | Tema *One Dark Pro Flat* |
| `pkief.material-icon-theme` | Íconos de archivos |
| `nicholashsiang.vscode-react-snippet` | Snippets de React (`rfc` + Tab) |
| `bruno-api-client.bruno` | Cliente de API (tipo Postman) |

### Ajustes importantes de `settings.json`

- **Biome** es el formateador por defecto; al guardar arregla el código y ordena los imports.
  Markdown usa *Markdown All in One*, con ajuste de línea.
- **TypeScript** usa la versión del proyecto (`node_modules/typescript/lib`) e imports no relativos.
- **Todo Tree** apunta a `/usr/bin/rg`. Sin esto aparece el error
  *"Failed to find vscode-ripgrep"*. Necesita el paquete `ripgrep`.
- **SQLTools** tiene la conexión *Ventor local* a `${workspaceFolder:ventor}/pos.sqlite`.
  Funciona solo si la carpeta del repo se llama `ventor`.
- Se ocultan `pos.sqlite-shm` / `pos.sqlite-wal` del explorador, y `node_modules`, `dist` y
  `pnpm-lock.yaml` de las búsquedas.
- Fuentes: *Cascadia Code* en el editor y *Cascadia Code NF* en la terminal
  (las instala la opción *Nerd Fonts* del asistente).

---

## Instalación a mano

### 1. Instalar VSCodium y ripgrep

```bash
wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
  | gpg --dearmor | sudo dd of=/usr/share/keyrings/vscodium-archive-keyring.gpg

echo -e 'Types: deb\nURIs: https://download.vscodium.com/debs\nSuites: vscodium\nComponents: main\nArchitectures: amd64 arm64\nSigned-by: /usr/share/keyrings/vscodium-archive-keyring.gpg' \
  | sudo tee /etc/apt/sources.list.d/vscodium.sources

sudo apt update && sudo apt install -y codium ripgrep
```

### 2. Crear el perfil

1. Abre VSCodium.
2. Rueda de engranaje (abajo a la izquierda) → **Profiles** → **New Profile**.
3. Nombre: `Ventor`, ícono: *package*. Elige **Empty** (vacío) y crea.
4. Asegúrate de que el perfil activo sea **Ventor** (aparece abajo a la izquierda).

### 3. Copiar los ajustes

`Ctrl+Shift+P` → **Preferences: Open User Settings (JSON)** y reemplaza todo el contenido
por el de `ventor/settings.json`. Guarda.

> El archivo vive en `~/.config/VSCodium/User/profiles/<id>/settings.json`.
> El `<id>` es aleatorio; el comando de arriba abre el correcto sin tener que buscarlo.

### 4. Instalar las extensiones

Con VSCodium **cerrado** (el perfil ya tiene que existir):

```bash
while read -r ext; do
  [[ -z "$ext" || "$ext" == \#* ]] && continue
  codium --profile "Ventor" --install-extension "$ext"
done < ventor/extensions.txt
```

O una por una desde la vista de extensiones (`Ctrl+Shift+X`) con el perfil Ventor activo.

### 5. Comprobar

```bash
codium --profile "Ventor" --list-extensions   # deben salir las 18
```

Abre `~/projects/ventor`, recarga (`Ctrl+Shift+P` → **Developer: Reload Window**) y revisa
que Todo Tree no muestre el error de ripgrep y que SQLTools liste *Ventor local*.

---

## Actualizar esta carpeta tras cambiar el perfil

Cuando agregues extensiones o cambies ajustes en el equipo actual:

```bash
cd ~/pop-os-setup/perfiles-de-desarrollo/ventor
codium --profile "Ventor" --list-extensions > extensions.txt
```

Y copia el `settings.json` desde **Preferences: Open User Settings (JSON)** con el perfil Ventor activo.
