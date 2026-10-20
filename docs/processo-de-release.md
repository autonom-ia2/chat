# Trem de release do chat2you

Combinado em 25/09/2026 entre as sessões Prospecção (#676), Cotação e Central/Guia e CRM, a pedido do Rodrigo:
subir junto o que estiver pronto, com um deploy só, em vez de um deploy de ~40 minutos por PR.

## Como funciona hoje (desde 09/10/2026, #1173)

A sessão **Orquestração Deploy** coordena fila, merge, deploy e limpeza do chat2you, no lugar da antiga sessão
Automação (decisão do Rodrigo em 09/10/2026; em 10/10 ela passou a orquestrar os deploys de todos os projetos).
Nenhuma sessão ou agente põe PR na fila sem a vez dada por ela.

**O pedido do Rodrigo prevalece sempre.** Se a Orquestração estiver fora (sessão parada, sem contexto, máquina
dormindo), o OK direto do Rodrigo libera: a sessão dona comenta no PR citando o OK dele, enfileira, e o painel
registra. A Orquestração confere quando voltar.

### Quem decide o quê

| Decisão | Quem |
|---|---|
| Ordem da fila, composição do lote, "pode enfileirar" | Orquestração |
| Merge de PR seguro (sem migration ou com migration só aditiva; sem infra; revisado; CI verde) | Orquestração (delegado pelo Rodrigo em 10/10) |
| Migration que não seja só aditiva, infra/IAM, permissões, segredos, billing | Rodrigo |
| Operação em dado de cliente, dinheiro, apagar dados ou pastas de projeto | Rodrigo |
| Liberar funcionalidade para todas as contas | Rodrigo |
| Qualquer coisa que o Rodrigo pedir | Rodrigo (prevalece) |

### Painel da fila (Issue #1237) e rótulos

O estado da fila vive na Issue fixada **#1237**, atualizada sozinha pelo workflow `fila-painel.yml` (eventos de PR, fim
de deploy e a cada 30 min). Ela não depende de nenhuma sessão estar viva: quem precisar assumir lê ali.

| Rótulo | Quem põe | Significa |
|---|---|---|
| `fila:pedido` | sessão dona do PR, com a CI verde | pediu vaga (preencha a seção "Pedido de vaga" no corpo do PR); um push depois disso tira o rótulo sozinho |
| `hotfix` | Orquestração | via expressa (abaixo) |
| `fila:validar` | o painel, ao mergear um PR com `fila:pedido` ou `hotfix` | em produção, aguardando o "ok, SHA"; a Orquestração tira depois do ok |

**Liberar é enfileirar.** Não existe rótulo de "liberado": a Orquestração (ou a sessão, com OK direto do Rodrigo)
enfileira, e o painel mostra a fila de merge e os PRs com auto-merge esperando checks. Nenhum rótulo muda na hora
de enfileirar: o `guia-trava.yml` roda de novo em qualquer `labeled`/`unlabeled`, e um rótulo trocado nessa hora
refaz os checks obrigatórios e segura o PR fora da fila (em 10/10 isso partiu um lote em dois deploys). Pular a trava
por rótulo não é saída: job pulado conta como check aprovado.

Rastro sem trava: PR que entra na `main` sem `fila:pedido` nem `hotfix`, e deploy disparado à mão, viram alerta
comentado no painel. As mensagens entre sessões continuam como aviso, mas o registro é o rótulo e o painel.

### Como assumir a orquestração

Se a sessão Orquestração não responder, qualquer sessão pode assumir com o OK do Rodrigo: ler o painel #1237, este
documento e o épico #1179 (registro dos lotes), e seguir daí. Nada do estado da fila fica só na memória de uma sessão.

Projeto novo só entra na orquestração com o inventário de deploy preenchido no repositório dele (modelo em
`docs/runbooks/inventario-de-deploy.md`).

### Pedido de vaga

Rótulo `fila:pedido` no PR, e a seção "Pedido de vaga" no corpo do PR com os campos abaixo. Só com a CI verde no
head atual e sem push depois: um push depois do pedido derruba o lote inteiro.

