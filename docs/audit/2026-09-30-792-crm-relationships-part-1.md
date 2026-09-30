# #792 — Parte 1: proteção do vínculo de contato no CRM

**Data:** 30/09/2026. **Estado:** incremento local concluído; pausa para aprovação de Rodrigo. Não é conclusão de M02 nem do plano completo. Não houve merge ou deploy desta frente.

## Base e isolamento

- Issue: `autonom-ia2/chat#792`.
- Branch: `feat/792-crm-relacionamentos`.
- Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you-792-crm-relacionamentos`.
- Base inicial e baseline: `1d7f051a2655ef98cdc6ac70fa8b6f1a89c4cfe7`.
- A main avançou durante o trabalho com o PR #790. O delta foi lido e não alterou ContactLinker, seus contratos de teste ou AGENTS.md. A branch exclusiva foi atualizada por rebase, sem conflito, sobre `e45fbe68945f948525dcc0a2997eae5c3c9dc74f`.
- Commit de código validado depois do rebase: `674daffcffbeeda4270fc4faa5b469e574417f49`.
- A cópia principal estava em `fix/crm-timeline-ai-labels`, com alterações de outras frentes. Não foi convertida na branch desta tarefa nem seus arquivos editados por esta frente.
- Ruby 3.4.4 já instalado; `bundle check` aprovado. PostgreSQL real local, banco exclusivo novo `chat2you_792_test`, carregado de `db/schema.rb`. Redis exclusivo em `127.0.0.1:6792`, sem tocar o Redis compartilhado em 6379.
- `RAILS_ENV=test`, banco explicitamente em loopback, ActiveJob e ActionMailer em modo de teste, WebMock bloqueando HTTP externo. Nenhuma base/credencial da AWS foi usada.
- Wrapper e logs locais em `.codex/792/`, ignorados pelo Git. Hooks nativos habilitados e executados; lint-staged não tinha arquivos JS/Vue elegíveis. Node modules já existentes foram referenciados somente para as ferramentas locais, sem instalação ou mudança de lockfile.

## Escopo entregue e revisão do código

A implementação altera apenas o serviço existente de vínculo e uma mensagem do catálogo backend. O controle de conta e de acesso permanece nas políticas/modelos atuais. Não modifica autorização nem introduz regex.

1. Lock de linha do card recarrega o contato persistido antes de agir e auditar. Isso corrige também a perda de atualização ao usar um objeto antigo que ainda acredita ter o contato de antes.
2. Troca para outra pessoa é rejeitada se houver conversa primária ou secundária de um contato diferente. O teste inclui primária legada sem linha em `crm_card_conversations`.
3. Repetição do mesmo vínculo/desvínculo é no-op para os dados do card e atividade. Não é uma garantia sobre deduplicação de broadcasts.
4. Auditoria de troca inclui ID antigo e novo, preservando o campo `contact_id` existente. Falha no registro da atividade reverte a alteração do vínculo.
5. Desvincular não apaga pessoa nem conversas. A tentativa de contornar o conflito desvinculando primeiro é testada e rejeitada.
6. Erros reutilizam o HTTP 422 de `RequestExceptionHandler`, sem expor identidade/conteúdo das conversas no corpo da resposta.

A revisão desta parte foi uma releitura do diff, dos chamadores, das validações, dos testes novos e dos contratos de erro. Não foi uma revisão independente por outra pessoa/agente. A revisão independente do conjunto continua pendente para a liberação final.

## Evidências executadas

| Execução | Resultado |
|---|---|
| Baseline antes da alteração, 4 arquivos de specs existentes | 38 exemplos; 35 passaram, 0 falhas, 3 suspensos existentes. |
| Testes novos de serviço, antes da correção | 14 exemplos; 9 falhas reproduzindo o comportamento a corrigir. Dois erros iniciais de preparação lazy das fixtures foram corrigidos antes de registrar este resultado. |
| Testes novos de serviço, depois da correção | 14 exemplos; 14 passaram, 0 falhas. |
| Bateria ampliada, serviço + API + regressão de cards | 86 exemplos; 83 passaram, 0 falhas, 3 suspensos existentes. |
| Mesma bateria após rebase, ordem aleatória seed 792 | 86 exemplos; 83 passaram, 0 falhas, mesmos 3 suspensos. |
| RuboCop nos 3 arquivos Ruby desta parte | 3 arquivos inspecionados, nenhuma infração. Também passou no hook de commit. |
| `git diff --check` | Sem erros de whitespace. |

São **24 testes novos**: 14 de serviço e 10 de requisição HTTP. Usam persistência real no PostgreSQL de teste, não armazenamento do HTML. Na bateria ampliada foram incluídos outros testes existentes além da bateria inicial; não se apresenta o conjunto ampliado como se todos os seus testes tivessem sido executados antes da alteração.

Uma primeira execução dos testes de API falhou por uma fixture que não tinha e-mail ao testar não divulgação; a fixture foi corrigida com e-mail fictício explícito. A execução final acima passou. Warnings antigos de enums Rails e de `unprocessable_entity` continuam presentes; não foram tratados como falhas nem removidos por supressão.

### Cobertura nova

- Vínculo e troca válidos preservam pessoa, título, valor, moeda, etapa e demais dados comerciais.
- Troca registra IDs de origem/destino.
- Conflito com primária legada, secundária e combinação de ambas.
- Vínculo com o dono legítimo das conversas permitido.
- Repetição sem nova atividade/timestamp.
- Card desatualizado: troca, remoção e primária adicionada após carregamento.
- Falha simulada de auditoria reverte a mudança.
- Conta diferente e requisição sem autenticação rejeitadas.
- Resposta de conflito sem conteúdo ou identidade das conversas.
- Nenhuma nova conversa, mensagem, follow-up ou entrega de e-mail na operação testada.

### Três testes antigos suspensos, não aprovados

Em `spec/requests/api/v1/accounts/crm/cards_spec.rb`, com `QUARANTINE: legacy CI failure (PR2)`:

- Linha 333: sanitização de conversa primária oculta no índice de cards para agentes.
- Linha 556: detalhes de conversas vinculadas no Kanban.
- Linha 583: sanitização de conversa primária oculta no Kanban para agentes.

As três suspensões já existiam no baseline e não foram alteradas. A ausência de falhas nos testes executados não elimina essas lacunas; elas precisam constar da análise final de regressão e permissões.

## Reexecução local

Exige worktree desta branch, Ruby 3.4.4 com gems do lockfile, banco PostgreSQL **novo de teste**, Redis exclusivo local e nenhuma credencial de produção. O wrapper ignorado `.codex/792/test.sh` configura `RAILS_ENV=test`, `DATABASE_URL=postgresql://postgres@127.0.0.1:5432/chat2you_792_test`, `REDIS_URL=redis://127.0.0.1:6792/0` e usa `bundle exec`. Não apontar esse wrapper para base de outra frente. O Redis exclusivo pode ser desligado no checkpoint; reabrir somente essa instância ao retomar.

