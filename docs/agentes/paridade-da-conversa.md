# Paridade da conversa (#3211)

Opções por agente que dão ao agente nativo o ritmo de conversa do fluxo externo. O módulo que lê as chaves é
`Autonomia::Agents::ParidadeDaConversa`.

**Padrão (decisão do Rodrigo, 25/11/2026, #3211: "liga para todo mundo"):** as quatro opções P1, P2, P3 e P5 valem para
**todo agente nativo**. Sem a chave, a opção está **ligada**. A exceção é a Lia (`agent_type` `insurance_quote`): nela, sem a
chave, a opção fica **desligada** (regra da casa: não mexer na Lia). Valor gravado manda em qualquer agente, inclusive na
Lia. Nada é gravado no banco: o padrão mora no código. A chave da instalação `AI_AGENT_CONVERSA_PADRAO_LIGADO=false`
desliga o padrão em todos de uma vez (ver Rollback).

| Item | Chave em `agent.config` | Padrão | Efeito ligado |
|---|---|---|---|
| P1 | `conversa_espera_a_fala` | ausente = ligada (Lia: desligada) | espera = fim previsto da fala anterior − agora, mínimo 1 s, teto 180 s; a pergunta junta toda a rajada do cliente. Com ela ligada, o `config['debounce_seconds']` do agente **deixa de valer** (Rodrigo aceitou o mínimo de 1 s, 25/11; o n8n usa max(min_debounce_sec, 1,5 s, fim previsto)). Mensagem automática do Chatwoot (template) não fecha a rajada; rajada vazia cai na última mensagem do cliente, como antes |
| P2 | `conversa_em_fila` | ausente = ligada (Lia: desligada) | o turno novo espera o turno em curso (IA ou pedaços), de 2 em 2 s, até a espera + 150 s; a resposta superada antes do 1º pedaço é descartada, com ou sem Fase 2 |
| P3 | `conversa_entrega_inteira` | ausente = ligada (Lia: desligada) | depois do 1º pedaço postado, mensagem nova não corta o resto. Só vale com `conversa_em_fila` (sem a fila, o turno novo falaria por cima) |
| P5 | `conversa_ritmo_do_canal` | ausente = ligada (Lia: desligada) | pausa pós-envio 1–3 s; no WhatsApp oficial, espera cheia no 1º pedaço e a cada 25 s acumulados, 1/5 nos demais; "digitando" no WAHA |
| P7 | `voice_reply` (já existe; ENV `AI_AGENT_VOICE_REPLY`) | o de sempre (padrão desligada) | regra para toda resposta em voz, menos na Lia: a resposta com link (`http://` ou `https://`) sai em texto, porque link lido em áudio não dá para tocar nem copiar |
| P6 | — (todos os agentes, menos a Lia) | ENV `AI_AGENT_DATA_DO_TURNO`, ausente = ligada | item `developer` `Agora: <dia da semana>, dd/mm/aaaa HH:MM (fuso da conta: <fuso>).` logo antes da pergunta, no fuso da conta; sem opção por agente, `AI_AGENT_DATA_DO_TURNO=false` desliga na instalação |

Sobre o P5: a cadeia de pedaços tem teto de 90 s de espera somada (`HUMANIZE[:max_total_delay_ms]`), calculado antes do
ritmo do canal. As pausas pós-envio do P5 (até 3 s por pedaço depois do 1º, até 5 pedaços) entram depois desse teto e
podem somar até **+12 s** a ele.

## Como desligar num agente

Não há tela. Grave a chave no `config` do agente (jsonb) com valor `false`. Em produção isso é escrita no banco: quem faz
é a Orquestração, por `psql`, com o OK do Rodrigo (nunca `rails runner`). Para um agente (troque o id e a chave):

```sql
UPDATE autonomia_agents
   SET config = jsonb_set(config, '{conversa_em_fila}', 'false'::jsonb, true), updated_at = NOW()
 WHERE id = <id do agente>;
```

Vale no próximo turno, sem deploy. Tirar a chave **não** desliga: volta ao padrão (ligada; na Lia, desligada).
`conversa_entrega_inteira` só vale com `conversa_em_fila`: desligar a fila desliga as duas.

Para todos os agentes de uma vez, use a chave da instalação (abaixo), não um `UPDATE` em massa.

## Na Lia

Sem a chave, as quatro ficam desligadas. Valor gravado vale nela também (`true` liga); ninguém grava hoje, e não há trava.

## E-mail fica de fora (#3218)

Na caixa de e-mail as quatro opções não valem, nem com a chave gravada: cada e-mail é uma carta completa, com o próprio histórico citado, então não há rajada de bolhas para juntar, fala para esperar nem "digitando". A regra mora em `Autonomia::Agents::ParidadeDaConversa` (todo predicado recebe a caixa), e a pergunta e o turno do e-mail são os de antes do #3211.

## Deploy

O padrão ligado depende do #3213 já em produção: é ele que solta a marca da fala (`autonomia:fala_em_curso`) em todo
`ReplyJob` e `ChunkedDeliveryJob`, mesmo com a opção desligada. A `main` de antes do #3213 não lê nem grava
`autonomia:fala_em_curso` nem `autonomia:fim_da_fala`; um worker dela no blue/green entregaria pedaços sem soltar a marca,
e o turno seguinte da conversa esperaria na fila até o prazo (a espera + 150 s).

## Rollback (chave da instalação)

ENV `AI_AGENT_CONVERSA_PADRAO_LIGADO`: ausente ou `true`, a chave ausente no agente vale **ligada** (o padrão acima). Com
`false`, a chave ausente vale **desligada** em todo agente: volta o comportamento do #3213. Para voltar atrás, grave
`AI_AGENT_CONVERSA_PADRAO_LIGADO=false` na variável do serviço e reinicie os processos (web e workers). Não há escrita no
banco nem deploy de código. Valor gravado num agente continua mandando; a Lia não muda.

Valor vazio (`AI_AGENT_CONVERSA_PADRAO_LIGADO=`) também desliga o padrão, como `false` e `0`.