| Campo | O que dizer |
|---|---|
| PR | número |
| OK do Rodrigo | sim / não |
| CI | verde no head atual (SHA) |
| Migration | não / aditiva (tabela, coluna, índice `CONCURRENTLY`) / outra |
| Guia e Central | o PR toca `lib/operator_guide`, rotas, menu, `lib/central_de_ajuda` ou `public/central-de-ajuda`? Rodou `pnpm guia:check`, `pnpm central:check` **e** `rails autonomia:guia:formatos:check` (este último pega controller e parâmetros; o guia:check não)? |
| **Liberação** | sem flag (todas as contas) / flag `X` só na conta `N` como piloto, com data para decidir / flag `X` para todas |
| Urgente | sim só se a produção está quebrada ou a `main` vermelha |

Flag nova em `config/features.yml`, `feature_enabled?` novo ou lista de contas por variável de ambiente sem a linha
"Liberação" não entram no lote. Por quê: em 09/10 o levantamento em produção mostrou funcionalidades nossas ligadas
de 0 a 6 das 7 contas do autonomia (Relacionamentos, Anúncios da Meta, importação de e-mail) e outras presas em 1 a 3 contas, sem ninguém com data para decidir. O catálogo e
o estado ficam em [`liberacoes-por-conta.md`](liberacoes-por-conta.md).

### Lote

- Até **7 PRs** sem migration destrutiva por rodada da fila (ruleset `main - fila de merge`, `max_entries_to_merge: 7`).
  Migration aditiva vai no lote, com snapshot RDS nas duas contas tirado pela Orquestração antes. Outra migration sobe
  sozinha, com snapshot e rollback do banco escritos antes.
- Antes de fechar, a Orquestração confere: versão de migration repetida entre os PRs; arquivos gerados do Guia e da
  Central em dia (`pnpm guia:check`, `pnpm central:check`, `rails autonomia:guia:formatos:check`); PR empilhado só
  depois que o de baixo virar `MERGED`; e a linha "Liberação" de cada PR.
- Lote fechado: a Orquestração enfileira todos de uma vez (`gh pr merge <N> --match-head-commit <sha>`), sem mexer
  em rótulo. A sessão dona não enfileira nem dá push depois do pedido.
- Refazer CI = fechar e reabrir o PR. `gh run rerun --failed` só quando a `main` não andou desde aquela CI (o merge
  ref antigo ainda é o atual). Não mesclar a `main` "para atualizar" (só se o GitHub disser `CONFLICTING`).
