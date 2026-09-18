# #436 — dois P2s e proveniência de entrega

Data: 2026-09-17. Alterações prontas para runtime pelo parent; nenhum resultado novo de
Rails/RSpec ou medição SQL é alegado nesta rodada.

## Evidência e escopo

Lidos `AGENTS.md`, `tmp/email436/reports-independent-review.md`, o código real dos presenters,
controllers, Jbuilders, models/policies e os contratos de RecipientState, PreflightDecision,
Evaluator/Payload. Busca em Enterprise não encontrou implementações correspondentes desses
relatórios. O arquivo `tmp/email436/reports-contract-third.json` registra 61 exemplos, zero
falhas, zero pending no runtime anterior do parent. As correções de fixtures pending,
autenticação por token e o campo aditivo `resume_allowed: false` foram preservadas.

Sem Git, banco, Rails, RSpec, rede, instalações, secrets, UI, operações de produção ou backfill.
Não houve alteração em entrega/reputação core. Branch/PR/Project e runtime ficam com o parent.

## Mudanças

1. **P2 da lista:** CampaignsController cria CampaignBatch somente para a coleção autorizada.
   Três agregações de higiene por coleção substituem 3N: não enviados/classificação, aceitos
   com sent_at e issues. A classificação foi extraída sem mudança de precedência para
   RecipientState e continua compartilhada com o detalhe. Membership usa uma consulta;
   qualquer import ativo usa uma consulta de IDs distintos; candidatos e pendências enforce
   usam até duas consultas de IDs distintos, reutilizando RecipientState e PreflightDecision.
   Sem recipients/events materializados, N suppression sets ou locks de leitura. O número de
   queries é limitado, não o volume de trabalho do banco. Contexto dura somente um request;
   novo GET/detalhe relê proteção, validade e expiração. Zeros e denominadores preservados.
2. **P2 de erro reputacional:** blocked estritamente true sem código conhecido vira o DTO
   reputation/reputation_paused, overridable false, resume_allowed false. Causas aninhadas
   conhecidas têm precedência, inclusive provider e technical. A resposta continua limitada
   à allowlist pública, sem métricas internas, actor, note ou razão livre. Nenhum release.
3. **Proveniência:** delivery_mode do enum persistido da campanha em reports.campaigns[],
   detalhe, cada destinatário, meta dos destinatários (inclusive página vazia) e timeline.
   Query params e payloads dos eventos não determinam o valor. Nenhuma mudança em status
   bruto, delivered, séries legadas ou CSV. Summary misto usa delivery_evidence existente.
   Contrato informa à UI que direct_inbox delivered é aceitação pelo provedor, não confirmação
   do destinatário. Implementação visual permanece com o owner separado.

## Regressões adicionadas — execução pendente

- Novo request spec compara GETs reais de 1 e 20 campanhas sent/paused/sending em
  shadow/enforce, medindo `sql.active_record` inclusive queries em cache. Mantém Hygiene
  real; limita crescimento total, queries de recipients e issues. Verifica também import
  ativo, capacidade de retomada e ausência de locks nas tabelas do domínio.
- Lista/detalhe: mesma classificação, capacidades, zeros/no_data, legado versus outro tenant,
  proteção forte com expires_at passado, expiração temporária e releitura por novo contexto.
  Detalhe Hygiene reutilizado também refaz as consultas. A pausa e os recipients não mudam.
- Erros: bloqueio explícito, booleanos inválidos, causa técnica/provedor aninhada prioritária.
  Request existente de resume com reclamação real agora exige reputation_paused, flags false
  e somente as chaves públicas; o coletor/evaluator real continua no caminho desse teste.
- Relatórios SES/direct na mesma conta: total legado delivered preservado, delivery_evidence
  misto e delivery_mode nos quatro pontos HTTP; evento SES com payload via=direct_inbox não
  muda a proveniência. Inclui parâmetros não confiáveis e meta de lista vazia.

## Checks efetivamente executados

- Ruby 3.4.4 `-c`: **13 arquivos, todos Syntax OK**, após a edição final.
- RuboCop: **13 files inspected, no offenses detected** (exit 0), após correções locais de
  alinhamento/comprimento e literais do teste. Somente o manifesto abaixo foi lintado.
