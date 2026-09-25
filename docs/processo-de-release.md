# Trem de release do chat2you

Combinado em 25/09/2026 entre as sessões Prospecção (#676), Cotação e Central/Guia e CRM, a pedido do Rodrigo:
subir junto o que estiver pronto, com um deploy só, em vez de um deploy de ~40 minutos por PR.

## Por que existe

Todo merge na `main` dispara o deploy blue-green completo nas duas stacks (hub2you e autonomia). Os workflows usam
`concurrency` com `cancel-in-progress: false`, então merges seguidos não se cancelam: viram deploys em fila. Medido em
25/09: cerca de 24 minutos são o build da imagem (feito uma vez por stack, sem cache), 3 minutos a subida e a saúde
da instância nova e 5,5 minutos o desligamento da antiga.

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

## Melhorias propostas, pendentes de OK do Rodrigo

- **Cache do build** (camadas do Docker entre execuções): encurta a etapa mais longa sem mudar o que é publicado.
- **Imagem única para as duas stacks:** buildar uma vez e publicar nos dois ECRs (contas 354307071110 e 140023375763).
  Mexe em IAM entre contas, então é infra e vai em PR separado, com rollback.
- **Filtro de caminhos dos workflows:** deixar de ignorar os `.md` que o sistema lê em produção.
