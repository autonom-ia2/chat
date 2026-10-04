# Atlas — integração dos fixtures Node

Escopo: somente fixtures e este registro; nenhuma edição de produto. Alterações preexistentes do worktree preservadas. Nenhuma consulta autenticada, SSH, rede externa, Rails ou banco executados.

Incluído `INSTAGRAM_TESTER_PROXY_IDENTITY=93.184.216.34:8080` no `baseEnv` de `session-manager.test.mjs` e no `env` de `operator-control.test.mjs`, igual ao upstream sintético do observer. Guards e assertions preservados. A assertion do manager já deriva o fingerprint de `configuration(data.env)`; nenhum fingerprint arbitrário foi introduzido.

Validação executada com timeout de 90 segundos por comando, sem TMPDIR adicional:

```sh
timeout 90s bash tmp/release-three-gates/run-local.sh node --test tests/qa/instagram-testers/fixtures.test.mjs tests/qa/instagram-testers/evidence.test.mjs tests/qa/instagram-testers/visual-helpers.test.mjs tests/qa/instagram-testers/toast-helpers.test.mjs tests/instagram_testers/session-observer.test.mjs tests/instagram_testers/session-manager.test.mjs tests/instagram_testers/runtime-publisher.test.mjs tests/instagram_testers/operator-control.test.mjs
timeout 90s bash tmp/release-three-gates/run-local.sh python3 -B tests/instagram_testers/coordination-runtime_test.py
bash tmp/release-three-gates/run-local.sh ruby --version
git diff --check -- tests/instagram_testers/session-manager.test.mjs tests/instagram_testers/operator-control.test.mjs
```

Resultados: Node 135 testes, 135 aprovados, zero falhas/cancelados/skipped; Python 10 testes aprovados em 3,384 segundos, incluindo comparação de fingerprint Ruby/Node e preflight com transportes sintéticos. Runner confirmado com Ruby 3.4.4. Diff check aprovado.

A primeira tentativa Python com `unittest discover` carregou zero testes pelo nome com hífen; não foi considerada validação. A execução direta acima carregou e aprovou os dez testes. Aviso do Python sobre DARWIN_USER_TEMP_DIR: fallback para `/tmp`, sem alteração de TMPDIR.

Logs locais: `tmp/release-three-gates/atlas-node-contracts.log` e `tmp/release-three-gates/atlas-coordination-runtime.log`. Nenhum merge, deploy ou provisão real realizado.