Com esses serviços locais disponíveis, a bateria final foi:

```bash
bash .codex/792/test.sh rspec \
  spec/models/crm/card_spec.rb \
  spec/services/crm/cards \
  spec/requests/api/v1/accounts/crm/cards_spec.rb \
  spec/requests/api/v1/accounts/crm/card_contact_links_spec.rb \
  --seed 792 --format progress \
  --format json --out .codex/792/regression-final.json
```

Logs locais: `baseline.log`, `m02-red.log`, `m02-green.log`, `regression.log`, `regression-final.log`, `regression-final.json`, `rubocop.log`. Não contêm credenciais de produção; não foram copiados em massa para o repositório.

## Limites e próximos passos

Não foram implementados a interface M01–M08, criação composta, normalização/duplicidade, contato somente com nome, mídias ou navegação. Não há capturas visuais a aprovar nesta parte.

Esta proteção pertence a `ContactLinker`. O `ConversationLinker`, upsert externo, criação e outros escritores ainda serão revisados: um lock neste serviço não comprova segurança de concorrência com outro serviço que não usa o mesmo protocolo. Os testes de objeto antigo são determinísticos; não foram descritos como teste de duas transações realmente simultâneas. Não corrigir ou associar registros históricos por suposição.

A versão efetivamente publicada na AWS e as flags não foram consultadas. O merge do PR #790 no GitHub foi confirmado; seu deploy não foi inferido. Conferir esses pontos antes da camada de integração visual e antes de publicar o conjunto. O trabalho local desta parte não dependeu de ativação de flags em produção.

O conector específico do Project falhou por conexão; o acesso pelo `gh` autenticado funcionou. A Issue foi adicionada ao Project Autonom.ia Dev e os sete campos obrigatórios foram preenchidos. No checkpoint, a próxima ação deve ser a aprovação de Rodrigo, não continuação automática.

**Proposta para a próxima parte, ainda não autorizada:** criar contato a partir de card sem vínculo, em transação, mantendo o mesmo ID da oportunidade. A aprovação dessa etapa não autoriza merge/deploy.

## Release e rollback

Este checkpoint fica em branch e PR de rascunho, sem auto-merge. Os workflows `deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml` foram lidos: push na main com código pode publicar as duas instalações; não usar merge parcial como teste. Nenhum workflow de publicação foi acionado por esta frente.

A parte 1 não cria migração, schema, flag ou dependência nova. A reversão de seu código não depende de remover contatos/empresas/atividades. O plano de rollback da entrega completa deverá considerar os dados criados nas partes futuras e só será executado com autorização. A regra de liberação continua: plano inteiro revisado/testado, pendências críticas resolvidas, aprovação explícita de Rodrigo para merge e escopo de deploy.
