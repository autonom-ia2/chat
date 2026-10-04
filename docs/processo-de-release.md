# Trem de release do chat2you

Combinado em 25/09/2026 entre as sessões Prospecção (#676), Cotação e Central/Guia e CRM, a pedido do Rodrigo:
subir junto o que estiver pronto, com um deploy só, em vez de um deploy de ~40 minutos por PR.

## Por que existe

Todo merge na `main` dispara o deploy blue-green completo nas duas stacks (hub2you e autonomia). Os workflows usam
`concurrency` com `cancel-in-progress: false`, então merges seguidos não se cancelam: viram deploys em fila. Medido em
25/09: cerca de 24 minutos são o build da imagem (feito uma vez por stack, sem cache), 3 minutos a subida e a saúde
da instância nova e 5,5 minutos o desligamento da antiga. Em 04/10, com o cache do build no ECR, foram 3 min 38 s de
build e 3 min 04 s de boot, que vinha depois do build (8 min 22 s do disparo à troca do tráfego). Desde o #974 a
instância nova liga antes do build e espera a imagem chegar ao ECR, então o boot quase todo corre junto com o build.

## Regras

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
9. **Rollback** de um lote: `workflow_dispatch` com `action=rollback` nos dois workflows de deploy (volta para a
   instância anterior). Só volta **um degrau**: a instância de dois deploys atrás é terminada cerca de 5 minutos depois
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
4. **A fila substitui o lote manual.** Ela junta até 2 PRs por rodada, testa o código combinado uma vez e faz
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
