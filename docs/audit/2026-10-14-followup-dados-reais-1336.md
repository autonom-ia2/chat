# #1336 — Follow-up de IA com dados reais do card nos modelos

Épico #1320 (Modelos WhatsApp, item 14 do PRD). Issue de liga: #1522.

## Decisões

- **Ponto de extensão** (sessão Followup IA, 14/10): `Crm::FollowUps::TemplateCandidates` ganha `card:` opcional e é o
  único lugar da seleção, para o `AutoFollowupRunner` e o `CallbackRunner`. Sem `card:` ou com a flag desligada, nada
  muda. O prompt do compositor não muda (mexer nele pede eval pago): a IA recebe o body já escrito com o dado real e só
  as posições que sobram. O valor real (`filled`) não vai para a IA e vence o que ela devolver, nos dois runners, só em
  modelo nativo.
- **De onde vem o dado:** o perfil do modelo (`WhatsappTemplateProfile#fields`) liga a posição a uma chave do catálogo
  (`TemplateFields`); o valor sai de `TemplateFields::Resolver.for_card`. Chave nova `negocio.prazo` =
  `expected_close_at`, lido como dia de calendário em UTC (a tela grava "AAAA-MM-DD" como 00:00 UTC; no fuso da conta
  sairia um dia antes, #1535). Valor pelos centavos (`value_cents` + `currency`); 0 é "sem valor".
- **Card sem o dado** (Rodrigo, 14/10: "outro modelo; sem nenhum, texto"): o modelo sai da lista; a IA escolhe outro;
  sem nenhum, Híbrido quando a caixa tem, senão `no_template`, como hoje. Regra só em
  `TemplateRealValues#without_real_value`.
- **Flag:** `followup_template_real_values`, bit 21 da `feature_flags_ext_1` (reservado pela Orquestração), `enabled:
  false`. O bit 22 é da `crm_lembretes_v2`.
- **Perfil repetido entre caixas irmãs da mesma WABA:** vale o da própria caixa; entre os outros, o mais antigo.

## Fora daqui (registrado para o Rodrigo)

- A tela de Modelos ainda não oferece ligar uma variável a `negocio.*`: os rótulos da tela (`valor`, `data`) não são
  chaves do catálogo e seguem com a IA. Até a tela ligar, só modelos com perfil gravado com chave do catálogo usam o
  dado real.
- `atendente.nome` não é preenchido no follow-up (não há "quem atende" num envio automático): modelo com esse campo
  ligado sai da lista.
- `metadata.payment_promise_at` ("prometeu pagar em") entra quando o #1515 estiver na main.

## Validação (14/10/2026, banco `chat2you_test_s`)

- rspec da área (follow_ups, composer, template_fields, campaign_journey, variable_suggester, booking_v2/notices,
  ai/redacao, account, whatsapp_template_profile, crm/access, jobs/crm): 1115 exemplos, 0 falhas, 5 pendentes (já
  existentes).
- Mutações conferidas: inverter o merge (IA vence), manter o modelo sem dado, ignorar a caixa própria e trocar a
  substituição por `gsub` em sequência; cada uma reprova os specs.
- rubocop nos arquivos tocados: sem ofensas. `autonomia:guia:formatos:check`, `pnpm guia:check`, `pnpm central:check`,
  `pnpm i18n:fork:check`: em dia.

## Eval com IA real (#1522, 14/10/2026)

Condição do Followup IA para ligar a flag. Orçamento do Rodrigo: US$ 0,30, chave da conta 16 (lida pela Orquestração
com OK direto dele, cifrada no trânsito, apagada depois). Harness fora do versionamento (`tmp/eval-1336/eval.rb` e
`analyze.rb`): o `FollowUpComposer` real (`gpt-6-luna`, modo `choose_template`), 15 cenários SINTÉTICOS em pares
(flag desligada × ligada). A lista "ligada" sai do próprio `TemplateRealValues`. Teste de fumaça com chave falsa antes:
o valor não aparece na saída, no resultado nem no log. Sem prompt nem resposta crua guardados.

**Custo:** 30 chamadas, US$ 0,0111, nenhum erro.

| Medida (flag ligada) | Resultado |
|---|---|
| Índice escolhido válido | 15/15 |
| Posições que sobram para a IA preenchidas | 15/15 |
| Valor real do card mantido no envio | 15/15 |
| IA tentando escrever posição já preenchida | 0 |
| Sem nenhum modelo sobrando: recusou (`no_fitting_template`) | 3/3 |
| Mesma escolha que com a flag desligada | 8/15 |

Leitura caso a caso:

- **Invenção com a flag desligada (o problema do #1336):** nos 2 casos "nenhum sobra", a IA escolheu o modelo de
  proposta e pôs texto na posição do valor e do responsável ("sua proposta de reforma do telhado está com nossa
  equipe"). Com a flag, esse modelo não é oferecido (o card não tem o dado) e a IA recusa.
- **"Valor com cara de dado" nas posições da IA com a flag ligada (4):** todos são "plano empresarial para 12 vidas",
  texto da própria conversa no modelo genérico. Não é invenção (a métrica conta qualquer dígito).
- **Troca de escolha no orçamento (genérico → retomada, 3 casos):** com o primeiro nome já escrito no body, a IA prefere
  "Oi Talita, tudo bem? Conseguiu avaliar o orçamento da reforma do telhado?" ao genérico sem nome. Melhor.
- **Cobrança com o vencimento visível (2 casos, card completo e sem dono):** com a flag ligada a IA NÃO enviou
  (`should_send` false, `nothing_to_send`); desligada, mandou a retomada "conseguiu pagar o boleto?". Nos 3 casos de
  cobrança em que o modelo com a data sai da lista (sem valor, sem prazo, um sobra) ela enviou. A conversa diz "consigo
  pagar só no dia do vencimento"; com "vence em 20/10/2026" no body e hoje 14/10, o prazo do cliente não venceu. É a
  régua de PRAZO do prompt funcionando com o dado real, não sorteio aparente: a recusa acontece exatamente quando a
  data aparece. Efeito colateral: no runner, essa recusa é terminal (`no_open_loop`, card `spent`), então a cadência
  termina e ninguém cobra depois do vencimento.

**Veredito:** o preenchimento está correto (nenhum valor inventado nem sobrescrito, nenhum modelo sem dado oferecido).
Antes de ligar na conta 16 falta: (1) repetir a cobrança, 10 chamadas (`EVAL_1336_PLAN=repeat`: 3+2 antes do
vencimento com a flag, 2 sem a flag, 3 depois do vencimento com a flag), para separar variação de efeito do dado e
confirmar que depois do vencimento ela envia; (2) decisão do Followup IA/Rodrigo sobre a recusa por "prazo do cliente
ainda não venceu" encerrar a cadência: reagendar para depois do prazo em vez de marcar o card como gasto. Sem (2),
ligar reduz cobranças de quem prometeu pagar no vencimento.

### Repetição da cobrança (10 chamadas, US$ 0,0046; total do eval US$ 0,0157)

| Cobrança, "pago no vencimento" (20/10) | Enviou |
|---|---|
| Antes do vencimento (14/10), flag ligada, card completo | 0/3 (`nothing_to_send`) |
| Antes do vencimento, flag ligada, card sem dono | 1/2 |
| Antes do vencimento, flag desligada (controle) | 2/2 |
| Depois do vencimento (21/10), flag ligada | 3/3 |

Somando as duas rodadas, antes do vencimento: com a flag 1 de 7 envia; sem a flag, 4 de 4. A recusa se repete e é
efeito do vencimento visível no modelo. Depois do vencimento a IA envia (retomada, genérico e, numa, o próprio modelo
de cobrança com R$ 1.890,00 e 20/10/2026 reais, sem tocar nas posições preenchidas).

**Veredito final:** o preenchimento está pronto (nada inventado, nada sobrescrito). Ligar na conta 16 depende só da
decisão sobre a recusa antes do prazo: hoje ela encerra a cadência, e quem prometeu pagar no vencimento deixa de ser
cobrado depois dele. Proposta para o Followup IA: quando a recusa vier com a data do card ainda no futuro, reagendar o
toque para depois dela em vez de marcar o card como gasto. Observação de texto: depois do vencimento, "vence em
20/10/2026" fica no presente; o modelo da conta é quem decide a frase.

## Nova rodada depois do #1591 (15/10/2026)

O #1591 (Followup IA, na main em `5be5020e4e`) mudou o runner: num funil de Atender, se a IA recusa por mérito
(`nothing_to_send`, que vira `no_open_loop`) e o `expected_close_at` do card ainda não passou, o mesmo toque volta
no dia seguinte ao prazo (D+1), no primeiro horário permitido, uma vez por card. A data vem só do card. A flag não
muda essa regra. Worktree atualizada com a main (merge `31863fed3d`).

**Mesma bateria, mesmos cenários:** 30 chamadas na rodada principal + 10 na repetição, `gpt-6-luna`. **Custo:** 40
chamadas, US$ 0,0150 (0,0110 + 0,0040), nenhum erro. Somado às rodadas de 14/10, o eval gastou US$ 0,0307 dos US$ 0,30.
Chave da conta 16 (hook `crm_kanban_ai`, que é a que o `Crm::Ai::CredentialResolver` usa nessa conta) lida de novo
com OK do Rodrigo. O psql só leu (`BEGIN READ ONLY`). O valor foi cifrado no servidor com uma chave RSA pública
(OAEP), e só o cifrado saiu de lá. Antes, um pré-teste com valor falso. A chave decifrada e a chave privada foram
apagadas no fim. Teste de fumaça com chave falsa: o valor não aparece na saída, no resultado nem no log.

| Cobrança, "pago no vencimento" (20/10) | Com a flag | Sem a flag |
|---|---|---|
| Antes do vencimento (14/10): enviou | 1/7 | 4/4 |
| Antes do vencimento: recusou (`nothing_to_send`) | 6/7 | 0/4 |
| Recusas que o runner reagenda para 21/10 (funil de Atender) | 6/6 | — |
| Depois do vencimento (21/10): enviou | 3/3 | — |

Outros cenários com a flag ligada (rodada principal, 15 pares):

| Medida (flag ligada) | Resultado |
|---|---|
| Índice escolhido válido | 15/15 |
| Valor real mantido, IA sem escrever em posição já preenchida | 15/15, 0 sobrescritas |
| Sem nenhum modelo sobrando: recusou (`no_fitting_template`, encerra como antes) | 3/3 |
| `negocio.prazo` preenchido | "20/10/2026" (dia certo, sem o erro de 1 dia a menos do #1535) |
| `negocio.valor` preenchido | "R$ 1.890,00" |
| Card sem o dado: modelo que precisa dele sai da lista | sempre |

Leitura:

- O efeito na IA se repete (em 14/10 também foi 1/7 contra 4/4): com o vencimento visível no modelo e o prazo
  ainda no futuro, ela não cobra. A mudança está no que vem depois. Antes, essa recusa marcava o card como gasto e
  a cadência acabava. Agora as 6 recusas caem em card de funil de Atender com prazo 20/10 e voltam em 21/10. Nessa
  data a IA enviou 3/3.
- Neste eval quem reagenda é o código do runner, não a IA, e a conta acima aplica a regra do #1591 às respostas
  registradas. O caminho do runner foi testado pelos specs: `auto_followup_runner_deadline_spec` (espera D+1, uma
  vez, prazo de hoje ainda espera, vencido encerra, funil de Vender e card sem prazo encerram, confiança baixa e
  encerramento não esperam) e pelos specs do runner, Híbrido e dados reais: 86 exemplos, 0 falhas, em
  `chat2you_test_1522`. A recusa por mérito não aciona o texto livre do Híbrido (`no_template_fits?`).
- Nesta rodada, depois do vencimento, a IA escolheu retomada e genérico, não o modelo de cobrança (em 14/10 foi 1/3).
  Os valores reais desse modelo saem corretos na lista oferecida (acima). O preenchimento já tinha sido conferido no
  envio em 14/10.
- Fora da bateria: `negocio.titulo` não está nos modelos sintéticos. Cobrança em funil de Vender continua
  encerrando na recusa (decisão do Rodrigo: só funil de Atender).

**Veredito:** pode ligar o bit 21 (`followup_template_real_values`) em 1/16/18. O preenchimento está correto e a
recusa antes do prazo deixou de encerrar a cadência no funil de Atender: espera o D+1 uma vez e, depois do vencimento,
a IA cobra.
