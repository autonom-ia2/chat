# Correções globais em 09/10 — código aprovado, validação final pendente

Este estado prevalece sobre os registros históricos abaixo. Rodrigo autorizou G01–G06 depois da auditoria de dez frentes. As seis correções foram implementadas com frentes separadas de criação, interface e gate Ruby; depois foram usados especialistas de ambiente, QA e revisão. Relatório atualizado: `docs/audit/2026-10-09-agentes-global-correcoes.md`.

O mesmo revisor encontrou na R1 um spec de integração ainda preso ao painel antigo. Ele foi migrado para a rota nova. A R2 aprovou código e JavaScript sem novo P0–P2; não há R3/R4 de código. Validação atual:227 testes em40 arquivos,0falhas; ESLint focal0erros/159avisos e integração0/0; traduções13catálogos/21.238mensagens; Guia196fluxos/189telas/0sem explicação; Vite compilou em40,90s. Depois da formatação do spec de integração, seus8 testes foram reexecutados com0falhas — já estão incluídos nos227. Sintaxe Ruby aprovada; não é RSpec.

O núcleo da correção tem20 arquivos diferentes da fonte80. Manifesto `input-final.json`, SHA do conjunto `8973a6594b53c8d76586bd71042873d775175d5c2d4872e7862e9c73664315a2`, em `.codex/preview/global-correcoes-20261009/`. HEAD permanece532a5b7b; não confundir commit da base com hash dos inputs. Os implementadores escreveram regressões antes do código, mas RED integral não foi executado: não inventar essa prova.

RSpec final e novas capturas reais não foram executados. O CLI atual do MacCluster recusa os manifestos v1 dos snapshots79/80 com `legacy-workspace-checksum-requires-review` e exigev2/`sha256-workspace-v2`. Não há migração, repin ou permissão de legado na CLI. `prepare` não migra; `snapshot --name` sempre cria novo ID; nenhum snapshot v2 equivalente estava disponível no M2. Não editar marker à mão, contornar gates ou copiar checkout ativo. A regra `/dev/AGENTS.md` de09/10 exige reuso da cópia da entrega; é necessário resolver a compatibilidade oficial antes de Ruby/browser. Prévias, snapshots e bancos anteriores foram preservados; limpeza continua no outro chat.

Próximo passo: destravar reuso oficial compatível, aplicar os20 inputs com hashes, executar RSpec e QA com APIs reais/banco sintético, recapturar somente estados afetados em desktop/celular e claro/escuro, depois mostrar ao Rodrigo. Aceite visual anterior F5–F7 mantido. Não reaplicar G01–G06 nem repetir dez auditorias. O novo `globalCorrecoes.spec.ts` e o plano QA são preparatórios: sintaxe TypeScript aprovada; typecheck sem dependências; nenhuma jornada ou PNG novo aprovado. F1 e GESTAO usam processos e manifestos separados.

Project3 atualizado; item permanece em Ajustes por runtime/aceite visual pendentes. Não houve PR, commit, push, fila, merge, deploy, produção, SQL, provedor pago ou migration neste bloco. Código aprovado não autoriza release; CI não executou. Automação coordena fila/deploy. Só “pode enfileirar” permite `gh pr merge --match-head-commit <SHA>`; sem push depois de pedir vaga.

---

# Auditoria global em 09/10 — concluída com correções pendentes

Este estado prevalece sobre os registros históricos abaixo. Rodrigo já aprovou visualmente
F5–F7 e pediu dez especialistas antes de PR. As dez frentes entregaram pareceres delimitados;
a consolidação final está em `docs/audit/2026-10-09-agentes-global-consolidado.md`.
A auditoria terminou; o pacote NÃO está aprovado para PR/release. Nenhum produto foi alterado
na auditoria. Não repetir dez revisões gerais nem revogar o aceite visual anterior.

Próximo bloco: renovar conversa após editar apresentação; corrigir entrada/retomada E3/E4
sem thread e preservar contexto em falhas; pré-marcar canal único sem perder múltipla seleção;
rotular confiança de conhecimento e mostrar aba móvel ativa; fechar o gate de recusas.
Candidatos (material assíncrono, limpar conversa, fechamento,409, limite30, Guia/toasts/legado)
exigem prova dirigida antes de mudança adicional. Não introduzir fallback especulativo.

Seis alegações em quatro grupos foram refutadas: PATCH sem envelope(2), remoção Connect/MetaAds(2),
upload500(1), totaisanalytics como vazamento(1). WrapperRails/handler herdado/integração de patch/
contratoBE-25 explicam as refutações. Não corrigir produto com base nos pareceres originais.
Consolidação final prevalece sobre contagens e metadados desatualizados dos relatórios individuais.

Freeze final09/10 08:39:22UTC:367 inputs fora de docs, zero diferenças, diffcheck0; HEAD e branch
preservados. Bateria ampliada M2:2.344 exemplos,1falha de registro skip_test_tool#1,3evalspagas
desativadas. Não suíteverde nem prova de atendimento quebrado. Source79 backend/specAST igual80
por prova integral.79presenteM2/ausenteM4;80presenteambos. Bateria adicional de papéis/SuperAdmin/
status/autoassignment não executada por planner-contexto/réplica; não forçar/restaurar/limpar.

Main/último deploy registrado GitHub:28e1e0ac8b3835577f7469368f03a86d1a8dab0d. Hub2You deployment
6943966962/workflow37826925422;Autonom.ia6943966912/37826925413 success. Sem runtime de produção.
HEAD136commitsatrás e16overlaps: integrar somente arquivos próprios e validar atualização antes
PR; não rebase/reset/merge automático nem incluir mudanças alheias.367inputsiguaisnãoatesta
zero regressão ativa. Criação54histórica;59720fora na auditoria. Gestão80/refs vistas em subconjunto
nomeado, não196imagensporrevisor. Recapturar estados afetados das correções antes de subir.

Revisão de correção segue R1→corrige→R2; se R2 reprovar, causa raiz→corrige→R3; se R3 reprovar,
parar e retornar. SemR4. Backend/frontend/runtime separados PRD§10.1. Sem novo PR/commit/push/fila/
merge/deploy/produção/SQL/pagos nesta auditoria. Automação coordena fila/deploy; somente “pode
enfileirar” autoriza ghprmerge com match-head-commitSHA; sempushapósvaga. Limpeza segue outrochat.

# Retomada F5–F7 — R3 aprovada; telas reais para aceite visual

Este estado prevalece sobre os registros históricos abaixo. Rodrigo aceitou F4 e autorizou
O que sabe, Onde atende, Ajustes e os consumidores Testar/Ferramentas. Issue #1164, épica
#1114 e Project 3. Plano: design/F5-F7-bloco-gestao.md. Auditoria:
docs/audit/2026-10-08-agentes-f5-f7-gestao.md. Worktree agentes-ia-prd, branch
docs/agentes-ia-prd, HEAD 532a5b7beb56902d2a0168013a3e8b657ba31488. Preservar alterações
alheias, prévias anteriores e claro30; limpeza pertence ao outro chat.

