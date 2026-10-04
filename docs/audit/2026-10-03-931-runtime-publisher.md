# #931 — runtime/publisher: correção e evidência local

Data: 03/10/2026. Base desta worktree: `149c6718f2`; branch existente `fix/931-instagram-audit-blockers`. Especialista RUNTIME, trabalhando em arquivos disjuntos com outros agentes. Nenhum commit/ref/push/merge/deploy/Project update executado; integração e review pertencem ao coordenador.

## Arquivos alterados

- `scripts/instagram_testers/session-manager.mjs`
- `scripts/instagram_testers/runtime/publisher-tunnel.mjs`
- `scripts/instagram_testers/runtime/manager-launchagent-wrapper.sh`
- `tests/instagram_testers/session-manager.test.mjs`
- `tests/instagram_testers/runtime-publisher.test.mjs`
- Este registro.

O patch `tmp/instagram-931/codex-local-delta.patch` foi lido, preservado e incorporado no escopo correspondente: `CommandInvocations` e stdin `pipe`. Não toquei na worktree original nem nos workflows bluegreen, fontes SESSION, UI, OAuth ou outros escopos.

## Decisões

1. `list-command-invocations` consulta `CommandInvocations[0]`. A fixture fornece o envelope completo e aplica a chave recebida em `--query`, em vez de devolver diretamente a projeção esperada.
2. O stdin do túnel permanece aberto durante port readiness, host key e SSH; cleanup encerra o processo. Evidência de EOF obtida com child Node local, sem plugin SSM.
3. A leitura `version` faz parte do ciclo recuperável. Falhas de transporte ou CAS aguardam o refresh normal de 15 minutos. Cada refresh lê a revisão novamente e realiza nova navegação/captura; não há replay da captura anterior.
4. O ciclo inteiro tem orçamento de 30 segundos e AbortController: version, navigation, headers, response body, publish e invalidate. SIGTERM/SIGINT cancelam tanto o ciclo como a espera de refresh. Abort chega ao processo publisher e conclui a promise mesmo quando o child simulado não emite exit.
5. Callbacks/corpos antigos não podem iniciar publicação após cancelamento. O finally remove o observer e cancela a operação sem aguardar `publication` pendente. Fechar contexto, fechar lock e remover lock têm, cada um, prazo de 30 segundos; timers/listeners são removidos. No túnel, a remoção de scratch também está submetida ao orçamento/cancelamento existente.
6. `operator_required` fica terminal para login/checkpoint/2FA e HTTP 401/403, inclusive se invalidate travar ou falhar. Navegação e resposta compartilham uma única invalidação. Exit 2 é exclusivo desse estado; erros operacionais de inicialização usam exit 1. O wrapper converte somente 2 em saída limpa e preserva restart para erros operacionais.
7. Contrato SESSION lido em `tmp/instagram-931/session-contract.md`: versão string não vazia ou null, opaca. A revisão de revogação pode substituir a anterior; o cliente não interpreta UUID/timestamp. O teste de CAS recusado confirma leitura da revisão nova e captura nova antes da recuperação. Atualmente SESSION continua emitindo UUIDs; a validação UUID existente no forced publisher não foi alterada, e não bloqueia esse contrato atual.
8. Browser gate e allowed network permaneceram iguais. A fixture nova aplica o handler real da rota à consulta legítima e confirma rejeição de mutações/destinos não permitidos.

## Antes/depois e resultados

- Query: controle sintético nesta rodada troca somente a query na cópia em memória do módulo atual. Original: falha estática após quatro polls/100 ms virtuais. Corrigida: sucesso em um poll/0 ms virtuais. Não houve AWS real.
- Stdin: child Node com stdin ignore recebe EOF e termina; com pipe, permanece vivo até cleanup. Não comprova comportamento do Session Manager Plugin instalado.
- Version/body: a posição da leitura fora do catch e os awaits ilimitados constam da fonte-base e das reproduções do audit-report fornecido. As regressões novas desta rodada exercitam o código corrigido; não apresentamos nova execução do gestor antigo como prova.
- Três ciclos: revisão inicial null, depois duas strings opacas; capturas/publicações espaçadas por 900000 ms virtuais.
- Falha version no primeiro e no segundo ciclo: nenhum retry antecipado; próxima captura recupera e emite status estático de recuperação.
- Deadline e SIGTERM: headers, body, version, navigation e publish pendentes são cancelados. Conclusões antigas são descartadas, inclusive body antigo terminando durante o ciclo novo. SIGTERM remove lock e listeners.
- Cleanup: close do browser, close do lock, unlink do lock e cleanup do túnel pendentes são limitados. Para o túnel, se SSH já respondeu com sucesso antes de cancelamento durante cleanup, o resultado já obtido é preservado; nenhuma nova publicação é iniciada.
- Wrapper: cópia textual com comando real substituído por child Node sintético verifica saídas 0/1/2/3. O teste preexistente do forced wrapper foi restringido a SSH_ORIGINAL_COMMAND sintético não vazio, rejeitado antes de uid/Docker.

