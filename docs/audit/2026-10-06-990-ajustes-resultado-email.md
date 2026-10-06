# #990 — ajustes da Campanha e do Resultado de e-mail (06/10/2026)

## Causa raiz

- **"Sem data" na lista**: `campaignRows.js` datava o e-mail por `sent_at || scheduled_at`. `sent_at` só é gravado
  no fim do envio (`EmailCampaign#finalize!`); envio imediato não tem `scheduled_at`. Pausada/enviando ficava sem
  data. WhatsApp API/Oficial/SMS também liam só `scheduled_at`.
  Correção: `EmailCampaign#first_sent_at` (menor `sent_at` dos destinatários), exposto como `started_at` no
  JSON da campanha (mesma consulta agrupada do `historical_sent`, sem consulta extra na lista) e no Resultado;
  a lista escolhe a data por situação (agendada → agendamento; enviando/pausada/encerrada → início; rascunho → criação).
- **Bloco "Envio pausado" e destinatários com visual antigo**: o Resultado (#1007) reaproveitava os componentes da
  Gestão. As regras e chamadas foram extraídas para composables (`useProtectionState`, `useEmailHealthActions`,
  `useEmailRecipients`, `hygieneCounts`) usados pelos dois; a Gestão mantém o template, o Resultado ganhou
  componentes próprios (`ResultProtectionCard`, `ResultHygieneCard`, `ResultEmailRecipients`).
- **Cliques por link**: a URL era texto. Agora só http/https viram link (`new URL`, sem regex), em nova aba.

## Validação

Vitest (TZ=UTC) das pastas CampaignResult, CampaignJourney, EmailProtection e campaigns: 48 arquivos, 690 testes ok.
RSpec e-mail/jornada: 898 exemplos; 2 falhas de manutenção por linhas de `email_suppression_events` deixadas por
outra spec no banco local (passam isoladas, não relacionadas). `i18n:fork:check`, `guia:check`,
`autonomia:guia:formatos:check` e rubocop ok.