R1 encontrou sete achados corrigidos. R2 confirmou essas correções, mas encontrou dois P1:
o DTO completo de cotação contaminava quote_choices; o encaminhamento para time não
distribuía a conversa nativa aberta. As causas foram corrigidas e o mesmo revisor concluiu
R3 APROVADA, sem achados acionáveis, em revisoes/F5-F7-r3.md. Revisão técnica encerrada;
não há R4. O aceite visual deste bloco pelo Rodrigo ainda está pendente.

Fonte final: 20261008-203511-532a5b7b-f42aa58719-03f5a091. Hash de conteúdo:
f42aa58719a8923091ab565bd5903ad5c4d3e5b7e9841aa762a88179cf94c077. São 14.987 entradas,
duas réplicas verificadas, produto/specs/QA congelados. Não confundir conteúdo com commit.
Frontend: 200/200 testes em 33 arquivos; ESLint sem erros, 523 avisos; Guia e i18n em dia;
build aprovado. Esses recibos da fonte78 aplicam-se à fonte80 por comparação integral
78→79→80. Backend79: 276 exemplos, zero falhas e formatos em dia; a execução combinada
falhou apenas nos sete alinhamentos de spec. Corrigidos na fonte80, com AST Ruby idêntica
e comparação integral comprovadas. Lint80: 42 arquivos, zero ofensas. Recibo consolidado:
.codex/preview/check56/canonical-gestao80.json. Isso é validação local, não CI ou produção.

Navegador final80: 124/124 cenários aprovados nos quatro perfis. Galeria: 196 PNG originais,
49 estados em computador/celular e claro/escuro; 40 referências do mockup separadas.
Portal: 18/18 destinos autenticados e 236 imagens conferidas. Não usar capturas antigas ou
placeholders como fonte final. Manifesto: .codex/preview/agents/screenshots/gestao/source80-final/manifest.json.

Telas reais: http://127.0.0.1:59750/preview-telas
Jornada interativa: http://127.0.0.1:59750/preview-gestao

Serve80 tem duração de quatro horas e túnel no M4, com banco sintético exclusivo; não é
hospedagem permanente. Não parar serviços na entrega nem reseedar após a validação.
Dados, IA e serviços externos são fictícios; telas, APIs, permissões e persistência são reais.
Somente o runtime próprio gestao77 foi substituído após cancelamento oficial e portas livres.
Bancos e snapshots anteriores permanecem preservados. Libvips isolada no M2 validada por
arquivo/ActiveStorage; from_buffer não validado. Nada instalado globalmente ou em produção.

WhatsApp e QR continuam em Canais; Agentes associa múltiplas caixas existentes. Alinhamento
de Teste e criação/F4 aceitos continuam preservados. Nenhuma migration nova neste bloco.
PR #1115 congelado: sem novo PR, commit, push, fila, merge, deploy ou produção.
Automação coordena fila e deploy. Somente “pode enfileirar” autoriza gh pr merge com
--match-head-commit SHA; não fazer push após pedir vaga.

# Retomada F4 — R3 aprovada; telas reais prontas para aceite visual

Este estado prevalece sobre os registros históricos. Rodrigo aceitou o bloco de criação e os
dois ajustes de Teste/Ligue, e autorizou Como está indo, resultados e conversas atendidas.
Issue #1160 vinculada à épica #1114 e Project3. Worktree existente agentes-ia-prd, branch
docs/agentes-ia-prd, HEAD532a5b7beb56902d2a0168013a3e8b657ba31488. Plano design/F4.md;
auditoria docs/audit/2026-10-08-agentes-f4-painel-resultados.md. F5–F7 completos continuam
fora deste bloco; suas abas reutilizam consumidores existentes.

Aplicação congelada no snapshot20261008-154459-532a5b7b-49f6df2a1b-6569bd77, conteúdo
49f6df2a1bc1b437f52a19322622c8ee83f8ac3a5d86d726e9b1481d158a9b07, duas réplicas verificadas.
Não confundir SHA de conteúdo com commit. App, specs e QA canônicos na mesma fonte, sem overlays.
Validação final:70/70Vitest em14arquivos,28/28RSpec, ESLint0erros/103avisos, RuboCop6/0,
i18n13/20.568, build e formatos do Guia aprovados. Guia build/check aprovado anteriormente,
sem mudança posterior de rota/explicação. Navegador52/52 em execução integral única nos quatro
perfis. Portal final passou10destinos,72cartões/filtros, teclado móvel do gráfico30dias e ciclo
real active+enabled:false→Pausado→Atendendo→Pausar com confirmação→Pausado; fixture restaurada.
Isso é evidência local, não CI, release ou aceite visual.

Telas reais: http://127.0.0.1:59740/preview-telas
Jornada interativa: http://127.0.0.1:59740/preview-painel
Galeria72PNG originais/18cenários×4perfis, todos da mesma aplicação final;36referências do mockup
identificadas separadamente. Arquivos finais em .codex/preview/agents/screenshots/panel-f4/r3-graph-final;
manifesto em .codex/preview/check55/final-source-capture-manifest.json, SHA
9abaa2618a919178218f5bdd426d52be3cb08911e4a08fb257167c8b08ffb878.
Não usar current/i18n-final/r3-final intermediários. Runtime serve-f4-r3-final-source no M2,
túnel59740/59741 no M4, banco sintético exclusivo59740–59743. Job tem duração limitada, não
é hospedagem permanente. Não parar serviços ao entregar a prévia ao Rodrigo.

R1 encontrou quatro erros de aplicação, corrigidos. R2 reprovou total limitado a50, controle
sem semântica de interruptor e textos técnicos. Causas raiz registradas/corrigidas: contagem do
escopo autorizado antes do limite; AgentSwitch existente com role/aria/estado E5/E6; textos
REDESIGN próprios en/pt_BR preservando legado. Leitura adicional antes da R3 encontrou dia
recente fora do gráfico30dias: desktop passou a caber inteiro e celular abre no trecho recente,
com geometria comprovada na matriz52. Mesma última R3 concluída: APROVADA, sem achados acionáveis, em revisoes/F4-r3.md.
Ferramenta interrompeu a sessão de navegador por permissão de rede revogada; parecer retomado
com fonte, capturas locais e recibos nativos/portal, sem nova sessão CUA. Esse limite está no
parecer. Aplicação permanece congelada; revisão técnica encerrada, semR4. Aceite visual F4 do
Rodrigo dado em08/10; aprovação técnica local não substitui esse aceite nem autoriza release.

Prévia54 e banco50/claro30 preservados. Limpeza de snapshots/worktrees/branches pertence ao
outro chat; nenhum item excluído aqui. Sem novo PR, commit, push, fila, merge, deploy, produção
ou migration. PR1115 congelado; Automação coordena fila/deploy. Só “pode enfileirar” autoriza
gh pr merge --match-head-commit SHA, sem push após pedir vaga.

# Retomada54 — Teste alinhado e Ligue com várias caixas; revisão encerrada

Este estado54 prevalece sobre os registros históricos abaixo. Rodrigo aceitou as demais telas
de criação e pediu somente os dois ajustes descritos aqui. Ambos foram corrigidos localmente.
O campo de mensagem e os botões estão alinhados em Teste; no celular o placeholder cabe inteiro.
Ligue permite marcar/desmarcar várias caixas existentes, publicar em uma única operação e
mostrar todos os nomes no Pronto após recarregar. WhatsApp continua conectado em Canais.

