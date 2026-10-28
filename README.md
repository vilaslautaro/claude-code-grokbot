# claude-code-grokbot

conectá claude code a tu grokbot sin drive, sin slack y sin servidor en el medio.

claude code es un cli. grokbot tiene una compu con terminal. y cada rutina de grokbot te da un webhook. con eso alcanza:

- el bot lanza la tarea con `claude --cloud`, corre en claude.ai/code con tu plan max (no gastás saldo de cursor cloud)
- el bot termina su turno, no se queda esperando ni hace polling
- cuando claude termina, falla o pide permiso, un hook le pega al webhook de una rutina del bot y lo despierta
- el bot revisa la rama, abre el PR y te avisa. nunca mergea, eso lo hacés vos

```
bot de grokbot --cc-cloud--> sesión de claude code (environment del bot)
      ^                                  |
      |                     hook: Stop / StopFailure / PermissionRequest / ...
      |                                  v
      +---- webhook de la rutina "Claude Code wake" <---- POST con un JSON corto
```

> **no querés hacerlo a mano?** agregá este bot a tu grokbot y te lo configura paso a paso, con prueba incluida: https://x.ai/bot/vnnCeBiOCASkKEs2k_Pp9

## qué hay en el repo

| archivo | qué es |
|---|---|
| [`kit/cc-cloud`](kit/cc-cloud) | lanzador: manda una tarea a claude code en la nube y devuelve el link de la sesión |
| [`kit/cc-local`](kit/cc-local) | fallback local: corre `claude -p` en la compu del bot, en un worktree por tarea |
| [`kit/wake.sh`](kit/wake.sh) | el hook que despierta al bot (lo usa `cc-local`; en la nube va adentro de `setup.sh`) |
| [`kit/settings.json`](kit/settings.json) | los eventos de claude code que disparan el hook |
| [`kit/guardar-key-local.sh`](kit/guardar-key-local.sh) | guarda la URL y la key del webhook para el modo local (lo corrés vos) |
| [`environment/setup.sh`](environment/setup.sh) | setup script del environment de claude.ai/code, con el hook adentro |
| [`environment/README.md`](environment/README.md) | cómo armar el environment (variables, network secret) |
| [`environment/variables.env.example`](environment/variables.env.example) | las dos variables del environment |
| [`templates/rutina-claude-code-wake.md`](templates/rutina-claude-code-wake.md) | prompt de la rutina webhook en grokbot |
| [`templates/brief.md`](templates/brief.md) | el brief que el bot le pasa a claude |
| [`templates/instrucciones-bot.md`](templates/instrucciones-bot.md) | lo que le enseñás al bot (instrucción o skill) |
| [`examples/cloud-envs.example`](examples/cloud-envs.example) | formato de `~/.config/cc-wake/cloud-envs` |
| [`examples/aviso-ejemplo.json`](examples/aviso-ejemplo.json) | ejemplo del JSON que le llega a la rutina |

## qué necesitás

- **grokbot** con su compu (la que tiene terminal y escritorio)
- **claude max** (o un plan que te dé claude code en la web, claude.ai/code)
- **github** con tus repos, y la **claude github app** instalada en los repos que quieras que toque
- `jq`, `git`, `curl` y `script` en la compu del bot (en general ya están)

## paso a paso

### 1. instalar claude code y loguearte (una sola vez)

en la compu de grokbot abrí una terminal **desde el escritorio** (el login abre el navegador, así que hacelo vos, no el bot):

```bash
curl -fsSL https://claude.ai/install.sh | bash
# o: npm install -g @anthropic-ai/claude-code
claude auth login
```

elegí **Claude account with subscription**, entrás con tu cuenta max y autorizás. verificá con `claude auth status` (tiene que decir `"loggedIn": true`).

regla: el bot nunca se loguea solo. si `claude auth status` no da `loggedIn`, te avisa y lo hacés vos.

### 2. github para la nube

la sesión de la nube clona y pushea el repo, así que necesita acceso:

- **claude github app** (la recomendada, acotada): claude.ai/code → conectar github → instalala solo en los repos que quieras
- `/web-setup` dentro de `claude`: manda el token de `gh` de esa compu a tu cuenta de claude. ojo que ese token suele tener scopes muy amplios

si el repo es de otra persona, la app la tiene que instalar el dueño (o usás `/web-setup` si sos colaborador).

### 3. la rutina webhook en grokbot

cada bot que use claude code necesita una rutina suya con trigger **webhook** ("Claude Code wake"). el prompt está en [`templates/rutina-claude-code-wake.md`](templates/rutina-claude-code-wake.md). grokbot te da una **URL** y una **key**: no las pegues en ningún chat, van directo al paso 4.

