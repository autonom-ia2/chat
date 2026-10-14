# #1449 — pedido de parar na resposta a campanha marca o contato (IA decide)

Data: 14/10/2026. Branch `feat/1449-optout-campanha-ia`. Part of #1320.

## Decisões

- Quem decide é o modelo: reaproveitado `Crm::Ai::OptOutClassifier` do follow-up (#1317). O prompt é o da main,
  literal (decisão do Rodrigo, 14/10: o follow-up em produção não muda de comportamento). Mudam só dois parâmetros
  opcionais: `feature:` (padrão `follow_up_saida`) e `previous_message:` (sem ele, vale a última enviada antes da
  resposta, como hoje; a campanha passa o texto dela, porque a mensagem gravada na resposta tem id maior que a resposta).
  Uma redação neutra chegou a ser testada e foi descartada: marcou "sim" falso mais vezes (abaixo).
- Origem nova `campaign_reply` em `OPT_OUT_SOURCES` e na fusão logo depois de `follow_up_reply`.
- A recusa vale pelo número (decisão do Rodrigo, 14/10): o contato marcado guarda o telefone em
  `additional_attributes.campaign_reply_phone` e é a prova (`Contacts::CampaignReplyOptOut`). Contato novo, ou que passa
  a ter esse telefone, herda (`Contacts::OptOutInheritance`), mesmo que o original tenha trocado de número. Desfazer no
  painel solta o número inteiro. Limite: apagar o contato original apaga a prova.
- A equipe desfaz `campaign_reply` no painel do contato (é a única tela dela; corrige engano da IA).
- O chamador passa `previous_message` sempre como texto (`content.to_s`): campanha só com mídia vai como "" (aceite do
  Followup IA em a5add37f5f).
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

## Bateria com IA real (14/10/2026)

Autorizada pelo Rodrigo até US$ 0,20. Chave da conta 16 lida por psql READ ONLY via SSM para um arquivo 600, lida só
pelo script e apagada depois; erro só com a classe. Modelo `gpt-6-luna`. 30 frases sintéticas, sem nome real
(15 de follow-up, 15 de campanha); registros de teste numa transação desfeita.
**Custo total: US$ 0,0216** (US$ 0,0123 com a redação neutra, descartada, e US$ 0,0093 com o prompt da main).

### Rodada 1 — redação neutra (descartada)

- Follow-up, main x branch: 14 de 15 iguais. "pode parar de me ligar e manda por aqui" deu "sim" 4 em 26 com a redação
  nova contra 1 em 26 com a da main. Por isso o texto voltou ao da main.

### Rodada 2 — prompt da main literal (o que vai no PR)

Follow-up, classificador da main (ANTES) x o desta branch (DEPOIS), mesma entrada: **15 de 15 iguais**.
"pode parar de me ligar e manda por aqui", 20 vezes cada: **ANTES "nao" 20/20, DEPOIS "nao" 20/20**.

| caso (follow-up) | esperado | antes = depois |
|---|---|---|
| "Por favor, parem de me mandar mensagem", "SAIR", "não quero mais receber isso", "me tira dessa lista", "chega, não me procurem mais" | sim | sim |
| "agora não, obrigado", "quanto custa?", "vou sair agora...", "já fechei com outro", "pode parar de me ligar e manda por aqui", "cancelar a reunião", "depois eu vejo" | nao | nao |
| emoji | nao_se_aplica | nao_se_aplica |
| "sai", "não tenho interesse" | livre | nao |

Campanha (feature `campanha_opt_out`, o texto da campanha como `previous_message`):

| caso | esperado | resultado |
|---|---|---|
| "para de mandar", "SAIR", "Não quero receber promoções", "parem com esse spam", "descadastrar" | sim | sim |
| "agora não, obrigado", "quanto custa?", "pode parar de me ligar e manda por aqui", "quero sim...", "quem é você?", "hoje não dá...", "não tenho interesse nessa oferta" | nao | nao |
| emoji | nao_se_aplica | nao_se_aplica |
| "sai" | livre | nao |
| "não quero mais" | sim | **nao** |

## Decisão registrada

- "não quero mais", sozinho, na resposta a uma campanha, não marca (nao em todas as rodadas): o modelo lê como recusa da
  oferta, e na dúvida não se marca. Fica assim (Rodrigo, 14/10).
