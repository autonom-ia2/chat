# #1449 — pedido de parar na resposta a campanha marca o contato (IA decide)

Data: 14/10/2026. Branch `feat/1449-optout-campanha-ia`. Part of #1320.

## Decisões

- Quem decide é o modelo: reaproveitado `Crm::Ai::OptOutClassifier` do follow-up (#1317). Aceite do chat Followup IA
  para trocar só `feature:` (padrão `follow_up_saida`) e a redação neutra ("acompanhamento ou campanha"; saiu "a cadência
  já parou com a resposta"). Schema, decisões, motivos e enum iguais. Depois da revisão entrou também
  `previous_message:` opcional (sem ele, o follow-up segue igual), porque a mensagem da campanha gravada na resposta tem
  id maior que a resposta.
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
pelo script e apagada depois; erro só com a classe. Modelo `gpt-6-luna` (o do classificador). 30 frases sintéticas,
sem nome real; registros de teste numa transação desfeita. **Custo total: US$ 0,0123** (0,0037 na bateria + 0,0086 em duas
rodadas de repetição).

Follow-up: classificador da main (ANTES) x o desta branch (DEPOIS), mesma entrada.

| caso | esperado | antes | depois |
|---|---|---|---|
| pedido claro de parar (4 frases, incl. "SAIR", "me tira dessa lista") | sim | sim | sim |
| "chega, não me procurem mais" | sim | sim | sim |
| adiar, preço, "vou sair agora...", "já fechei com outro", "cancelar a reunião", "depois eu vejo" | nao | nao | nao |
| emoji | nao_se_aplica | nao_se_aplica | nao_se_aplica |
| "sai" | livre | nao (ambigua) | nao (ambigua) |
| "não tenho interesse" | livre | nao | nao |
| "pode parar de me ligar e manda por aqui" | nao | sim 1 de 26 | **sim 4 de 26** (1ª rodada + 5 + 20 repetições) |

14 de 15 iguais na primeira rodada. Na única diferença, o modelo varia nos dois prompts; com a redação nova o "sim"
errado apareceu um pouco mais (4/26 contra 1/26). A amostra não separa com segurança variação de efeito do prompt.

Campanha (só DEPOIS, feature `campanha_opt_out`, a campanha como `previous_message`):

| caso | esperado | resultado |
|---|---|---|
| "para de mandar", "SAIR", "Não quero receber promoções", "parem com esse spam", "descadastrar" | sim | sim |
| "agora não, obrigado", "quanto custa?", "quero sim...", "quem é você?", "hoje não dá...", "não tenho interesse nessa oferta" | nao | nao |
| emoji | nao_se_aplica | nao_se_aplica |
| "sai" | livre | nao (ambigua) |
| "pode parar de me ligar e manda por aqui" | nao | nao; na repetição, **sim 1 de 3** |
| "não quero mais" | sim | **nao** 4/4 (2 textos de campanha diferentes): o modelo lê como recusa da oferta |

## Pendente (decisão do Rodrigo)

- "não quero mais", sozinho, não marca: o modelo entende como recusa da oferta e, na dúvida, não marca. Mudar exige
  mexer no prompt do classificador, que é compartilhado com o follow-up.
- "pode parar de me ligar e manda por aqui": falso positivo ocasional. Campanha 1 em 4; follow-up 4 em 26 com a
  redação nova contra 1 em 26 com a da main. Se for para o follow-up ficar idêntico à main, a saída é manter o texto
  antigo (só o `feature:` e o `previous_message:` mudam) e aceitar "acompanhamento" na pergunta da campanha.