- **Deploy contínuo (#1979).** Cada push na `main` pede a trava do deploy na hora, sem esperar a fila de merge. A
  trava do GitHub guarda um deploy rodando e um esperando, e o push mais novo toma o lugar do que esperava (que sai
  como *cancelado*, sem problema nenhum). Quem sobe depois leva a `main` inteira, então merges seguidos viram no
  máximo dois deploys. Até 20/10 o job "Esperar a fila de merge" segurava cada deploy até a fila esvaziar e pulava
  quando havia um mais novo; com a fila sempre alimentada, seis deploys seguidos pularam e a produção ficou duas
  horas para trás. **Na main não é no ar:** só conta como no ar o SHA que o "Deploy Green" subiu. O painel (#1237)
  marca ⏰ **ATRASADA** quando o primeiro pedido de deploy não atendido passa de 60 min, e comenta uma vez por versão
  presa no ar. Se a trava descartar o pedido do push mais novo (o GitHub não garante a ordem), o deploy que terminou
  pede sozinho um deploy novo da `main`. Cancelar um deploy à mão não impede que ele suba depois: para segurar a
  produção, o caminho é o rollback (que congela).
- **Rerun de deploy velho não volta a produção para trás.** O deploy falha na largada quando o commit dele é mais
  velho que a última imagem construída. Para subir a `main` atual, disparar um deploy novo pelo `workflow_dispatch`.

### Depois do deploy

1. Cada sessão valida a sua parte e manda "ok, SHA" à Orquestração. Nenhum lote novo antes de todos os "ok".
2. A Orquestração confere em produção, só leitura por `psql`, quantas contas têm cada flag declarada no lote
   (SQL gerado por `.github/scripts/feature_flags_por_conta.rb`). Diferente do declarado: avisa o Rodrigo.
3. Piloto com data vencida volta ao Rodrigo para decidir: liberar para todas, estender ou remover.
4. Limpeza da entrega, na mesma etapa: a branch do PR é apagada pelo GitHub no merge (`delete_branch_on_merge`,
   ligado em 09/10/2026); a sessão dona remove a worktree (`git worktree remove` + `prune`, regra do `/dev`) e
   apaga os snapshots do MacCluster da entrega pelo caminho exato, nos dois nós. Alteração solta que ninguém
   assume vai para `resgate/<data>-<nome>` (commit + push, sem PR) antes de remover.

### Hotfix (via expressa, #1176)

Para acerto pequeno e urgente. Pelo caminho normal leva ~32–40 min até o cliente: CI do PR ~11 min, CI da fila
~11 min e deploy ~9 min até a troca de tráfego (medianas das execuções de 08 e 09/10/2026 em `gh run list` e nos
passos do job "Deploy Green"). A via expressa pula a segunda bateria. É o caso de emergência em que o `--admin` da
seção "Fila de merge" vale.

1. **Regressão do último deploy? Primeiro o rollback**, com OK do Rodrigo: `workflow_dispatch` com
   `action=rollback` e `esperado_sha` (o SHA que estava no ar antes do deploy ruim) nos dois deploys. Ele só troca o
   tráfego de volta para a instância anterior, e a produção fica **congelada** até o deploy manual do conserto com
   `descongelar=true`. O hotfix vem depois.
2. **Critérios, todos obrigatórios** (a conta do GitHub é compartilhada e tem bypass: quem confere é a
   Orquestração, não o GitHub):
   - diff pequeno, até ~50 linhas;
   - sem migration e sem dependência nova;
   - rótulo `hotfix`;
   - fila de merge vazia e lote anterior com todos os "ok, SHA";
   - CI do PR verde e a `main` sem nenhum merge depois que essa CI rodou (se mudou, fechar e reabrir o PR);
   - vez dada pela Orquestração e OK do Rodrigo.
3. **Merge:** `gh pr merge <N> --admin --merge --match-head-commit <sha>`. O bypass de admin do ruleset entra
   direto na `main`, sem a rodada da fila, e o deploy dispara pelo push como sempre. Não roda CI depois do merge: o
   que valeu foi a CI do PR. Se o comando puser o PR na fila em vez de mergear, deixar seguir pela fila.
4. **Depois:** "ok, SHA" como em qualquer deploy. Hotfix sobe sozinho, nunca junto com lote.

Por que é seguro pular a fila: ela testa a combinação com os outros PRs do lote. Com a fila vazia e a `main` parada
desde a CI do PR, a combinação é exatamente a que essa CI testou. Fora desses critérios, usa o caminho normal.

### Deploy manual

`workflow_dispatch` dos deploys só com a vez da Orquestração. Exceção: rollback de emergência, avisando na hora.
Todas as sessões de agente usam a mesma conta do GitHub, então o registro do Actions não mostra quem disparou.
A Orquestração acompanha os disparos manuais e cobra quem furou a fila.

## Por que existe

Todo merge na `main` dispara o deploy blue-green completo nas duas stacks (hub2you e autonomia). Os workflows usam
`concurrency` com `cancel-in-progress: false`: o deploy que está rodando nunca é cancelado, e o que espera a vez é
trocado pelo push mais novo (#1979). Medido em
25/09: cerca de 24 minutos são o build da imagem (feito uma vez por stack, sem cache), 3 minutos a subida e a saúde
da instância nova e 5,5 minutos o desligamento da antiga. Em 04/10, com o cache do build no ECR, foram 3 min 38 s de
build e 3 min 04 s de boot, que vinha depois do build (8 min 22 s do disparo à troca do tráfego). Desde o #974 a
instância nova liga antes do build e espera a imagem chegar ao ECR, então o boot quase todo corre junto com o build.

Desde o #1350 o desligamento da antiga é um job à parte, **Desligar a blue**, que roda depois do **Deploy Green** com
sucesso e fora da trava do deploy: o próximo deploy já pode começar enquanto a antiga ainda está nos 5 min de
rollback rápido. A política não mudou: a antiga fica ligada 5 min, depois é parada (é o rollback de um degrau), e a de
dois deploys atrás é terminada. Antes de agir, o job relê o listener e os ponteiros `current`/`previous` do SSM: não
para a antiga se um rollback a trouxe de volta, espera rollback em andamento acabar e não falha se um deploy mais novo
já cuidou das instâncias. O run do deploy só termina depois desse job, mas o tráfego já está na nova desde o fim do
**Deploy Green**: é ali que se confere o "ok, SHA".

Deploy cancelado ou com falha antes da troca de tráfego (#972): se a instância nova estiver rodando o `deploy.sh`
(migrations), ela não é terminada no meio. Ela se desliga sozinha quando ele acaba, fica parada com a tag
`DeployCleanup=pending`, e o próximo deploy a termina. Se ela ainda estiver de pé, o próximo deploy espera até 30 min e,
passado isso, a termina mesmo assim e segue: só uma migration de mais de 30 min é cortada.

Falha antes de a imagem chegar ao ECR (build quebrado ou cancelado, #1350): a instância nova não rodou nada, então é
terminada sempre, mesmo se a recuperação na antiga (suspender o Instagram assistido, religar o web) falhar. Essa falha
continua falhando o job com o erro original. Todo deploy também avisa (`::warning::`, sem terminar nada) de instância
ligada há mais de 2 h que não é a atual nem a anterior registradas.

## Regras do lote manual (25/09 a 04/10/2026)

O lote manual em `release/*` foi substituído pela fila de merge (seção seguinte). Continuam valendo: a bateria do
item 2, o que dispara deploy (item 5), migration (6), par com o adapter (7), issues (8), rollback (9) e limpeza (11).

1. **Um lote aberto por vez.** `release/<data>-loteN` sai da `main`. Cada sessão faz squash nele **só** do que já tem
   OK do Rodrigo, com a própria suíte verde lida antes. PR com mais de 30 linhas ou que mexa em arquitetura também
   chega com a revisão independente já feita: CI e suíte verdes não substituem revisão. PR de lote tem base no branch do lote, não na `main`.
2. **Quem fecha o lote** roda, em cima do lote inteiro:
   - RSpec de `spec/services/autonomia`, `spec/requests/api/v1/accounts/autonomia`, `spec/models/autonomia`,
     `spec/jobs/autonomia`, `spec/services/crm`, `spec/controllers/super_admin`, `spec/configs` e `spec/lib`;
   - vitest de `routes/dashboard/autonomia`, `components/autonomia`, `components-next/sidebar`, `i18n` e `api`;
   - por último `pnpm guia:build`, `pnpm guia:check` e `pnpm central:check`, porque arquivos gerados (`guia-produto.md`,
     `guideRouteRegistry.js`, `mapa-de-artigos.json`, `cobertura.json`, evidências com número de linha) conflitam
     entre PRs. O que mudar entra como commit do próprio lote.

   A lista fixa não cobre tudo. Cada PR declara na descrição os caminhos de spec que tocou (por exemplo
   `spec/requests/api/v1/accounts/crm`, `spec/enterprise`, `spec/policies`, `routes/dashboard/crm`,
   `routes/dashboard/campaigns`, `store/modules`, `scripts/central-de-ajuda`), e quem fecha roda a união deles com a
   lista fixa, mais o lint do CI (`.github/scripts/email-protection-eslint.mjs`) nos arquivos tocados.

   Um PR que quebra a bateria sai do lote: o squash dele é revertido no branch do lote (`git revert`), e ele vai no
   próximo, sem segurar os outros nem virar correção às pressas dentro do lote.

   A saída vai para as outras sessões antes do merge. O merge para a `main` é **um só**, com merge commit (não
   squash), para os PRs do lote aparecerem como mergeados.
3. **Janela.** O lote fecha quando o último PR combinado entrar, ou 2 horas depois do primeiro squash, o que vier
   antes. Quem não entrou vai no próximo lote.
4. **Validação antes do próximo lote.** Depois do deploy, cada sessão valida a sua parte, faz o teste real curto se
   tiver (até ~30 min) e responde "ok, SHA". Nenhum lote novo vai para a `main` antes de todos os "ok": um deploy no
   meio de um teste troca a instância e contamina o resultado.
5. **Merge direto na `main` só para `docs/` e `.github/`.** Não disparam deploy. Atenção: o filtro dos workflows
   ignora todo `*.md`, mas há `.md` que o sistema lê em produção (manuais de agente em
   `app/services/autonomia/insurance/quote_agent/instrucoes/`). Esses vão no lote junto com código. Um lote só com
   manual precisa de `workflow_dispatch`. Conteúdo da Central e do Guia (`lib/central_de_ajuda`, `lib/operator_guide`,
   `public/central-de-ajuda`) dispara deploy e também vai no lote.
6. **Migration** só com aviso às outras sessões e snapshot RDS nas duas stacks antes do merge do lote.
7. **Par no autonomia-adapters (Lambda).** O lote declara a ordem (chat antes ou adapter antes). O adapter sobe fora do
   trem, pelo `workflow_dispatch` dele, depois da validação do chat.
8. **Issues.** PR mergeado num branch que não é o padrão não fecha issue pelo `Closes #N`. Quem fez cada PR fecha a
   issue depois do merge do lote na `main` e atualiza o Project Autonom.ia Dev.
9. **Rollback** de um lote: `workflow_dispatch` com `action=rollback` e `esperado_sha` nos dois workflows de deploy
   (volta para a instância anterior). Como funciona desde o #1979:
   - o job **Congelar a produção** confere primeiro se a instância anterior veio do commit `esperado_sha` (a tag Name
     dela diz de que run veio). Sem `esperado_sha`, ou com SHA errado, ele para ali, **sem congelar nada**, e o erro
     diz qual SHA a anterior roda e quais instâncias ainda existem;
   - depois **congela** a produção (`/chatwoot/prod/blue-green/deploy-freeze` = `on` no SSM): deploy novo nem pede a
     vez, e o **Desligar a blue** não para nem termina nada;
   - cancela o deploy que ainda não chegou a registrar a green. Cancelado no boot ou no build, ele não toca na
     produção; cancelado depois do build, a limpeza dele reinicia o web da atual por alguns segundos, como em
     qualquer deploy que falha nesse ponto;
   - o rollback pede a **mesma trava** do deploy: espera o deploy que já estava no tráfego terminar, confere o SHA de
     novo e só então troca. Se esse deploy mudou a anterior, o rollback para sem trocar e lista as instâncias com o
     commit de cada uma, para a volta manual;
   - se outro pedido tomar a vez do rollback na trava (só um deploy manual consegue, com a produção congelada), o job
     **Avisar rollback cancelado** falha o run: disparar de novo;
   - a produção **segue congelada** depois do rollback, para o merge seguinte não subir de novo o que foi desfeito.
     Solta com deploy manual (`action=deploy`) e `descongelar=true` depois do conserto na `main`; ele só descongela
     depois de subir. Esse deploy manual também pode perder a vez para outro pedido: conferir que ele chegou ao fim.

   Só volta **um degrau**: a instância de dois deploys atrás é terminada cerca de 5 minutos depois
   de cada deploy. Para desfazer um lote que já tem outro por cima, o caminho é um lote novo com `git revert`. Um lote
   com migration tem o rollback do banco escrito antes, no próprio PR do lote.
10. **Urgência (hotfix).** Um lote de um PR só, com OK do Rodrigo. Respeita a regra 4 (espera os "ok" do lote
    anterior), mas não espera a janela de 2 horas.
11. **Limpeza.** Depois do merge do lote na `main`, cada sessão remove as próprias worktrees. Apagar branch remota (a do
    lote e as dos PRs) segue a regra do `/dev`: precisa do OK do Rodrigo.

## Fila de merge do GitHub (aprovada em 04/10/2026, #959)

Vale para toda sessão e todo agente (Claude, Codex/ChatGPT) e para pessoas. Enquanto o ruleset
`main - fila de merge` não estiver **ativo**, as regras acima continuam valendo como estão.

Com o ruleset ativo:

1. **A `main` só recebe código pela fila.** Merge direto fica bloqueado. Só administradores do repositório
   passam por cima (`gh pr merge --admin`), e só em emergência: esse push não roda a CI depois.
2. **Checks obrigatórios:** `RSpec` (um check só, que agrega as partes), `Vitest`, `trava`, `central` e
   `fork-i18n`. Rubocop, Brakeman e ESLint seguem informativos e não rodam na fila.
3. **Como mergear:** com OK do Rodrigo e os checks verdes, `gh pr merge <N> --match-head-commit <sha>` põe o
   PR na fila (o repositório tem `allow_auto_merge` ligado: é por ele que o `gh` entra na fila). O comando sai
   com sucesso **antes** do merge. Só conta como mergeado quando `gh pr view <N> --json state` mostrar
   `MERGED`. A posição na fila: `gh api graphql -f query='query{repository(owner:"autonom-ia2",name:"chat"){pullRequest(number:N){state isInMergeQueue mergeQueueEntry{state position}}}}'`.
4. **A fila substitui o lote manual.** Ela junta até 7 PRs por rodada (eram 2 até 07/10/2026; desde então `grouping_strategy: HEADGREEN`: basta o
   commit do topo do grupo, que contém todos os PRs, passar nos checks), testa o código combinado uma vez e faz
   um único push na `main`, que gera um único deploy. Não é mais preciso combinar janela por mensagem nem
   montar `release/*-loteN` para juntar PRs. A validação depois do deploy (regra 4, "ok, SHA") continua.
5. **O "Testes do fork" e o "fork-i18n" não rodam no push da `main`:** a fila já testou exatamente aquele
   commit, e a rodada extra disputava runner com o deploy de produção (medido em 04/10: deploy ~1 min na fila).
   Fila ativa e testada em 04/10/2026 (#969).
6. **PRs abertos antes da mudança** precisam de `gh pr update-branch <N>` (ou um push novo) para rodar os
   workflows novos e ganhar o check `RSpec`.

Configuração versionada em [`docs/ci/ruleset-fila-de-merge.json`](ci/ruleset-fila-de-merge.json):

```sh
# criar desativado e conferir
gh api -X POST repos/autonom-ia2/chat/rulesets --input docs/ci/ruleset-fila-de-merge.json --jq '.id'
gh api repos/autonom-ia2/chat/rules/branches/main
# ativar
gh api -X PUT repos/autonom-ia2/chat/rulesets/<id> -f enforcement=active
# rollback imediato (volta ao fluxo antigo)
gh api -X PUT repos/autonom-ia2/chat/rulesets/<id> -f enforcement=disabled
```

O rollback de deploy (`workflow_dispatch` com `action=rollback`) não passa pela `main` e não é afetado.

### Medições de 04/10/2026 (#959, #961)

| Etapa | Antes | Depois |
|---|---|---|
| CI de PR: nó mais lento do RSpec | 502 s (divisão alfabética) | 299 s (divisão por tempo + cache do Vite) |
| Compilação dos assets de teste do Vite | ~85 s em cada nó | cache entre rodadas |
| Do merge até a troca de tráfego | ~9 a 10 min | igual (fases do deploy em PR próprio) |
| Conferência e "ok, SHA" depois da troca | ~5,5 min (esperava o fim do workflow) | segundos (confere na troca) |

O estresse com 7, 8 e 9 nós (disparo manual do `testes.yml` com `shards`) expôs três defeitos que a ordem fixa
escondia, todos corrigidos na causa: ciclo de carga `AutomationRule`/`AutomationRuleSchema` (#963), listas sem
desempate na ordenação (#965) e `Current` vazando entre specs (#966). Diante de falha que depende de ordem,
o `plan.json` da rodada (artefato `rspec-plan`) reproduz o grupo exato do nó.

## Melhorias propostas, pendentes de OK do Rodrigo

- **Cache do build** (camadas do Docker entre execuções): encurta a etapa mais longa sem mudar o que é publicado.
- **Imagem única para as duas stacks:** buildar uma vez e publicar nos dois ECRs (contas 354307071110 e 140023375763).
  Mexe em IAM entre contas, então é infra e vai em PR separado, com rollback.
- **Filtro de caminhos dos workflows:** deixar de ignorar os `.md` que o sistema lê em produção.
