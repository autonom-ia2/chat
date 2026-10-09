# Preflight AWS — Redis Alfred e allowlist do release 1129

- **Observado em:** 2026-10-08 00:20 UTC
- **SHA esperado e observado:** `d27814313fd96e7bc52266efa6177d7421dc4875`
- **Contas:** Autonomia `1` e Hub2You `18`

Os leitores bounded existentes (`.codex/inspect-browser-operations-flag.py` e `.codex/inspect-browser-backend-isolation.py`) retornaram `ok` nas duas contas. A allowlist de cada runtime correspondeu exatamente à própria conta (`1`/`18`), a flag `INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED` permaneceu `unset`, as sessões estavam presentes e o manager observado estava `healthy`.

Os fingerprints do servidor Redis Alfred foram distintos entre Autonomia e Hub2You. Os valores foram omitidos deste registro; o receipt sanitizado preserva apenas o resultado booleano de isolamento.

Esta rodada foi somente leitura: os comandos SSM executaram diagnóstico bounded, com `publication_performed=false`; não houve `put-parameter`, dispatch, convite, OAuth, SSH ou alteração de flag.

Receipt sanitizado: `.codex/release-1129-redis-allowlist-preflight-20261008.json`.

A ativação Hub continua bloqueada até a confirmação operacional do VPS/manager e nova liberação do executor. A ordem de rollback permanece: se o backend degradar, recuperar primeiro o blue-green e confirmar o target corrente saudável; só depois executar o rollback da flag, pois a guarda do helper exige saúde corrente.
