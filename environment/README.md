# environment de claude.ai/code (uno por bot)

claude.ai/code → selector de environment (abajo de la caja de mensaje) → **New environment**:

- **Name**: `cc-<TU_SLUG>` (el nombre que quieras)
- **Network access**: Trusted
- **Environment variables**: copiá [`variables.env.example`](variables.env.example) y completá los dos valores
- **Network secrets → Add secret**: tipo **Bearer**
  - Allowed websites: solo el dominio de `<TU_WEBHOOK_URL>`
  - Header: `Authorization`, prefijo `Bearer`
  - Value: `<TU_WEBHOOK_KEY>` (la key de la rutina "Claude Code wake")
- **Setup script**: pegás entero [`setup.sh`](setup.sh)

por qué así: el proxy de anthropic agrega el header `Authorization` **después** de que el request sale de la VM. la key nunca entra a la sesión, ni al código, ni al chat. y como los network secrets matchean por dominio y todas las rutinas comparten dominio, un environment no puede tener las keys de varios bots. por eso es uno por bot.

opcionales (casi nunca hacen falta): `WAKE_SUMMARY_MAX` (default 4000, `0` apaga el resumen), `WAKE_TIMEOUT` (segundos por intento, default 8), `WAKE_DRY_RUN=1` (imprime el aviso en vez de mandarlo).

**importante**: si cambiás el hook, tenés que volver a pegar `setup.sh` en cada environment. las sesiones que ya están abiertas siguen con el hook viejo, así que lanzá una nueva.