**Validação final: 72 testes Node, 72 pass, 0 fail, 0 cancelled, 0 skipped, 0 todo.** São 58 dos dois arquivos do escopo RUNTIME e 14 do observer preexistente, incluídos pela mudança no publisher compartilhado. ESLint dos quatro arquivos MJS: exit 0, sem diagnóstico. `git diff --check` do escopo: exit 0. Prettier aplicado somente aos quatro arquivos do escopo; alterações relidas antes da rodada final.

Comandos finais:

```sh
umask 022
env -i PATH=/usr/bin:/bin TMPDIR=/private/tmp /Users/rodrigosilva/.local/bin/node --test --test-timeout=10000 tests/instagram_testers/session-manager.test.mjs tests/instagram_testers/runtime-publisher.test.mjs tests/instagram_testers/session-observer.test.mjs

env -i PATH=/Users/rodrigosilva/.local/bin:/usr/bin:/bin node_modules/.bin/eslint scripts/instagram_testers/session-manager.mjs scripts/instagram_testers/runtime/publisher-tunnel.mjs tests/instagram_testers/runtime-publisher.test.mjs tests/instagram_testers/session-manager.test.mjs

env -i PATH=/usr/bin:/bin /Users/rodrigosilva/.local/bin/node tmp/instagram-931/runtime-query-control.mjs
```

Logs sintéticos: `tmp/instagram-931/runtime-node-final.log`, `runtime-eslint-results.log`, `runtime-query-control.log`. O umask 022 vale somente para a execução sintética: o teste preexistente cria diretório público 0755 e espera rejeição; o umask herdado 077 tornava essa fixture privada e causou uma falha de setup. Não houve mudança no gate do produto nem skip.

## Ocorrências e bloqueios

A primeira fixture query adicional usou split que também cortava a projeção interna; corrigida para slice no primeiro delimitador. Um teste legado com deadline real de 15 ms falhou sob carga antes do spawn; convertido para relógio virtual. A fixture de cleanup também avançava o relógio antes de a operação de filesystem chegar ao ponto pendente; agora sinaliza explicitamente esse ponto antes de avançar.

Uma rodada anterior ficou pendente nessa fixture antiga (`session_id 16181`, runner observado PID 28537, log `runtime-node-results.log`). Foi tentado apenas `kill -TERM 28537`; o sandbox recusou com `operation not permitted`. Não houve retry nem método alternativo de encerramento. Esse runner sintético antigo continua sem evidência de encerramento; o coordenador deve tratá-lo como pendência local. A rodada final, em log separado e com timeout explícito, concluiu com exit 0.

## Limites e handoff

Nenhum browser, gerente/publisher operacional, plugin SSM, AWS/SSH/Meta real, banco, segredo, instalação, launchd, maccluster ou rede externa foi executado/acessado. As únicas instâncias child reais são Node local com programa sintético; filesystem é temporário sintético ou injetado. Cancelamento impede novas publicações e encerra o transporte iniciado; não desfaz uma escrita que o servidor já tenha aceitado. Não há prova end-to-end, de configuração operacional ou de produção nesta rodada.

Review independente e integração pendentes do coordenador. A condição de rollout dos tombstones legados e suspensão antes de rollback descrita pelo SESSION continua obrigatória no plano do coordenador. Este trabalho não executa nem autoriza essas ações.

## Follow-up do coordenador — fixture de permissões independente de umask

O coordenador executou 72 testes: 71 pass/1 fail em `session-observer.test.mjs:320`, `Missing expected rejection`. A investigação desta rodada confirmou o umask herdado `077`. Reprodução exclusivamente em diretório sintético criado sob `/private/tmp`: mkdir com modo pedido 0755 produziu modo efetivo 0700, aceito corretamente por privateProfile; após chmod explícito 0755, o mesmo validador rejeitou com `private_profile_required`. Evidência em `tmp/instagram-931/runtime-umask-proof.log`.

Mudança adicional autorizada: somente `tests/instagram_testers/session-observer.test.mjs`, importando chmod e aplicando-o à fixture pública antes da assertion de rejeição. Nenhuma mudança em privateProfile ou no restante do código de runtime/publisher nesta rodada. O uso prévio de umask 022 foi apenas uma condição de execução; a fixture agora define a permissão necessária independentemente desse ajuste.

Reexecução final sob **umask 077**, ambiente vazio e TMPDIR de sistema: **72/72 pass, 0 fail, 0 cancelled, 0 skipped, 0 todo**, exit 0. ESLint do arquivo alterado e diff --check: exit 0. Logs: `runtime-umask077-final.log` e `runtime-observer-fixture-eslint.log`, no scratch desta tarefa. Nenhum publisher/browser/SSM/SSH/Meta operacional, serviço, secret ou perfil real foi usado; não houve commit ou produção.

CI: RUNTIME não criou novo testfile de suíte. As regressões estão nos arquivos existentes runtime-publisher.test.mjs/session-manager.test.mjs e a correção de fixture no session-observer.test.mjs. Os três constam explicitamente em `.github/workflows/instagram-tester-onboarding.yml`, conferido somente por leitura; não alterei o workflow. `tmp/instagram-931/runtime-query-control.mjs` é controle sintético auxiliar em scratch, não um novo testfile da suíte/CI.
