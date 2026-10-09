# Publicação autorizada — Issue #995 / PR #1129

## Autorização e escopo

Rodrigo autorizou explicitamente o merge do head `423f5b767fdb8467de86584b7b7538640982a924`, os dois deploys AWS, a instalação na VPS e a ativação do piloto Hub2You, conta 18, @placementseg. A aprovação ocorreu no chat antes da operação, em 07/10/2026. Os 26 checks do head estavam aprovados.

Autonom.ia recebe o código com a opção nova desligada. O @ informado não retornou candidato exato na busca anterior; não substituí-lo por conta aproximada. Não encerrar #995 antes dos aceites reais de conexão e reconexão. Nenhum destinatário de DM foi autorizado.

Plano aprovado: `docs/audit/995-browser-operations-release-plan-20261007.md`, SHA-256 `3c0d06221ec98653003f5fd522a06328b575ffc13e69318b4c17154dcdcd6104`.

## Merge e dois deploys iniciais

A fila normal concluiu a PR em 08/10 às 00:06:20 UTC, mergeCommit `d27814313fd96e7bc52266efa6177d7421dc4875`, parents caca5eae + 423f5b7. RSpec agregado, Vitest, trava, central e fork-i18n passaram na fila. Sem bypass, force push, rebase ou merge manual. Os arquivos Instagram no merge conferem com os hashes revisados.

