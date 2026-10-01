# Liberação das campanhas e biblioteca — #800 — 01/10/2026

## Autorização e escopo

Rodrigo autorizou: “pode fazer”, após a explicação de merge/deploy nas duas plataformas e restauração dos 14 modelos. Esta autorização cobre a publicação do PR #801, a conferência produtiva e o snapshot/seed limitado aos 14 registros globais do catálogo. Não inclui envios reais nem edição de campanhas/modelos próprios de clientes.

Lote exclusivo `release/2026-10-01-lote1`, partindo de main `91f8899ff33cf5bf108f28344b88fb95a149400b`. PR #801 foi marcado pronto, retargetado e integrado por squash em `99d81ab1f324299fb630e068101fe072bdb4484e`. Nenhum merge na main ou deploy dessa entrega nessa etapa. Checkout principal preservado. Sem migration, dependência nova, mudança de credencial, política SES ou infraestrutura.

## Evidências antes do lote

HEAD aprovado `f55227a492d1ddcbe97fcfc75e5e649d3081bc41`: [CI de e-mail 36786741192](https://github.com/autonom-ia2/chat/actions/runs/36786741192), [traduções 36786740977](https://github.com/autonom-ia2/chat/actions/runs/36786740977) e [Guia/Central 36786747901](https://github.com/autonom-ia2/chat/actions/runs/36786747901) concluíram com sucesso. Saída lida: **6891 testes frontend em 618 arquivos, 1063 exemplos Ruby, zero falhas**, dois pending em quarentena preexistente; lint cumulativo sem bloqueios, Prettier, build e navegador isolado (215 verificações, zero falhas) aprovados. Execuções anteriores canceladas do Guia foram substituídas pela última verde no mesmo HEAD.

QA independente `/root/qa_800` aprovou telas completas, alinhamento nas cinco larguras, catálogo/rodapés/idempotência e integração sem conflito com main. A observação de PR draft ficou superada ao marcar #801 pronto antes do squash.

## Publicação anterior e rollback

Deploy anterior main `91f8899` concluiu com sucesso em [Hub2You 36784374947](https://github.com/autonom-ia2/chat/actions/runs/36784374947) e [Autonom.ia 36784374924](https://github.com/autonom-ia2/chat/actions/runs/36784374924). SSM runtime-image confirma esse SHA nas duas contas. Os parâmetros current/previous foram registrados privadamente como destinos de rollback. Perfis existentes hub2you (354307071110) e financial (140023375763) confirmados; perfil default inválido não é utilizado e nenhuma credencial foi alterada.

Plano: um merge commit do lote na main inicia os workflows blue-green existentes. Conferir web/worker, revisão, target groups e HTTPS. Na imagem nova, fazer snapshot seguro dos registros globais, executar uma vez `bundle exec rails email_campaign_templates:seed`, conferir os 14 nomes únicos/rodapés e fingerprints dos modelos próprios antes/depois. Snapshot somente dos globais; conteúdo de contas não é exportado. Navegador conta 16 em leitura, incluindo biblioteca, lista, editor e revisão.

Rollback: `workflow_dispatch` com `action=rollback` e `confirm_production=true` nas duas stacks, retornando à instância imediatamente anterior. Sem schema a reverter. Catálogo global independente da UI pode permanecer; se houver necessidade de restauração, usar o snapshot limitado aos campos dos globais existentes, sem exclusão automática de novos modelos ou alteração dos próprios.

## Gates do lote

Regressão de integração executada em banco local novo `email800_release_union`, PostgreSQL em 127.0.0.1:55779 e Redis isolado; sem consultas pagas. Resultados e checks do HEAD integrado serão registrados antes do merge na main.

## Validação do HEAD integrado

[CI de integração 36839673873](https://github.com/autonom-ia2/chat/actions/runs/36839673873) terminou verde no HEAD `99d81ab1f324299fb630e068101fe072bdb4484e`: 6891 testes frontend/618 arquivos, 1063 exemplos Ruby/zero falhas/2 pending preexistentes, 215 verificações no navegador/zero falhas/153 capturas sintéticas, 57 módulos de idioma compilados/renderizados, build e lint aprovados. Fork i18n 36839673895 e Guia/Central 36839673927 verdes.

Lint local: 15 arquivos frontend/zero bloqueios/123 avisos permitidos de chaves dinâmicas; Prettier aprovado; 9 arquivos Ruby/zero offenses. Guia: 169 fluxos/170 telas/zero sem explicação. Central: check exit 0/174 artigos/170 telas, com referências antigas pendentes de revisão e deslocamentos de linha já tratados como avisos pela trava. Nenhum gerado mudou.

A primeira rodada local completa de Vitest não fixou TZ e apresentou 19 diferenças de UTC-3 versus UTC. QA repetiu os seis arquivos afetados com TZ=UTC: 186 testes/zero falhas; o CI integrado repetiu todos os 6891 com UTC/zero falhas.

A primeira bateria Ruby ampliada executou 5960 exemplos/uma falha por FRONTEND_URL local HTTP versus expectativa HTTPS do SES. A repetição de 6210 exemplos no mesmo banco apresentou três falhas de contagens globais (16 eventos de supressão e 13 auditorias). Os testes de concorrência sem transação conservam eventos/auditorias imutáveis; reutilizar a base ou apendar modelos globais após esses casos contamina as expectativas. QA independente repetiu exatamente os três arquivos em `email800_qa_isolation` novo: 63 exemplos/zero falhas. A execução intermediária limpa mas ainda com seleção apendada foi interrompida apenas no processo local identificado, antes de completá-la; 3767 exemplos executados/zero falhas não foram usados como aprovação da bateria inteira. Rodada final usa os mesmos 582 arquivos distintos em ordem canônica e banco novo `email800_release_canonical`, com TZ=UTC e FRONTEND_URL=https://example.test. Nenhum teste foi excluído nem reescrito para obter aprovação.

Operação do catálogo validada localmente no HEAD integrado: snapshot privado e seed idempotente, 14 nomes únicos/MJML/HTML/categorias/rodapés conferidos, fingerprint de todos os campos dos próprios preservado (incluindo thumbnail_url). QA operacional aprovado. Parâmetros SSM exigem SHA exato e comparam checksum da cópia no host antes do seed; não carregam credenciais nem conteúdo de contas.

Resultado final da união em base nova e ordem canônica: **6210 exemplos, zero falhas, 11 pending**, em 8m39s. Oito quarentenas preexistentes e três evals pagas fora da rodada; sem custo de inferência. As três falhas globais anteriores desapareceram sem alterar produto ou specs. Guia build/check e Central repetidos por último, sem diff nos gerados.

## Merge

PR #805 mergeado com merge commit `a5bf00d1c179c775d99ebba749d46665dffeaa3f` em 2026-10-01 09:29 UTC. A árvore publicada é idêntica ao HEAD integrado aprovado (git diff sem diferenças). QA final aprovou depois de ler a união verde; último Guia/Central do corpo final, run 36842870885, também verde. main anterior ainda era 91f8899 e nenhum deploy anterior estava rodando. Blue-green automático iniciado: Hub2You 36843036111 e Autonom.ia 36843036153.

## Publicação concluída

Ambos os workflows finalizaram com **success**, no SHA `a5bf00d1c179c775d99ebba749d46665dffeaa3f`: [Hub2You 36843036111](https://github.com/autonom-ia2/chat/actions/runs/36843036111), [Autonom.ia 36843036153](https://github.com/autonom-ia2/chat/actions/runs/36843036153). Web e worker usam a revisão publicada, target groups atuais healthy e HTTPS responde com o redirecionamento SSO esperado. Leitura limitada via SSM confirmou esses estados; não foi necessário rollback. A instância imediatamente anterior foi preservada pelo fluxo existente.

Snapshot antes de qualquer seed, arquivo exclusivo com permissão 0600 e checksum verificado entre container e host. Caminho privado em cada stack: `/opt/chatwoot/backups/email800/a5bf00d1c179/globals-before.json`. Conteúdo do snapshot não foi anexado nem exportado.

| Plataforma | Globais antes/depois | Nomes únicos | Rodapés protegidos | Modelos próprios preservados                    |
| ---------- | -------------------- | ------------ | ------------------ | ----------------------------------------------- |
| Hub2You    | 0 → 14               | 14           | 14                 | 9, fingerprint de todos os campos idêntico      |
| Autonom.ia | 0 → 14               | 14           | 14                 | 0 existentes; nenhum registro de conta alterado |

Operações SSM concluídas com Success/code 0: snapshot Hub2You `8ed59429-c8b0-4283-a256-8360014d4c32`, seed Hub2You `0377ce36-f71c-4bb9-9bb2-0f53b3167ada`, snapshot Autonom.ia `2b80c22c-083b-4c1a-b8a6-58120a06cecb`, seed Autonom.ia `80b37a18-0322-45f0-87e9-a13071f57ac1`. O seed foi executado uma vez por plataforma, em transação, com verificação de MJML/HTML/categoria e fingerprint dos próprios.

### Conferência visual produtiva

Conta 16 em `chat.hub2you.ai`, aba separada da aba ativa do Rodrigo: lista com ação de envio e colunas alinhadas visualmente, biblioteca com 14 globais e dois próprios acessíveis, prévia Desktop/Mobile, editor do rascunho de teste e revisão com público zero e orientação para completar o e-mail. Nenhum clique em confirmar envio, salvar, usar modelo, importar ou reavaliar endereços. Não houve alteração de campanhas.

Capturas reais completas em `/Users/rodrigosilva/Documents/Codex/Entregas/2026-10-01-campanhas-publicadas/`: `01-campanhas-producao.jpg`, `02-biblioteca-producao.jpg`, `03-editor-producao.jpg`, `04-revisao-producao.jpg`, `05-modelo-desktop-producao.jpg`, `06-modelo-mobile-producao.jpg`, `07-modelos-proprios-producao.jpg`. Sidebar e marca vêm da aplicação; não há shell substituto. O perfil estava em inglês e não teve seu idioma alterado. Português e inglês foram validados no código/CI anterior; não se confundem essas provas com uma captura produtiva em português.

Na Autonom.ia, revisão, serviços, target group, HTTPS de `agents.autonomia.site` e catálogo foram confirmados operacionalmente. Não houve conferência visual autenticada do dashboard dessa plataforma; as capturas pertencem à Hub2You. Envios reais, edição/salvamento e agendamento em produção não fazem parte desta conferência; seus fluxos foram testados localmente/CI.

Issue #800 fechada pelo lote #805. Evidências de release, catálogo e QA preservadas na entrega local. Registro final é documental e não modifica o runtime publicado.