Snapshot54: `20261008-105028-532a5b7b-5711deea65-548ec6fb`, SHA-256 de conteúdo
`5711deea65fa462600d85866574c9a3c71f1d031d7cd07040d4a92ab36423ee4`.
Branch `docs/agentes-ia-prd`; HEAD Git/PR1115 permanece `532a5b7beb56902d2a0168013a3e8b657ba31488`.
Não confundir SHA de conteúdo do snapshot com SHA de commit. Réplicas M2/M4 verificadas.

Validação53: 115 casos JS, 34 exemplos Ruby, lint sem erros, RuboCop: 9 arquivos, zero ofensas, i18n: 13 catálogos/20.448
mensagens e formatos do Guia em dia. Navegador: 45 aprovados/0 falhas/3 repetições F1 omitidas,
mais quatro extras de material aprovados. A R1 encontrou apenas placeholder cortado no celular;
o tamanho responsivo foi corrigido e quatro jornadas principais passaram novamente em 54.
A R2 do mesmo revisor não encontrou achado acionável e encerrou os dois ajustes:
`revisoes/F2-F3-multi-inbox-r2.md`. Não houve R3 ou quarto ciclo.

Prévia ativa: http://127.0.0.1:59720/preview-telas e http://127.0.0.1:59720/preview-criacao.
Código54 com banco50 preservado via runtime-m2-preserved50; não reseedar esse banco: claro 30
foi criado pelo Rodrigo. Para parar, identificar primeiro o bash do runtime54 por PID/command,
sem matar o PostgreSQL diretamente. F1 na porta 59730 continua separada.
A galeria passou no navegador:68 capturas/20 comparações/108 imagens, filtros 16/16/18/18, auth 200,
Escolha real, claro 30 preservado e duas caixas marcáveis. Compositor: botões de 44px e diferença vertical dos centros de 0px
nos quatro perfis. HTML servido coincide com o local; rede somente loopback e pageErrors[].
Recibos em `.codex/preview/check54/`; proveniência53/54 em `capture-provenance.json`.

Aguardar o retorno visual do Rodrigo sobre esses dois ajustes; o aceite anterior das demais
telas de criação permanece. Isso não aprova o redesign inteiro e não é CI verde. Sem nova
migration, novo PR, commit, push, fila, merge, deploy ou produção nesta retomada. A regra de
merge do usuário continua sem exceção: Automação coordena; somente "pode enfileirar" autoriza
gh pr merge com --match-head-commit SHA, sem push após pedir vaga.
Auditoria: `docs/audit/2026-10-08-agentes-f2-f3-publicacao-multi-inbox-causa-raiz.md`.

# Retomada50 — prévia local concluída; criação pronta para aceite visual do Rodrigo

Este estado50 prevalece sobre os registros históricos abaixo.

O snapshot50 foi verificado nas réplicas M2/M4: `20261008-091254-532a5b7b-b457c63ab6-9f631cfe`, SHA-256
`b457c63ab6d08def94e64efb599ef2dc859b12565fafd381378a4b9c70958836`. O runtime nativo terminou com 45 casos
aprovados, zero falhos e três pulados; os quatro extras de cópia de material passaram pela API real, preservando
o doador e chegando a E4. Vitest, i18n e lint do bloco passaram conforme `.codex/preview/check50/results.json`.
Isso é evidência local de validação, não CI, release ou aceite final.

A revisão de produto R2 do mesmo revisor terminou sem achados acionáveis em
`docs/agentes-ia-redesign/revisoes/F2-F3-retomada50-produto-r2.md`. A galeria no navegador passou:
HTTP 200/HTML, 68 capturas, 20 comparações, 108 imagens carregadas, filtros computador/celular claro/escuro
em 16/16/18/18 e portal HTTP 200 com autenticação chegando à Escolha real. O diagnóstico confirma tráfego
somente loopback. Evidências: `.codex/preview/check50/gallery-verify50.log` e
`.codex/preview/check50/gallery-diagnostic50.log`.

As 36 capturas mobile do export50 foram lidas em resolução original nos dois temas; o estado14 mostra
Pronto/Nota 92 e os alertas 07/09 estão inteiros no viewport. O inventário está em
`.codex/preview/check50/mobile-inspection.json`. A criação e a ativação estão prontas para o aceite visual
do Rodrigo. Isso não aprova o redesign inteiro, não é CI verde e não autoriza release.

A regra vigente permanece: implementar → revisão 1 → corrigir → revisão 2 pelo mesmo revisor; se a revisão 2
reprovar, registrar causa raiz → corrigir → revisão 3 pelo mesmo revisor; se a revisão 3 reprovar, STOP e retornar
ao Rodrigo. Não há quarto ciclo. A Issue1138 recebeu o estado local50 preservando o histórico. Sem novo PR, commit,
push, fila, merge, deploy, produção ou migration.

# Retomada44 — regra de revisão vigente; STOP43 histórico

Rodrigo autorizou a retomada local com a seguinte cadência: falhas de testes, lint e build são
validação, não revisão, e devem ser corrigidas autonomamente antes de chamar o revisor. O fluxo é
**implementar → revisão 1 → corrigir os achados → revisão 2 pelo mesmo revisor**; se a revisão 2
ainda reprovar, registrar a causa raiz antes de corrigir e chamar **o mesmo revisor na revisão 3**.
Se a revisão 3 ainda encontrar erro, parar e retornar ao Rodrigo; não abrir um quarto ciclo.

O STOP43 permanece como histórico: em 2026-10-08, o snapshot
`20261008-073655-532a5b7b-f821462254-accd6713` terminou com 1 caso aprovado, 1 falho e 46 não
executados, e o contraste baixo em **Conte** bloqueou a galeria e o aceite das telas reais. A
retomada não declara prévia ou produto aprovados. Evidência: `docs/audit/2026-10-08-agentes-f2-f3-bloco-criacao.md`
e `.codex/preview/check43/native43-verify.log`.

> Estado atual 08/10: retomada44 documental/local; a galeria real e o aceite F2+F3 continuam pendentes. PR1115 congelado; sem novo PR, commit, push, fila, merge, deploy ou produção sem OK explícito do Rodrigo. O STOP43 completo permanece na auditoria indicada acima.

# Handoff — Redesign de "Agentes de IA" (Chat2You) → Codex

Escrito pela sessão Claude Code em 07/10/2026, para o Codex continuar o trabalho sem perder contexto.
Leia este arquivo inteiro antes de qualquer ação. Depois leia, nesta ordem: `AGENTS.md` (raiz do repo),
`docs/agentes-ia-redesign/PRD.md` §0, §4, §5, §6, §6.6, §7.0, §10 e §11.7–§11.8.

---

## 1. O que é o projeto