O push disparou automaticamente Hub2You run [37705954598](https://github.com/autonom-ia2/chat/actions/runs/37705954598) e Autonom.ia run [37705954604](https://github.com/autonom-ia2/chat/actions/runs/37705954604). Ambos concluíram com success. Não houve dispatch duplicado.

Verificação independente às 00:22:08 UTC: web e worker de ambas as stacks running, SHA completo d278, CURRENT running, target healthy e listener apontando exclusivamente ao CURRENT. Gates e allowlists exatas 1/18 preservadas; opção nova unset. O previous está stopped, registrado e distinto. Ele precisa ser iniciado e ter saúde validada pelo workflow antes de promover tráfego em uma reversão.

Comandos de leitura efetivamente utilizados:

- `gh run view <run> --repo autonom-ia2/chat --json status,conclusion,jobs` com projeção reduzida.
- `python3 .codex/verify-release-1129-health.py --expected-sha d27814313fd96e7bc52266efa6177d7421dc4875 --expected-browser-operations-flag unset --receipt .codex/release-1129-aws-postdeploy-health.json`
- `python3 .codex/inspect-browser-operations-flag.py`

O verifier atual tem SHA `aa2a45beebfd087a3a808a136141b3cc7ca34f6f2c537ff2916d7d3455be8fea`. Recibos privados não contêm valores de credenciais.

## Instalação VPS

Preflight, stage e prepare preservaram a release anterior `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26`, oito units ativas/enabled, perfis e recursos. Pacote imutável d278: SHA `7fc09488f72370eeaa7ad97716c7701300b5b6d000edc64ef63d19904b98af12`, 42 arquivos e dependências verificadas.

Após AWS saudável e revisão operacional, as oito units Instagram foram drenadas. O código foi instalado enquanto elas estavam inativas; depois o conjunto anterior foi retomado. Estabilidade de 10 s passou. Readback às 00:21:13 UTC: CURRENT d278, oito units active/running/enabled, NRestarts=0, caps/drop-ins preservados, perfis e locks exclusivos, sem marcador humano. Nenhum n8n, Traefik, Redis, DNS, IAM ou quota foi alterado.

Helper de release efetivamente executado: `5d09ecf5eec099a601bcaa2585b591de49dcebb155197dca15263a4b198b5039`. Ele inclui o parser de ControlGroup escapado; o hash 5fa363 anterior não é a fonte executada. Browser executor instalado: `c115b10c1a9f1934f7504e4c9823c0e3e048bd4a0988dbcc93031c5da024e354`.

Recibos: `.codex/release-1129-stop-001944169919.json`, `install-002013137906.json`, `resume-002032362471.json` e `release-1129-vps-after-resume.json`. Auditoria detalhada e proveniência: `docs/audit/995-release-1129-vps-preparation-20261007.json`.

Leitura AWS às 00:21:43 confirmou capturas novas após resume em ambas as stacks, publicações e heartbeat posteriores, sessões available/active e managers healthy, sem request/control. Leitura Redis/allowlist às 00:20 UTC confirmou Alfred fisicamente separado por stack e allowlists exatas; fingerprints omitidos.

## Ativação do manager Hub2You

Primeira tentativa, helper `1e6071c4740178650fb3d4e145efefd767ee0277046eea59786415038e4d0333`: check imediato após start retornou hub_browser_not_running. Rollback foi verificado, flags ficaram ausentes e oito units voltaram saudáveis. A falha ocorreu antes de qualquer operação Meta.

Candidato f6b599, com espera limitada de Chrome e decode do ControlGroup, foi recusado por activation_backup_exists antes de escrever flag. O backup da reversão anterior permaneceu íntegro. Isso não foi um segundo convite nem um resultado Meta incerto.

Correção mínima revisada por Nexo: reutilizar o mesmo backup somente com diretório root 0700, arquivos root 0600, não-symlink, hashes old/new exatos e bytes iguais ao env atual; qualquer conflito aborta. Espera de Chrome limitada a 45 s e guards de PID/cgroup/lock/marker/rollback preservados. Candidato executado após preflight fresco: `ec2cdfd2e076f6bb3afa6b4d6300f91528822930448b27972656e4692acf0615`.

Apply às 00:26:48 concluído com sucesso. Readback 00:27:30: manager Hub flag literal true, Autonom.ia absent, oito units saudáveis, outras sete inalteradas, caps/drop-ins/perfis preservados, bootstrap C115 e pacote correto. Backup anterior reutilizado com integridade comprovada.

A leitura das 00:27:08 era recente, mas ainda mostrava a captura antiga. Não foi usada como prova de transporte após ativação. O reader das 00:28:15 confirmou Hub captura 00:26:52, publicação 00:27:13 e heartbeat 00:27:26, posteriores à ativação, available/active/healthy, sem request/control. ACK separado não é persistido pelo publisher; não foi inventado.

Leitura VPS 00:31:42: oito units saudáveis, NRestarts=0, zero eventos err..alert no journal desde ativação, markers humanos ausentes e bootstrap C115. Isso comprova saúde operacional, não convite/OAuth/conexão.

## Flag backend Hub e publicação exclusiva

Writer revisado: `3c65b14cbf3c4171fb2edf3d4745ca7ac920d643e04a89b16bdb733aa730004d`. Dispatcher revisado: `7059d873d61c202edcd30be803b5c0e8de5e2d0db4cbb173ac3e583175e363d3`. SHA40 exato, rollback byte a byte LF/CRLF/sem newline final, recibo gravado antes do readback e vínculo do rollback ao expected_sha foram verificados offline. O rollback SSM exige CURRENT saudável; se o backend degradar, recuperar primeiro via blue-green e só então reverter SSM.

Após manager e transporte saudáveis, Atlas aplicou somente o overlay Hub, versão SSM 9→10, flag true. Readback confirmado; gates, outras linhas e metadados preservados. Main e head exatos d278, sem run Hub concorrente antes do dispatch. Um único workflow foi disparado: [37708017246](https://github.com/autonom-ia2/chat/actions/runs/37708017246). Autonom.ia e restart manual web/worker ficaram fora do bloco.

Às 00:34:46 o run exclusivo Hub estava na troca de workers. Ainda falta comprovar flag literal nos containers e saúde/tráfego do novo CURRENT antes do piloto.

## Baseline do piloto e pendências

Reader readonly revisado por Nexo: `.codex/inspect-hub2you-browser-operation-pilot.py`, SHA `62958a0da4d7c2874b3292a6f57f6039c3f8a2d66c1337c8b42ac7931142fedd`. Ruby watchdog 35 s, SSM 40 s, polling 50 s; scope Hub18/SHA40/provider_name placementseg, DTO sanitizado sem payload, token, cookie ou IDs de operação.

Comando executado: `python3 .codex/inspect-hub2you-browser-operation-pilot.py --expected-sha d27814313fd96e7bc52266efa6177d7421dc4875`.

Baseline 00:29:52: runtime d278, sessão active/available/healthy, zero operations e zero canais com provider_name placementseg na conta 18. Backend ainda unset nessa leitura. Nenhum convite, OAuth, caixa ou reconexão real foi comprovado até esta entrada. #995 permanece aberta.

O aceite deverá registrar busca exata, status fresco, convite só se absent, aceitação pelo titular quando solicitada, OAuth e caixa conectada. Consulta repetida não deve duplicar POST. Unknown após write_started mantém o marcador e não autoriza reenvio. Recuperação administrativa e reconexão da caixa são aceites separados.

## Runtime ativado e tráfego verificado — 00:36 UTC

Leitura durante a troca às00:36:14 falhou fechada; não foi aceita como health. Após run avançar para limpeza, verifier00:36:50 confirmou CURRENT/listener/target saudáveis nasduas stacks, web+worker d278: Hub flagtrue, Autunset. Reader00:36:52 confirmou Hub browser_operations_runtime_enabledtrue, allowlist18 exata, sessãoavailable/active/healthy,0ops/0canaisplacementseg. O run segue limpeza programada da versão anterior; piloto pode começar comtráfego novo jácomprovado e semoutraoperação emcurso.

Root recarregou somente aba do painel autorizada conta18; ação Meta ainda não realizada nesta entrada.

## Piloto real: busca enfileirada, transporte falha antes da Meta

Root executou uma busca placementseg pela UI autorizada conta18 após runtime/tráfego verificados. Readers00:37:33 e00:38:51:1search queued, queue1, running/ready/failed0, semclaim/permit/outcome; backendflagtrue,allowlist18,managedsessionactiveavailablehealthy. A UI permanece Buscando perfil. Nenhum convite/OAuth foi acionado.

Iris provou no processo filho real session-manager.mjs: RUNTIME_MODE=vps e BROWSER_OPERATIONS_ENABLEDtrue, sourcecurrentd278/C115. Assim, hipóteseflagbootantiga descartada. Journal completo desde00:36:50:7eventos instagram_browser_operation_failed empriorityinfo. A leitura anterior de warnings/erros0 não capturava esses eventos. Poll ativo,15s, refresh13min, budget120s; loggenérico não distingue read/parse/claim. Falha situada antes do claim persistido, não constitui resposta/rejeição Meta. Atlas investiga retorno real do caminho read semconsumir/claimmanual.


## Falha do piloto e recuperação — 2026-10-08 UTC

A busca real da conta 18 expirou sem claim/permit/escrita; o painel terminou com integração indisponível. Diagnóstico live confirmou que `Redis::Alfred` não oferece `zrange`/`zrem`, embora a conexão Redis ofereça ambos. Causa anterior a Chrome/Meta. Não houve convite, OAuth ou DM.

Rollback autorizado: manager Hub flag ausente, oito unidades saudáveis e perfis/caps preservados; backend overlay Hub SSM versão 11 com flag ausente e readback. Falta concluir carga da flag ausente no runtime AWS. Autonom.ia continua off.

Correção: PR #1134, head `ca7e158040e56532f9500ca41df585d5504579d4`, somente duas chamadas via conexão `Redis::Alfred.with`. Harness com Redis real/fachada real/pool 1 reproduziu o erro em d278 e passou dez verificações na correção. Revisão independente Nexo aprovada; CI em andamento; nova publicação depende de aprovação deste head posterior.


Às 01:00:04 UTC, a verificação direta dos dois ambientes aprovou web e worker rodando, source d278, listener correto, target atual saudável, gates administrativos preservados e flag browser operations ausente. A execução de recuperação `37710013024` é Deploy Green (Rollback skipped); ainda aguardava a limpeza final do alvo anterior, portanto esta leitura não é apresentada como conclusão do workflow. A tentativa anterior `37709754257` falhou em `instagram_recovery_suspension_failed` antes da troca de listener; o código desse caminho pára o worker atual antes de recuperar o anterior, razão pela qual o caminho foi substituído pelo deploy normal e a disponibilidade foi revalidada.

PR1134 head ca7e158: 26 checks concluídos, 24 success e duas verificações de e-mail fora do escopo skipped. Nenhuma falha. Revisão independente e plano mínimo aprovados; nova autorização para merge/publicação solicitada ao Rodrigo. Nenhum merge/publicação da correção feito ainda.


Conclusão da desativação: run `37710013024` terminou **success**, Deploy Green success / Rollback skipped. Leitura direta às 01:05:05 UTC aprovou ambos os ambientes, web+worker d278, targets atuais saudáveis, listeners corretos, flags ausentes; instâncias anteriores paradas/registradas, sem alegar que o alvo de rollback já esteja saudável. Manager Hub permaneceu off e VPS/perfis preservados. Recibos públicos locais sanitizados: `995-browser-operations-disable-workflow-20261008.json` e `995-browser-operations-disable-health-20261008.json`. Project atualizado. PR1134 continua aberto no head ca7e158; merge/deploy do fix aguardam nova aprovação.
