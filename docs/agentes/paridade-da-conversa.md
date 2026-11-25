# Paridade da conversa (#3211)

Opções por agente que dão ao agente nativo o ritmo de conversa do fluxo externo. Todas nascem **desligadas**: sem a
chave, o comportamento é o de hoje. O módulo que lê as chaves é `Autonomia::Agents::ParidadeDaConversa`.

| Item | Chave em `agent.config` | Padrão | Efeito ligado |
|---|---|---|---|
| P1 | `conversa_espera_a_fala` | ausente = desligada | espera = fim previsto da fala anterior − agora, mínimo 1 s, teto 180 s; a pergunta junta toda a rajada do cliente |
| P2 | `conversa_em_fila` | ausente = desligada | o turno novo espera o turno em curso (IA ou pedaços), de 2 em 2 s, até a espera + 150 s; a resposta superada antes do 1º pedaço é descartada, com ou sem Fase 2 |
| P3 | `conversa_entrega_inteira` | ausente = desligada | depois do 1º pedaço postado, mensagem nova não corta o resto. Só vale com `conversa_em_fila` (sem a fila, o turno novo falaria por cima) |
| P5 | `conversa_ritmo_do_canal` | ausente = desligada | pausa pós-envio 1–3 s; no WhatsApp oficial, espera cheia no 1º pedaço e a cada 25 s acumulados, 1/5 nos demais; "digitando" no WAHA |
| P7 | `voice_reply` (já existe; ENV `AI_AGENT_VOICE_REPLY`) | o de sempre (padrão desligada) | regra para toda resposta em voz, menos na Lia: a resposta com link (`http://` ou `https://`) sai em texto, porque link lido em áudio não dá para tocar nem copiar |
| P6 | — (todos os agentes, menos a Lia) | ENV `AI_AGENT_DATA_DO_TURNO`, ausente = ligada | item `developer` `Agora: <dia da semana>, dd/mm/aaaa HH:MM (fuso da conta: <fuso>).` logo antes da pergunta, no fuso da conta; sem opção por agente, `AI_AGENT_DATA_DO_TURNO=false` desliga na instalação |

Sobre o P5: a cadeia de pedaços tem teto de 90 s de espera somada (`HUMANIZE[:max_total_delay_ms]`), calculado antes do
ritmo do canal. As pausas pós-envio do P5 (até 3 s por pedaço depois do 1º, até 5 pedaços) entram depois desse teto e
podem somar até **+12 s** a ele.

## Como ligar num agente

Não há tela. Grave a chave no `config` do agente (jsonb) com valor `true`, por exemplo
`agent.update!(config: agent.config.merge('conversa_em_fila' => true))`. O `Contratar` passa a ligar as chaves num PR
seguinte.

## Como desligar

Tire a chave do `config` do agente (ou grave `false`). A mudança vale no próximo turno, sem deploy.
