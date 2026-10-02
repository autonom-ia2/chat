# WAHA 2026.9.2 — publicação autorizada do lote4

Data: 2026-10-02. Issue #846. PR de candidato #853; PR de publicação #862.

## Aprovação e escopo

Rodrigo autorizou explicitamente merge e deploy nas duas instalações e alertou que cada uma usa um WAHA diferente.
A aprovação abrange a publicação do código revisado. APPLY/backfill e envio de mensagens de teste continuam
dependentes de autorização operacional separada. Nenhum logout, QR ou pareamento integra este procedimento.
R1–R5/N1–N3 e as correções #850/#851/#852 permanecem preservados. Sem alteração de schema, UI ou adapter.

## Lote e revisão

Branch exclusiva: release/2026-10-02-lote4, criada da main ffa7ce96920687f3d4d7d43124b78063006b407e.
PR #853 integrado por squash somente nesse lote: b182e158a9c6d7920443dfcf0f265b24da0a87bf.
Árvore 8540ffaffb08f164731d5454f5aa03dd2f976922 idêntica à do candidato 71ab1bb4b20113f07ffc58551cf2a4375db1f8e3.
Revisões independentes do migrador e das métricas aprovadas no fechamento do candidato.
O commit seguinte deste lote modifica apenas esta auditoria e o aviso de aprovação no plano operacional.
A origem feat/waha-2026-9-2-chatwoot-sync foi mantida no SHA 62af5b0493dda09aba9c764e9e62f58197895f34.

## Validação do próprio lote

Executada no M4, Ruby 3.4.4, Node 24.11.0/pnpm 10.2, banco de teste próprio
chat2you_waha_lote4_20261002 e Redis isolado na porta 6863. Dependências instaladas com lock congelado.

- RSpec: bateria fixa do trem mais união dos caminhos WAHA, Channel::Api, Conversation, listeners,
  reporting_events e controller WAHA. 5582 exemplos, 0 falhas, 12 pendentes; nenhum erro fora de exemplo.
  Saída integral lida. Pendentes: 3 avaliações pagas desativadas e 9 quarentenas anteriores; nenhuma adicionada.
- Vitest: bateria fixa do trem, 133 arquivos e 1354 testes passaram; saída integral lida.
- RuboCop: 19 arquivos Ruby/Rake alterados, nenhuma infração; sem autofix.
- Guia: build e check após bateria, 174 fluxos/171 telas, nenhuma sem explicação, 4 blocos sem rota já existentes.
  Nenhuma alteração gerada no Git.
- Central: exit 0, 175 artigos/171 telas. Saída inteira idêntica, exceto caminho do worktree, à do candidato
  já revisado; os avisos preexistentes não bloqueiam o check local. A trava do PR ainda precisa concluir.
- git diff --check: passou. Hooks normais obrigatórios no commit e push; sem --no-verify.
  Não há JS/Vue alterado para o lint seletivo de email. Não houve avaliação paga.

Logs completos e resultados JSON privados em .codex/waha-lote-validation/, fora do Git.
Redis próprio encerrado após a bateria; nenhuma instância de outros trabalhos foi parada.

## Pré-deploy das duas instalações

Conferência direta de configuração e runtime em 2026-10-02, antes do merge na main.
Perfis AWS existentes, sem troca de secrets/auth: hub2you (354307071110) e financial (140023375763).
Web e worker ativos, imagens e .git_sha ab84a219bdd30f287ed0011ed61d62ec43f1fab4, HTTP local /api 200.

| Instalação | WAHA efetivo em web e worker | Versão GET autenticado |
| --- | --- | --- |
| Hub2You | https://wa-hub.autonomia.site | 2026.9.2 / HTTP 200 |
| Autonom.ia | https://wa-autonomia.autonomia.site | 2026.9.2 / HTTP 200 |

SSM somente leitura: Hub2You 12734906-79a5-44a8-b64c-18f306d54a01;
Autonom.ia dd88c971-7832-4ab8-a463-5749a2867bf2. URLs distintas confirmadas também no SSM de cada conta.
Nenhuma configuração WAHA, sessão, mensagem ou dado de cliente foi alterado nessas conferências.

## Publicação e retorno

Após checks finais do PR #862, um único merge commit na main dispara os dois blue-green automaticamente.
Não executar workflow_dispatch adicional de deploy. Acompanhar cada run por SHA até success e depois conferir
diretamente web/worker, imagem, SHA, targets, saúde pública e preservação dos endpoints distintos.
No momento deste registro, merge na main e publicação ainda aguardam essa etapa; não são declarados concluídos.

Rollback de aplicação: workflow oficial de cada ambiente, action=rollback/confirm_production=true,
com decisão operacional explícita e verificação da instância/imagem anterior. Um degrau apenas; retorno esperado
após este deploy é ab84a219bdd30f287ed0011ed61d62ec43f1fab4. A volta da imagem não desfaz dados de um backfill.

Após ambos os runtimes novos, preparar dry-run restrito à seleção privada do Hub2You, com APPLY=false e ambos
os filtros. Nunca transportar essa seleção para Autonom.ia. APPLY só após revisar o resultado, snapshot privado,
janela sem escritores de Apps e responsável pela restauração. GET/PUT de WAHA não é atômico.
E2E e expansão ficam pendentes do piloto autorizado; nenhuma prova de mock é apresentada como teste produtivo.