A área **Agentes de IA** do Chat2You (fork do Chatwoot, repo `autonom-ia2/chat`, pasta local
`/Users/rodrigosilva/dev/chat2you`) é a única que ainda não passou pelo redesign "premium e simples" das outras áreas
(Automações #982, Campanhas #990, Primeiros passos, Central). O Rodrigo pediu:

1. visual igual ao padrão Chat2You;
2. jornada de criação mais simples, para uma pessoa com pouca familiaridade com tecnologia ("QI 70");
3. todas as telas reimaginadas (lista, criação, painel, conexão de WhatsApp, peças dentro da conversa), com o backend
   que isso exige;
4. **muito cuidado com os agentes em produção** (Clara na conta 16 da stack hub2you, Lia/Agente de Cotação, agente da
   conta 2 da stack autonomia).

## 2. Onde está cada coisa

Tudo está na branch **`docs/agentes-ia-prd`** (worktree `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`),
com a épica **#1114** e issue B1 **#1120** no Project. PR documental **#1115** aberto e congelado no HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`; implementação B1 somente local.

| Arquivo | O que é |
|---|---|
| `docs/agentes-ia-redesign/DIAGNOSTICO.md` | Diagnóstico inicial (bugs B1–B12, atritos, diferença visual). Já está na `main`. |
| `docs/agentes-ia-redesign/PRD.md` | **Fonte da verdade.** PRD v9.2 (~1.400 linhas): decisões D1–D35, telas, máquina de estados, BE-00…BE-32, plano de PRs B1…F10, gate de telas reais e cenários locais, critérios de aceite, contrato de validação em produção, volta, registro de revisão. |
| `docs/agentes-ia-redesign/PRD-agentes.html` | Página de leitura do PRD (gerada). Publicada em https://claude.ai/artifact/7uxXATxV3EzTsVxKrw64V9 |
| `docs/agentes-ia-redesign/mockup/` | **Protótipo navegável aprovado pelo Rodrigo** — é a fonte da verdade visual. |
| `docs/agentes-ia-redesign/mockup/src/*.js`, `src/styles.css` | Fontes do protótipo (dados reais da conta 16 em `data.js`). |
| `docs/agentes-ia-redesign/mockup/build.sh` | Junta as fontes em `mockup/jornada.html` (uma página só). |
| `docs/agentes-ia-redesign/mockup/jornada.html` | Protótipo pronto. Abra no navegador (precisa de internet só para os ícones Lucide). Publicado em https://claude.ai/artifact/NdjZdAnt8uhTa4P2VziyGM (versão 8 + textos de excluir do #1063). |
| `docs/agentes-ia-redesign/aceite-telas-reais.md` | Gate local obrigatório: 14 grupos de cenários, matriz de perfis/temas/tamanhos e checklist para mostrar todas as telas reais antes do primeiro deploy. |
| `docs/agentes-ia-redesign/validacao-producao-base.md` | Rascunho **não normativo** das consultas (Q1–Q17) e cenários do tester (T01–T31, P0–P5), com 15 pendências obrigatórias. Cada PR parte dele para escrever o seu plano de validação. |
| `docs/agentes-ia-redesign/revisoes/rodada-1..9.md` | Achados das rodadas de revisão do PRD (IDs R1-xx…R9-xx citados no §7.2 do PRD); a R9 e a checagem terminaram sem achados residuais documentais. |
| `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md` | Causas raiz C1–C15 das rodadas que pararam (regra do Rodrigo). **Leia antes de editar o PRD.** |
| `docs/agentes-ia-redesign/tools/` | `prdedit.py` (editar item inteiro do PRD, causa C9), `build_prd_html.py` + `prd_page.css` (gera a página do PRD), `shots.sh` (capturas do protótipo com Chrome headless). |

### Como usar o protótipo

- Abrir: `open docs/agentes-ia-redesign/mockup/jornada.html`.
- Dentro dele: botão **"Todas as telas"** (mapa de todas as telas e estados), **"Ver como"** (pode editar / só pode ver /
  admin da plataforma) e a barra **"Ver esta tela como"** em cada tela (estados: carregando, erro, vazio etc.).
- Editar: mude `mockup/src/*.js` ou `styles.css` e rode `bash docs/agentes-ia-redesign/mockup/build.sh`.
- Conferir visual (obrigatório antes de entregar, regra do Rodrigo): capturas com
  `bash docs/agentes-ia-redesign/tools/shots.sh <pasta_saida> "teste ligue agente-clara-ajustes" 1440 1500` — os nomes
  aceitos são os do `MAP` em `mockup/src/screens-extra.js` (ex.: `lista`, `conte@pensando`, `agente-lia-ajustes`,
  `interno-teste`, `lista#view`). Janela muito alta (> ~3000 px) sai em branco no Chrome headless; não é bug da página.
- Ler as capturas antes de dizer que está pronto. Nunca entregar tela branca.

## 3. O que já está feito

1. **PR #1036 (em produção, `ac6028c00b`)** — bugs B1–B3: pausar/desligar devolve as conversas para a equipe e inativa o
   espelho (`after_update :sync_mirror_bots`), excluir devolve antes de apagar, limpeza de rascunhos só apaga rascunho
   vazio, `insurance_quote` nunca nasce pelo Construtor.
2. **PRD completo** com 9 rodadas de revisão em 4 lentes (produto, técnica, segurança/produção, testes). Convergência:
   60 → 63 → 59 → 46 → 43 → 27 → 28 → 28 → **11 confirmados** (1 alto, 9 médios, 1 baixo; UX-04 rejeitado). A R9 normal
   está consolidada em `revisoes/rodada-9.md`; as correções e a checagem independente terminaram sem achados residuais documentais.
3. **Protótipo** aprovado pelo Rodrigo ("ficou muito bom. Isso mesmo") e atualizado a cada rodada.
4. **Atualização pelo #1063** (exclusão lógica, Roberto, em produção desde 06/10, `4d79f25612`): PRD §0, D34, D35, BE-14,
   BE-22 (fora), CA-BE-04 e textos de excluir no protótipo. Análise: sem risco para o plano (SoftDelete chama
   `sync_mirror!(operating: false)`, que devolve as conversas como o #1036; `agents_scope` e reaper usam `.kept`).

**Retomada35: validação local25 PASS/0 FAIL/3 SKIP (exit0),33 capturas reais e réplicas verificadas antes/depois. Sobreposição móvel R34-VIS-01 corrigida; galeria offline com imagens originais pronta. Rodrigo pediu revisão em blocos maiores: próxima entrega é a jornada inteira de criação, sem OK a cada microetapa. F1 sem aceite humano; F2–F7 ainda pendentes. Sem PR/push/merge/fila/deploy/produção. Audit `docs/audit/2026-10-08-agentes-f1-blocos35.md`.**

### 3.1 Estado atual da retomada — 07/10/2026

- **Estado corrente — entrega por blocos35 em08/10:** snapshot `20261008-041914-532a5b7b-dce699dc2e-b839f31f`, SHA256 `dce699dc2ef9762cced2041deb14e2067e3e98a72d9169fef89e7680e24bd589`, ambas as réplicas verificadas antes/depois. Matriz25 PASS/0 FAIL/3 SKIP,33 capturas reais. Padding móvel e verificação geométrica do aviso encerram R34-VIS-01. Prévia `.codex/preview/agents/agentes-ia-bloco-1.html` é um arquivo único offline de capturas reais, não a aplicação navegável. Rodrigo mudou a cadência para jornadas completas; próxima é Modelo → Conte → Teste → Ligue → Pronto. Sem aceite F1 ou implantação de F2–F7; sem commit/push/PR de implementação, merge/fila/deploy/produção. Este estado prevalece sobre os históricos abaixo.

- **Estado corrente — STOP visual34 em08/10:** snapshot34 `20261008-034637-532a5b7b-5a476c9517-87a370f4`, SHA256 `5a476c951707b9e08ab702ac2d8dd62ad47657e13f25979d1cfc086d3be69a5a`, duas réplicas verificadas. Matriz25 PASS/0 FAIL/3 SKIP, capturas33 lidas sem branco. Defeitos33 corrigidos, mas a leitura do fim da lista móvel encontrou sobreposição do launcher sobre o aviso. R34-VIS-01 documentado com causa e padding móvel proposto, sem aplicação após a final. Retornar a Rodrigo; nenhuma tela aceita, F2–F7 pendentes. Sem commit/push/PR de implementação, merge, fila, deploy ou produção. Este estado prevalece sobre históricos abaixo.

- **Estado corrente — correção restrita após33 autorizada por “continue” em 08/10:** resultado33 8 PASS, 17 FAIL, 3 SKIP (exit1). H1 resolvido; falhas de nome do menu mobile e cores no tema escuro. Captura final pós-delete branca por espera incompleta do harness. Snapshot33 verificado antes/depois, SHA256 `652b87a6027f7e0d7bc862f82b942de816a6b03c5b59bbcca9b39b08332fc716`. Sessão informou STOP; Rodrigo orientou continuar. Corrigir somente as causas conhecidas e validar uma vez. Sem aceite F1, F2, PR de implementação, push, merge, fila, deploy ou produção. Este estado prevalece sobre os históricos abaixo.

- **Estado corrente — retomada do H1 em 08/10:** Rodrigo autorizou a correção específica e validação local após STOP32. Aplicada cor branca diretamente no H1 de AgentsEmptyHero; stylesheet global intacto. Capturas antes do Axe, lower-list para Clara e execução única completa dos quatro projetos, sem retries. Audit `docs/audit/2026-10-08-agentes-f1-retomada-h1.md`. Snapshot/execução/aceite ainda pendentes. Sem PR de implementação/merge/fila/deploy/produção; F2–F7 continuam pendentes. Este estado prevalece sobre os históricos abaixo.

- **Estado corrente — STOP FINAL32:** snapshot `20261007-214937-532a5b7b-fe3bcb720e-3b740e77`, SHA256 `fe3bcb720ead758c83aaafacb3b262a24277363fde5ea3af028261ee8bda79f1`, duas réplicas verificadas antes/depois. Vitest38/224 passou, exit0, incluindo as duas lacunas D9, foco e integração de retomada. Navegador real: lista desktop1440claro passou, vazio reprovou no H1 por contraste1,04; 26 casos não rodaram. `_base.scss` define cor diretamente em headings, H1 do hero só herdava branco da section. Correção necessária `text-white` no H1 não aplicada após a falha final. Regra do Rodrigo exige parar e retornar, sem outro ciclo. Capturas reais de lista/vazio lidas e preservadas, nenhuma aceita. Captura “lower” é duplicada e não prova o fim da lista. Não houve lint32/build/check amplo após falha; não apresentar resultados históricos como CI ou validação final do lote. Relatório completo `docs/audit/2026-10-07-agentes-f0-f1-final32-stop.md`. Serviços locais do preview encerrados, nenhum listener59720–59723, banco sintético preservado. F2–F7/B3 completo pendentes. Nenhum commit/push/PR de implementação, merge, fila, deploy ou produção. Este estado prevalece sobre os históricos abaixo.

- **Estado corrente — STOP final25:** snapshot `20261007-190704-532a5b7b-42bf732f84-0ababeca`, SHA256 `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`, duas réplicas verificadas antes/depois. Ruby 222/zero falhas/zero pendentes/externos; JS 43/43 nos quatro arquivos API/store/Message/PanelTune. Performance mista ≤12 SELECTs e disponibilidade nativa 1→20 constante passaram; STATE e enum/configuração/canais/notas privadas passaram nas checagens. **A revisão final B2 permanece bloqueada por seis ofensas em 106 arquivos Ruby**: três `Rails/LexicallyScopedActionFilter` no concern RequestValidation e três alinhamentos no spec Enterprise real `spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_wrong_replies_spec.rb`. Causa e mínima correção futura estão registradas, sem aplicação: callbacks permanecem no controller; alinhar o arquivo do receipt real. Pareceres `revisoes/B2-codigo-final-{n1perf,r9-produto,estado-runtime}.md`; recibos no fim de `docs/audit/2026-10-07-agentes-b2-integracao-inicial.md`. BE05 reader/writer e consumidor PanelTune passaram na única checagem limitada (`revisoes/B3-BE05-codigo-limitada.md`), flag ligada retoma histórico e não cria outra thread, flag desligada preserva legado. Isso não prova F0, o B3 completo nem telas reais. Conforme a regra do Rodrigo, interromper e retornar; não corrigir nem abrir outro ciclo por iniciativa da sessão. F0/F1, prévia sintética, Guia/formatos atualizados do lote, bateria ampla combinada final e aceite visual continuam pendentes. Sem novo commit/push/PR implementação, merge, fila, deploy ou produção. Este estado prevalece sobre os históricos abaixo.


- **Estado corrente snapshot22 e correção normal B2:** snapshot `20261007-182755-532a5b7b-17fe0961a1-fd384075`, SHA256 `17fe0961a13db1df8c18aafa2f303c692c41d5f2a88994637bb37cdc323e9275`, duas réplicas verificadas antes/depois. Ruby 222 exemplos/oito falhas/zero pendentes ou externos: 14 BE05 passaram; enum numérico/canal inbox_id e 16 fixtures legadas passaram; oito falhas dos achados de estado/digest/nota privada e instrumentação N1 em correção única. Bateria ampla19 teve sete falhas de fixtures antigas com flag CRM ausente, causa registrada e corrigida sem relaxar gates. B2 revisão normal fechou sete achados, checagem limitada ainda não começou. F0/F1 desenhos fechados após regra D7; produto ainda pendente. Vitest22 após dependências offline M2: 38 executados/29 passaram/nove falhas, quatro módulos F0 não coletados porque ausentes. BE05 API/store e nota privada frontend agora em implementação após RED. Primeira tela Seus agentes ainda não existe no produto, aceite/capturas pendentes. Sem novo commit/push/PR implementação/merge/fila/deploy/produção. Este estado prevalece sobre históricos abaixo.


- **Integração atual B2 e preparação da primeira tela:** snapshot18 executou 124 exemplos/uma falha/zero pendências ou erros externos. Causa provada: polling failed/resultnil recuperava teste antigo porque nil responde to_h; corrigido root após RED, ainda sem GREEN. Snapshot19 `20261007-180541-532a5b7b-fb59e79917-20069aba`, checksum `fb59e799170f2c57a42bf498a0beaebba382305b0f75df50a4fb2b351af0ef27`, duas réplicas verificadas, em bateria ampla combinada B1+B2 de 432 arquivos. Snapshot18 lint89 e formatos oficiais check passaram. Leitor BE05 Issue #1133, desenho B3 em revisão final única após causa residual registrada; produto BE05 não iniciado. F1 única revisão normal encontrou seis contratos a corrigir, correção documental/mockup em andamento; F0 checagem específica pós-D7, sem apagar STOP antigo. Runtime sintético de prévia preparado somente local M4/portas59710–59713/schemaisolado, serviços de produto ainda desligados. Nenhuma tela real implementada/aceita, nenhum push para #1115, commit novo, PR de implementação, merge/fila/deploy/produção. Este estado prevalece sobre históricos abaixo.

- **B2 em integração local após RED real:** 18 arquivos/114 exemplos, 105 falhas (99 contratos ausentes e seis fixtures BE28 inválidas), zero pendentes/externos no snapshot `20261007-165304-532a5b7b-52bd2e6c7e-ac8f47f5`. Fixture AgentEvent corrigida para conversation_id antes do produto BE28; snapshot seguinte `20261007-165703-532a5b7b-38a27ee1ba-e14d385e`: sete exemplos/seis falhas esperadas de DTO/zero pendentes/externos. Depois das provas RED, subagentes implementaram materiais/estatísticas, disponibilidade/canais/espelhos e estado/teste assíncrono; root integra gate/toggle/lista/serializers/gaveta e writers compartilhados. GREEN, orçamento de consultas e revisão normal de código ainda pendentes. Evidência em `docs/audit/2026-10-07-agentes-b2-implementacao.md`. F0/F1 não implementados; primeira tela #1130 continua sem captura/aceite. Issue F0 #1123 atualizada com D7/retomada, histórico preservado. Nenhum commit/push novo, PR de implementação, merge, fila, deploy ou produção. Este estado prevalece sobre os históricos abaixo.

- **B1 fechado tecnicamente no ambiente local; B2 em testes primeiro:** revisão limitada dos sete achados sem residual, resíduo de estilo corrigido/revisado pela passagem final e lint43 verde. Snapshot final `20261007-163238-532a5b7b-9baf372e0e-e72fb9e9` verificado nos dois nós: 4.819 exemplos/zero falhas/74 pendentes (71 evals pagos desativados, três quarentenas do harness); 43 testes frontend, ESLint, build, i18n, Guia e formatos oficiais passaram. Evidência completa no fim de `docs/audit/2026-10-07-agentes-b1-codigo-causa-raiz.md`. Sem CI novo, commit/push, PR de implementação ou aceite de tela. Rodrigo confirmou seguir: próximos contratos B2 (#1122), testes antes do produto, para primeira tela real Seus agentes (#1130, adicionada ao Project). Nova decisão WhatsApp permanece em Canais; demais telas só avançam após seu aceite da atual. Sem merge, fila, deploy ou produção. Este estado prevalece sobre os históricos abaixo.
- **Retomada com mudança explícita de produto e aceite tela por tela:** Rodrigo retirou a conexão de WhatsApp de dentro da área Agentes. Ligue usa somente canais já conectados/disponíveis; a conexão continua na área central existente de canais, com orientação/atalho quando necessário e preservação do agente salvo. Isso substitui D7/BE-13 e o fluxo interno `connect-whatsapp` anterior; não transforma o parecer final antigo em PASS. Rodrigo confirmou seguir e exige ver/tratar cada tela real antes de subir. Primeiro aceite: Seus agentes; avanço de tela depende do OK visual/funcional do Rodrigo. Correções dos sete achados B1 retomadas após RED real; validação e checagem focada ainda pendentes. Fontes normativas/mockup em atualização por ownership para a nova decisão. Sem nova revisão geral do PRD, merge, fila, deploy, produção ou push para #1115. Este estado prevalece sobre a parada histórica abaixo.
- **PARADO após a revisão final F0, sem outro ciclo autorizado:** produto/testes final passou, mas a revisão técnica final deixou **F0-FINAL-01 P1**: o helper de origem da conexão só aceita Onde atende, embora PRD/BE-13 e mockup também exijam retorno para Ligue. Causa e prova em `revisoes/F0-desenho-final-tecnica.md` e `docs/audit/2026-10-07-agentes-f0-checagem-causa-raiz.md`. Nenhuma correção adicional ou código F0 iniciado; retornar ao Rodrigo conforme sua regra. B1 continua local e incompleto: a bateria anterior teve 4.805 exemplos/zero falhas/74 pendentes, mas a revisão normal encontrou sete achados ainda não corrigidos. Novos testes RED executados em snapshot isolado: Ruby 127 exemplos/16 falhas esperadas/zero pendentes/zero erros fora dos exemplos; JS 14 testes/uma falha esperada. Nenhuma correção do produto após esse RED nem checagem de código iniciada. B2 (#1122) teve o desenho fechado sem residual, sem código. Telas reais e cenários/aceite continuam pendentes; prévia antiga encerrada. Nenhum push para #1115, merge, fila, deploy ou nova consulta de produção. Este estado prevalece sobre os registros históricos abaixo.
- **Implementação B1 iniciada, testes reais no M2:** snapshot oficial verificado nos dois nós, wrapper de teste preparado sem migration. Primeira execução RSpec:161 exemplos,95 falhas,0 pendentes,0 erros fora dos exemplos; inclui falhas esperadas e helpers novos com kwargs inválidos, já corrigidos. Código dividido por ownership entre subagentes; nova prova RED dos contratos seguida de implementação. Audit `2026-10-07-agentes-b1-implementacao.md`. Nenhum push para #1115, merge, fila, deploy ou acesso adicional à produção. Estado atual prevalece sobre registros históricos seguintes.
- **Segunda retomada autorizada — desenho B1 liberado para implementação local:** Rodrigo autorizou corrigir a referência antiga e conferir todas as menções. A tabela BE-19 foi corrigida; checagem focada de TEC-11 concluída sem erro residual (hash `eb6a02821cc6c44202582961628edc0e0c5e7760f372a54b4ca6a2bd9d192399`). Os dez pontos anteriores continuam fechados. Testes primeiro e implementação ainda pendentes; capacidade do snapshot/testes no M2 em conferência. Não houve push, merge, fila, deploy ou novas consultas de produção. Esse estado prevalece sobre as paradas históricas abaixo.
- **Resultado da retomada — parado novamente:** a checagem confirmou o PATCH real de agente e o ator SuperAdmin autorizado, mas encontrou referência antiga a `resource_params` na tabela BE-19 de `design/B1.md:427`. A correção documental ficou incompleta. Código não iniciado; diagnóstico/mapeamento interrompidos; retorno ao Rodrigo, sem nova correção ou rodada por iniciativa da sessão. O audit de causa raiz mantém os dois resultados e a autorização intermediária.
- **Retomada autorizada após a parada:** Rodrigo respondeu “ok. Pode continuar”. B1-TEC-11 teve o alvo corrigido localmente para o PATCH real de agente; checagem focada ainda pendente. O código continua aguardando essa checagem e os pré-requisitos de teste. Nenhum limite de produção, merge ou fila foi alterado; o PR documental permanece no mesmo HEAD. Este registro prevalece sobre o estado histórico de parada abaixo.
- **Parada após revisão final do desenho B1:** PR documental #1115 aberto, HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`, CI verde, sem migration e sem OK específico de merge. As correções posteriores de `design/B1.md` e os dois audits de desenho são locais, sem novo push. A revisão final deixou B1-TEC-11 P1: o desenho confunde update de Account no SuperAdmin com o PATCH real de agente. Não fazer outra correção/revisão nem iniciar código sem nova orientação do Rodrigo. Resultado em `docs/audit/2026-10-07-agentes-b1-desenho-causa-raiz.md`. As telas reais continuam pendentes. O setup local ignorado foi preparado e corrigido, mas não executado: M4 abaixo da reserva de disco; alternativa M2 ainda exige snapshot/preparação oficiais.
- Rodrigo aprovou as recomendações D1–D35 e autorizou a rodada 9 como plano. Isso não autoriza merge, deploy, alteração de
  banco, fila ou escrita do UPDATE previsto em D10.
- R9 normal foi concluída e consolidada em `revisoes/rodada-9.md`, com 11 achados confirmados (1 alto, 9 médios, 1 baixo;
  UX-04 rejeitado). Correções fechadas na checagem independente, sem achados residuais documentais. Nos próximos PRs,
  achado na checagem exige parada, causa raiz e revisão final; erro na final exige retornar ao Rodrigo, sem repetir ciclos.
  Registro pré-R9 e resultado estão no §15.1c–§15.1d do PRD.
- O caminho ao vivo (B1, B4b, B5 e B6b) será pedido isoladamente; os demais PRs podem entrar em lotes de até 7 sem migration,
  conforme a sessão Automação. Um PR com migration sobe sozinho com snapshot e plano de volta.
- Antes do primeiro deploy do redesign, o backend necessário deve funcionar no ambiente local de teste e a jornada precisa ser
  mostrada em todos os cenários e telas reais descritos em [`aceite-telas-reais.md`](aceite-telas-reais.md), com capturas lidas
  em 1440/400 px, claro/escuro e perfis editar/só ver/admin. O protótipo publicado foi percorrido em 07/10 (41 entradas do mapa
  e criação até Pronto). As telas reais ainda não existem; o aceite local e a aprovação dessas telas estão pendentes.
- O risco de segurança do B1 continua aberto: BE-19 (chaves de `config` fora da lista), BE-25 (conversas fora das caixas
  permitidas) e BE-31 (caminho controlado ainda não implementado). Após OK específico, houve apenas leitura read-only: Antes B1
  = zero nas duas stacks; Q12a = zero no Hub2You e uma ocorrência/um agente na conta 20 da Autonom.ia, preservada para
  recuperação técnica; Q12b não foi executada e não houve correção ou escrita. O recibo está no §11.7/§15.1d do PRD.

## 4. O que faltava decidir — respostas registradas em 07/10

As perguntas abaixo preservam o histórico do handoff. Rodrigo respondeu em 07/10: aprovou as recomendações D1–D35 e autorizou
a continuação e uma revisão normal, com o limite de correções e checagens registrado acima.

1. **As 35 decisões D1–D35** (tabela da §4 do PRD; resumo no topo da página do PRD). Cada uma tem recomendação. Pergunte se
   ele aprova todas as recomendações de uma vez ou quais quer mudar. Atenção às mais sensíveis:
   - **D1** (Testar = caminho da produção; régua de certeza sai),
   - **D10** (UPDATE de tons ao vivo, por psql),
   - **D12/BE-25** e **BE-19** (falhas de segurança abertas hoje em produção — entram no primeiro PR, B1),
   - **D23** (só a tela nova exige teste para ligar),
   - **D35** (PRs do caminho ao vivo sobem sozinhos vs. lote de até 7 da fila nova).
2. **Critério de saída das revisões do PRD.** A recomendação era: rodar a rodada 9 com a regra "zero altos e zero médios de
segurança/produção → PRD aceito; o resto vira pendência do PR que toca o assunto". Alternativas: seguir até uma rodada
voltar vazia (regra literal dele) ou parar agora.

**Resposta registrada:** recomendações D1–D35 aprovadas como plano; R9 e checagem das correções concluídas sem achados residuais documentais; manter o limite do §10.3 nos próximos PRs.
O gate de telas reais e cenários locais, a implementação local do backend e o aceite visual continuam obrigatórios antes do
primeiro deploy. A escrita de D10, merge, fila, deploy e qualquer ação em produção continuam dependendo de autorização
específica.

Na versão original deste handoff, o código estava bloqueado por essas respostas. Elas agora estão registradas acima; a
implementação começa depois da conferência do protótipo e da revisão documental, respeitando os pré-requisitos de B1. O gate
das telas reais é executado após implementá-las e bloqueia o primeiro deploy, não a implementação local.

## 5. Regras do Rodrigo que valem aqui (não negociáveis)

- Responder em português do Brasil, direto, sem jargão; verdade primeiro; não inventar arquitetura, endpoint, comando.
- **Aprovação explícita** antes de: merge, deploy, qualquer coisa em produção, escrita em banco de produção, apagar
  branch remota, secrets, auth, billing, infra, DNS, permissões.
- **Produção só por leitura via psql:** SSM `AWS-RunShellScript` → `docker exec chatwoot-web psql "$DATABASE_URL"` dentro de
  `BEGIN TRANSACTION READ ONLY`. **Nunca** `rails runner`/`rails console` em produção. Stack hub2you usa `--profile hub2you`.
- **Sem regex para interpretar texto de usuário**, e regex não é a escolha padrão nem para o resto (use métodos de string,
  parser, schema). Se achar que não tem alternativa, pergunte ao Rodrigo antes.
- **Nunca encadear teste e commit** (`rspec && git commit`). Rode a validação, leia a saída inteira, depois commite.
  Depois de `rubocop -a`/`eslint --fix`, leia o `git diff` e rode os testes de novo.
- **Construção aditiva no fork:** arquivos próprios, toque mínimo em arquivo do Chatwoot, sem coluna nova em tabela upstream,
  flag para voltar à tela antiga.
- **Sem `<select>` nativo** na UI: use `components-next/choice-select/ChoiceSelect.vue`.
- **Tailwind só com tokens `n-*`**, sem CSS próprio, sem `<style>`, sem `style=""` (exceção: largura de barra).
- **i18n:** en + pt_BR no catálogo do fork (`config/fork_i18n.json`, `pnpm i18n:fork:check`).
- **Guia da Plataforma:** rota/permissão mudou → `pnpm guia:build`; controller/params mudou →
  `bundle exec rails autonomia:guia:formatos`; tela nova sem bloco em `lib/operator_guide/porques.md` não passa no PR.
- **Worktrees** em `/Users/rodrigosilva/dev/worktrees/chat2you/<issue>-<slug>`; nunca `rm -rf`, `git reset --hard`,
  `git clean`; não suprimir stderr do git. Ver `/Users/rodrigosilva/dev/CLAUDE.md` (espelhado em `AGENTS.md`).
- **Revisão:** falhas de testes, lint e build são validação, não revisão; corrija-as autonomamente antes de chamar o revisor.
  O fluxo é **implementar → revisão 1 → corrigir os achados → revisão 2 pelo mesmo revisor**. Se a revisão 2 ainda reprovar,
  registre a causa raiz em `docs/audit/`, corrija a causa e chame **o mesmo revisor na revisão 3**. Se a revisão 3
  ainda encontrar erro, pare e retorne ao Rodrigo; não abra um quarto ciclo. CI verde não é revisão.
- **Tester em produção** para todo deploy que muda comportamento: lista os testes antes com o motivo, afirmação dura,
  tempo-limite é falha, evidência (HTTP, latência, ids, eventos). Contrato no PRD §11.7–§11.8.
- **Conferir visual antes de entregar** (capturas lidas, nada em branco).
- **Qualidade acima de economia de tokens:** nunca cortar validação ou revisão para economizar.

## 6. Fila de merge e deploy (coordenação)

- A sessão **Automação** coordena todo merge e deploy do `autonom-ia2/chat` (decisão do Rodrigo). Ninguém enfileira sem ela
  dar a vez. Quando um PR estiver pronto, entregar ao Rodrigo somente estes quatro dados: **número do PR; OK específico do
  Rodrigo; CI verde no head atual; tem migration**. Rodrigo repassa à Automação. Não contatar a Automação diretamente.
  Para PR do caminho ao vivo, incluir também que deve subir isolado para rollback (D35).
- Desde 07/10: lotes de **até 7 PRs sem migration**; PR com migration vai sozinho com snapshot RDS nas 2 contas e rollback
  escrito; qualquer urgência continua sob coordenação da Automação. Depois do deploy autorizado: validar e entregar **"ok, SHA"** ao Rodrigo, que repassa à Automação.
- Não mesclar a `main` "para atualizar" (só se `CONFLICTING`). Um push por PR: rode antes, localmente, tudo que a CI barra
  (rspec da área, rubocop, vitest com `TZ=UTC`, lint de e-mail/i18n, `guia:check`). Teste alheio caiu: fechar e reabrir o
  PR (não usar rerun). PR empilhado: só enfileira depois que o de baixo virar MERGED.
- Deploy é blue-green nas 2 stacks (~40 min por deploy). Ler `docs/processo-de-release.md` antes.

## 7. Próximos passos, em ordem

**Atualização de retomada:** Rodrigo autorizou a correção pontual completa após as paradas históricas. TEC-11 fechado na checagem focada; seguir testes primeiro e implementação local de B1, preservando os limites de revisão e release. Histórico e causa permanecem no audit.

1. As duas respostas estão registradas na §4 e no §15.1c. Não perguntar novamente; manter o limite de revisão do §10.3.
2. A R9 e a checagem das correções terminaram, com zero achados residuais documentais, em `revisoes/rodada-9.md`.
   Não repetir a rodada. O desenho B1 completo e o aceite das telas reais continuam pendentes; nos próximos PRs,
   falha de teste/lint/build é corrigida antes da revisão, depois segue revisão 1 → correção → revisão 2 pelo mesmo
   revisor; achado na revisão 2 exige causa raiz/correção → revisão 3 pelo mesmo revisor; achado na revisão 3 exige
   parada e retorno ao Rodrigo.
3. A inspeção do protótipo orienta a implementação. Depois que as telas reais e o backend existirem localmente, executar o gate
   de [`aceite-telas-reais.md`](aceite-telas-reais.md). Não declarar aceite das telas reais antes da aprovação do Rodrigo.
4. A **Issue épica #1114** já foi criada e adicionada ao Project Autonom.ia Dev, com os campos definidos. O PR de documentação
   desta branch ainda não existe; quando estiver pronto, usar `Refs #1114`, corpo no formato do repo (parágrafo do produto, Closes/Refs,
   How to test). Sem código, sem deploy de comportamento. Entregar os quatro itens ao Rodrigo; ele repassa à Automação.
5. Depois da inspeção do protótipo e da revisão documental, implementar **na ordem do §10.1**: **B1** primeiro (BE-19 + BE-25 + BE-31 + BE-14 + BE-10,
   BE-21, BE-15, BE-20) — fecha as falhas de segurança abertas. As leituras read-only autorizadas já foram executadas: Antes
   B1 = zero nas duas stacks; Q12a = zero no Hub2You e chave `recovery`, uma ocorrência em um agente da conta 20 da Autonom.ia,
   classificada pelo código como desconhecida/órfã e preservada; Q12b fica fora do escopo. Não limpar nem corrigir sem decisão humana.
   Antes de implementar B1, conferir o recibo e manter:
   - `design/B1.md` com o desenho técnico, uma spec por caso obrigatório do §7.2 e o **plano de validação** (a partir de
     `validacao-producao-base.md`, resolvendo as pendências do escopo, com as respostas 6(a–d) por escrito).
6. Seguir B2 → B3 → B4/B4b/B5/B6a/B6b → F0…F9 conforme dependências do §10.1, cada PR com o fluxo do §10.2 (entender →
   desenho técnico → implementar com teste primeiro → validar local → conferir visual → revisão §10.3 → aceite → fila).

## 8. Armadilhas já conhecidas (não repita)

- **Edição do PRD:** troque o **item inteiro**, nunca linha solta — editar por linha deixou sobras contraditórias duas vezes
  (C9). Use `tools/prdedit.py` (`item_replace`, `row_replace`, `rep` com assert). Depois de editar, procure cada ID mexido
  em todo o documento (passe de consistência, §10.3 passo 5) e preencha o registro de conferência (§15.1, causa C14).
- **Regra por efeito, não por lista** (C11): "invalida o teste toda mudança que altera o que o agente responde ou por onde
  responde" — não enumere casos como fronteira.
- **Validação de produção não é mecânica** (C15): falha dispara classificação (defeito do lote → volta pré-aprovada na hora;
  não é do lote → lista ao Rodrigo; dúvida → volta). Só invariante olha o que mudou **depois da foto**.
- **Altitude** (C7/C13): o PRD fixa comportamento e casos obrigatórios; mecanismo e consulta exata vão para `design/<PR>.md`
  com o código aberto.
- **Volume real em produção é baixo** (05/10: Clara 3 conversas em 7 dias; Lia 29 em 30 dias): comportamento ao vivo se
  prova no tester, não por estatística.
- O `.env` da instância religada pelo rollback é o do primeiro boot (mudar SSM não basta).
- A fila pode juntar até 7 PRs sem migration; rollback de um degrau desfaz o lote inteiro. O caminho ao vivo pede lote isolado
  (D35, §14).
- Agentes agora têm **exclusão lógica** (#1063): toda consulta e escopo novo usa `kept` / `deleted_at IS NULL`.
- O teste do Construtor/Playground é assíncrono (202 + `poll_url`); a recusa de permissão do repo é **401**
  (`Pundit::NotAuthorizedError`).
- Capturas com Chrome headless: largura mínima ~500 px; altura muito grande dá página branca.

## 9. Contatos de produção (referência)

- Stack hub2you: perfil AWS `hub2you`; conta 16 (Hub2you, Clara), conta 27.
- Stack autonomia: credencial em `~/dev/Appsell/credential.env` (nunca imprimir); conta 2.
- Credenciais locais: `/Users/rodrigosilva/dev/claudete-ops/.secrets/credentials.env` — citar só o **nome** da variável,
  nunca o valor.