### 4. un environment por bot en claude.ai/code

seguí [`environment/README.md`](environment/README.md): dos variables ([`variables.env.example`](environment/variables.env.example)), la key como network secret tipo Bearer y [`environment/setup.sh`](environment/setup.sh) pegado entero en "Setup script".

después anotá el id del environment en la compu del bot: `claude` → `/remote-env` → elegí ese environment (guarda su `env_...` en `~/.claude/settings.json`). copialo a `~/.config/cc-wake/cloud-envs` con el formato de [`examples/cloud-envs.example`](examples/cloud-envs.example). sin esa línea la sesión corre en el environment por defecto y el aviso no le llega a tu bot.

### 5. el kit en la compu del bot

```bash
git clone https://github.com/vilaslautaro/claude-code-grokbot.git
cp -r claude-code-grokbot/kit ~/cc-wake-kit
```

`cc-cloud` se encarga de las dos mañas de `claude --cloud` cuando lo corre un bot: la pseudo-TTY (lo envuelve en `script`) y el diálogo "trust this folder" (lo pre-acepta en `~/.claude.json`). además pone `notify: <slug>` en el prompt y elige el environment del bot.

```bash
cd <TU_REPO>
git checkout -b fix/<tarea> && git push -u origin fix/<tarea>   # la nube clona el remote, no tu copia local
~/cc-wake-kit/cc-cloud --agent <TU_SLUG> --model sonnet --file /tmp/brief.md
# seguir una sesión:
~/cc-wake-kit/cc-cloud --send <SESSION_URL> -- "te faltó el test del caso vacío"
```

si la salida trae `warning`, la rama no estaba pusheada.

### 6. el brief y las instrucciones del bot

- brief: [`templates/brief.md`](templates/brief.md)
- instrucción o skill para el bot, y qué hace al despertar: [`templates/instrucciones-bot.md`](templates/instrucciones-bot.md)

cuando la sesión termina, a la rutina le llega algo como [`examples/aviso-ejemplo.json`](examples/aviso-ejemplo.json). `kind` puede ser `finished`, `failed`, `needs_input` o `ended`. el bot revisa la rama, abre el PR y te avisa. **nunca mergea.**

tip: yo tengo un bot "claude code" y los otros bots le pasan laburo a él. así hay un solo environment y una sola rutina que mantener.

## fallback local (`cc-local`)

si la nube no sirve, [`kit/cc-local`](kit/cc-local) corre `claude -p` en la compu del bot, en un worktree propio por tarea (`~/cc-worktrees/...`) y en segundo plano, con el mismo hook cargado por `--settings` (no toca tu `~/.claude/settings.json`).

en local no hay proxy que agregue la key, así que la guardás vos en un archivo modo 600 con [`kit/guardar-key-local.sh`](kit/guardar-key-local.sh) (`~/cc-wake-kit/guardar-key-local.sh <TU_SLUG>`, la key se tipea oculta).

```bash
~/cc-wake-kit/cc-local --agent <TU_SLUG> --dir <TU_REPO> --branch fix/<tarea> --base develop --file /tmp/brief.md
```

ojo: en `-p` no hay diálogos, los permisos no aprobados se niegan solos (corre con `--permission-mode acceptEdits`, cambialo con `CC_LOCAL_PERMISSION_MODE`). si claude se muere de golpe (OOM, kill) no llega aviso, mirá el log que devuelve.

## problemas conocidos

- **se cuelga el primer lanzamiento**: es el diálogo "trust this folder". `cc-cloud` lo pre-acepta. si igual cuelga, mirá el `log` que devuelve
- **"no encontré el link de la sesión"**: no llames `claude --cloud` directo desde el bot, necesita la pseudo-TTY que pone `cc-cloud`
- **no llega el aviso**: la sesión corrió en otro environment (falta tu `env_...` en `cloud-envs`), falta `WAKE_URL` o `NOTIFY_AGENT`, o el network secret no está cargado para el dominio del webhook. el log del setup script avisa si faltan las variables
- **cambiaste el hook y no pasa nada**: volvé a pegar `setup.sh` en cada environment y lanzá una sesión nueva
- **la nube solo pushea ramas**: no crea tags ni borra ramas. el PR y el merge quedan de tu lado
- **probar sin mandar nada**: `WAKE_DRY_RUN=1` en el environment hace que el hook imprima el aviso en vez de mandarlo

## licencia

MIT, ver [`LICENSE`](LICENSE).