- Verificação Python de espaços finais: nenhum nos 13 Ruby e no contrato.
- Inventário SHA-256 anterior/posterior em 204 arquivos preexistentes dos serviços de email,
  controllers/Jbuilders, specs do domínio e docs: 12 alterados previstos, **192 intactos**,
  nenhum arquivo preexistente fora do manifesto mudou no momento da comparação. Isso inclui
  `spec/requests/api/v1/accounts/email_campaigns/reputation_spec.rb` do parent.

A tentativa inicial de `rbenv init - zsh` encontrou `rbenv: command not found`. Sem instalar
ou mudar configuração, os checks usaram diretamente o Ruby já instalado em
`/Users/rodrigosilva/.rbenv/versions/3.4.4/bin`, com ambiente limpo. Comando final de lint:

```sh
env -i PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:/usr/bin:/bin RUBOCOP_CACHE_ROOT=/private/tmp/436-p2-rubocop /bin/zsh -c 'bundle exec rubocop --no-server --cache false --format simple $(cat /private/tmp/436-p2-ruby-manifest.txt)'
```

O parser usou esse mesmo Ruby, `-c` por arquivo, via subprocess em ambiente sem carregamento
da aplicação. O inventário e o manifesto temporários estão em `/private/tmp/436-p2-before.json`
e `/private/tmp/436-p2-ruby-manifest.txt`. Nenhum `git diff` foi executado.

## Manifesto desta rodada

```text
app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb
app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb
app/services/email_campaigns/presentation/campaign.rb
app/services/email_campaigns/presentation/campaign_batch.rb (novo)
app/services/email_campaigns/presentation/errors.rb
app/services/email_campaigns/presentation/hygiene.rb
app/services/email_campaigns/presentation/protection.rb
app/services/email_campaigns/presentation/recipients.rb
app/services/email_campaigns/reports/builder.rb
app/services/email_campaigns/reports/recipient_state.rb
spec/requests/api/v1/accounts/email_campaigns/reports_integration_436_spec.rb
spec/requests/api/v1/accounts/email_campaigns/reports_query_budget_436_spec.rb (novo)
spec/services/email_campaigns/reports/presentation_436_spec.rb
docs/email-campaigns/reports.md
docs/audit/436-reports-p2-provenance.md (novo)
```

## Handoff

Parent deve incluir explicitamente `reports_query_budget_436_spec.rb` no rerun dos relatórios
(215+ e novos exemplos) e baseline, no harness já preparado. Não executar somente a lista
antiga de arquivos, pois ela omite o novo request spec. As seis comparações de orçamento SQL,
o HTTP de resume bloqueado e os pontos de proveniência precisam passar no runtime. Os 61
exemplos anteriores e checks estáticos não comprovam o comportamento desta rodada. Nenhuma
outra arquitetura/operação ou mudança de UI faz parte deste handoff.

## Fechamento funcional pelo integrador

A suíte cumulativa de higiene/reputação/relatórios passou em **714 exemplos RSpec, zero falhas**, com apenas **um pending preexistente** de Account. Incluiu explicitamente o novo orçamento SQL de 1 versus20 campanhas (sent/paused/sending, shadow/enforce), o erro sanitizado de pausa reputacional e a proveniência de entrega nos endpoints. As 19 verificações HTTP de relatório foram repetidas após ajuste de estilo, todas aprovadas usando autenticação real por token; não houve stub do mecanismo de autenticação.

RuboCop cumulativo: **151 arquivos sem infrações**. Os dois achados adversariais estão fechados com as respectivas regressões reais. A resposta de erro mantém `resume_allowed: false`; testes antigos de retomada receberam destinatário pending explícito para não depender de campanha vazia. A projeção pública normaliza pause_reason sem alterar o registro estruturado interno.

Evidências: `tmp/email436/reports-closed.json`, `reports-closed-rubocop.log`, `reports-auth-final.log`. Ambiente exclusivamente sintético em loopback, sem rede externa de envio, credenciais herdadas, produção, merge ou deploy. CI remoto ainda deve ser confirmado no SHA publicado; UI e operações serão integradas e revalidadas na sequência.
