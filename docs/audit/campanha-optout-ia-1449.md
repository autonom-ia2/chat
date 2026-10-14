# #1449 — pedido de parar na resposta a campanha marca o contato (IA decide)

Data: 14/10/2026. Branch `feat/1449-optout-campanha-ia`. Part of #1320.

## Decisões

- Quem decide é o modelo: reaproveitado `Crm::Ai::OptOutClassifier` do follow-up (#1317). Aceite do chat Followup IA
  para trocar só `feature:` (padrão `follow_up_saida`) e a redação neutra ("acompanhamento ou campanha"; saiu "a cadência
  já parou com a resposta"). Schema, decisões, motivos e enum iguais. Depois da revisão entrou também
  `previous_message:` opcional (sem ele, o follow-up segue igual), porque a mensagem da campanha gravada na resposta tem
  id maior que a resposta.
- Origem nova `campaign_reply` em `OPT_OUT_SOURCES` e na fusão logo depois de `follow_up_reply`. Não entra na herança:
  como a manual, não tem prova fora do contato.
- A equipe desfaz `campaign_reply` no painel do contato (é a única tela dela; corrige engano da IA).
- Sem flag (decisão do Rodrigo, via Orquestração): ligado em todas as contas; conta sem chave própria usa a da plataforma
  (`CredentialResolver`). Sem chave nenhuma: não marca, log só com ids.
- Teto: 500 mensagens avaliadas por conta por dia (UTC), uma vaga por mensagem (Redis, SET NX). Custo na Gestão IA em
  "Campanhas", feature `campanha_opt_out`.
- Gatilho: `CampaignJourney::ReplyMarkJob`, depois do `ReplyMarker` (que grava a mensagem da campanha na conversa da
  resposta). Só a primeira resposta com texto, só se a última mensagem pública antes dela for de campanha, até 7 dias.
  Botão (`content_attributes.selected_option`) não vai ao modelo.

## Validação (local, cliente de IA falso)

- rspec da área: 345 exemplos, 0 falhas (campaign_journey, opt-out do contato, fusão, Gestão IA, follow-up).
- vitest `ContactOptOut`: 15/15. eslint, rubocop, `guia:check`, `central:check`, `i18n:fork:check`,
  `autonomia:guia:formatos:check`: em dia.
- Tela real (painel local, conta seed): selo com a origem, explicação, "Desfazer recusa" e o diálogo; desfazer pela tela
  tirou a recusa no banco.

## Pendente

- Bateria com IA real (~20 respostas, teto US$ 0,20): suspensa até o Rodrigo definir o orçamento (prompt de
  classificador em produção).
