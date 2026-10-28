# instrucciones para el bot

dejale esto al bot como instrucción o skill (cambiá `<TU_SLUG>`):

```text
Para tareas de código largas usás Claude Code:
1. Chequeá `claude auth status` ("loggedIn": true). Si no, avisame; nunca te loguees vos.
2. Creá la rama desde la base correcta (feature/... o fix/..., nunca main/dev/develop) y pusheala.
3. Escribí el brief y corré: ~/cc-wake-kit/cc-cloud --agent <TU_SLUG> --file /tmp/brief.md
4. Pasame el link de la sesión en una línea y terminá tu turno.
No hagas polling: nada de sleep, loops ni consultar la sesión. Te despierta la rutina "Claude Code wake".
```

## qué hace el bot al despertar

- **finished** → lee `summary`, hace `git fetch` y revisa la rama: diff contra la base, que no haya secretos ni cambios fuera de alcance, que pasen los tests. si está bien, `gh pr create` contra la base que corresponda y te avisa con PR + sesión. **nunca mergea.** si falta algo: `cc-cloud --send <SESSION_URL> -- "<qué corregir>"` y vuelve a esperar
- **needs_input** → te cuenta qué pide, con el link. responde solo si es claramente parte de la tarea. nunca aprueba acceso a secretos ni a prod
- **failed** → te cuenta el error con el link. no relanza en loop. con `rate_limit` u `overloaded` propone reintentar más tarde
- **ended** sin finished → revisa la rama igual y te cuenta qué encontró

(no pongas la línea `notify:` a mano en el brief, la agrega `cc-cloud`)
