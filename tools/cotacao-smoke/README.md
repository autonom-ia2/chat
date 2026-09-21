# Suíte de conversas do agente de cotação

Conversa com a Lia pelo WhatsApp de teste, como um corretor conversaria, e confere o
resultado no banco de produção. Roda **depois de cada deploy** que toca o agente de
cotação (chat2you) ou o adapter do AGGER.

Ela existe por um motivo específico. Em 20/09/2026 uma guarda do adapter passou a pedir
nascimento e sexo de um CNPJ, e **toda cotação de empresa virou escalada para humano**. A
suíte unitária dos dois repositórios estava verde, o CI estava verde, e o defeito só
apareceu quando o Rodrigo mandou uma mensagem de cliente e olhou a resposta. O que faltava
era exatamente isto: uma conversa real, repetível, rodada a cada deploy.

## Como rodar

```bash
set -a; source ~/dev/claudete-ops/.secrets/credentials.env; set +a
export SMOKE_PLACAS="FCP1A83,QUU0I17,QNX9533"
python3 tools/cotacao-smoke/smoke.py
```

Um cenário só: `python3 tools/cotacao-smoke/smoke.py --so pj-condutor`. Ele roda com a
**mesma placa e a mesma pessoa** que teria na rodada cheia — o índice é o do arquivo, não o da
lista filtrada —, que é o que faz de `--so` uma reprodução e não outro teste.

Lista: `python3 tools/cotacao-smoke/smoke.py --listar`.

O contato de teste é o número da sessão WAHA (`SMOKE_SESSAO`), e é por ele que cada cenário
descobre em que conversa caiu. Se o Chatwoot gravar esse contato com outro telefone, passe
`SMOKE_TELEFONE=+55...`.

Sai com código 1 se algum cenário reprovar, então serve de portão em script de deploy.

## O que ela prova, e como

O veredito sai **do dado que o produto gravou**, nunca de ler o texto da Lia:

| pergunta | onde a resposta é lida |
|---|---|
| em que conversa o cenário caiu? | `messages` do contato de teste, depois da marca |
| a cotação foi acionada? | `autonomia_agent_tool_runs`, execução nova **naquela conversa** |
| terminou bem? | `status = done`, `failure_code` vazio |
| chegou ao cliente? | a mensagem que o motor publicou **por esta execução** — `content_attributes` carrega `autonomia_async_token`, que começa com a `execution_key` — e o anexo nela |
| escalou para humano? | `autonomia_agent_events` daquela conversa, `event_type in (1,2,3)` — os três de `AgentEvent::HANDOFF_TYPES` |
| o cliente foi respondido? | `messages` daquela conversa, depois da marca |

Tudo é medido **por conversa**, nunca por caixa. A caixa da Lia atende vários corretores: em
sete dias teve 12 conversas de 3 contatos e 22 execuções de cotação espalhadas por 9 delas.
Medindo por caixa, o anexo do vizinho satisfaz o cenário e a execução do vizinho vira "a cotação
abriu" — falso verde com a cara de aprovação.

`delivered_count` **não** é a prova de entrega, e o próprio produto explica por quê
(`app/services/autonomia/agents/tools/native/base.rb`): ele conta qualquer item aceito para
publicação, inclusive a pergunta pelo dado que falta. Em produção há execução `done` com
`delivered_count = 1` cuja única entrega foi "Para concluir sua cotação, me informe…", sem
anexo nenhum. Ele continua impresso como evidência; quem decide é a mensagem na conversa.

Interpretar a fala com lista de palavra está proibido nesta casa, e aqui não seria só
proibido: seria frágil. O texto muda a cada ajuste de manual; o dado gravado, não.

## Os cenários

Cada um traz no JSON o campo `motivo`, dizendo **qual falha ele pega**. Cenário sem falha
associada não entra.

| id | o que faz | pega |
|---|---|---|
| `pf-placa` | pessoa física com CPF e placa | o caminho mais usado parar de funcionar |
| `pj-condutor` | empresa com motorista funcionário | o defeito de 20/09: campo de pessoa cobrado do CNPJ |
| `pj-sem-nascimento` | empresa sem o nascimento do motorista | recusa virando escalada em vez de pergunta |
| `fora-de-escopo` | pergunta de outro ramo | cotação aberta à toa, que custa consulta paga |
| `preco-sem-dados` | pede preço antes de dar os dados | promessa de valor sem cotação feita |

## Custo, e por que ele é aceitável

Cada cenário de cotação gasta **uma consulta paga** ao BigDataCorp e **uma cotação real**
no portal da corretora. Hoje são dois por rodada.

**Ela não é rápida, e não adianta fingir que é.** Somando os tetos deste arquivo — 120 s para a
mensagem virar conversa, 180 s para a execução nascer, 420 s para ela terminar e 300 s para a
entrega chegar, mais 120 s de silêncio em cada cenário sem cotação — o pior caso passa de **45
minutos**; o caminho feliz fica em torno de **15**. Cada passo de espera é ainda uma consulta à
produção por SSM, que custa segundos por vez. É o preço de saber que o deploy não quebrou o
produto, contra descobrir pelo corretor, como aconteceu. Se for portão de deploy, ela é um
portão lento — trate-a como tal.

## Limitações, ditas na cara

- **Não isola contexto.** A suíte não abre conversa: ela manda a mensagem e descobre onde caiu.
  Quem decide isso é o Chatwoot, que **reaproveita a conversa aberta e abre uma nova quando a
  anterior foi resolvida** — o contato de teste já acumulou 10 conversas nesta caixa. Então os
  cenários de uma rodada normalmente caem todos na mesma conversa, e um pode influenciar o
  seguinte; mas a suíte nunca supõe qual é: ela lê a conversa de cada cenário e mede só ali.
  Resolver a conversa entre cenários, que isolaria de verdade, exige um token que hoje responde
  401 — e, pior, `toggle_status` com token de usuário zera o `ai_assignee` e faria a IA sumir da
  conversa (causa já registrada em produção). Ao investigar uma falha, rode o cenário sozinho
  com `--so`.
- **Prova a entrega, não o conteúdo dela.** "Chegou ao cliente" quer dizer que a mensagem
  publicada por aquela execução está na conversa, e com anexo nos cenários que exigem o
  comparativo. Que o PDF traga os preços certos, quem garante é a conferência de preços do
  produto.
- **Escalada fora do horário aparece, e reprova.** Rodar fora da janela do agente passa a
  conversa a humano por `skipped_schedule`, que agora a suíte enxerga. Isso é intencional: uma
  rodada fora do horário não mede o deploy, e ela precisa dizer isso em vez de aprovar.
- **A escalada é lida na conversa do cenário.** Até o #554, o handoff do CRM podia ser gravado
  na conversa *primária* do contato, e não naquela em que ele acabou de escrever; num deploy sem
  o #554 uma escalada assim passaria despercebida aqui. Com o #554 em produção, o evento cai na
  conversa viva, que é a que a suíte mede.
- **Documentos novos a cada rodada, por obrigação.** `ToolRun#pedido_ainda_vale?` trata
  pedido igual ao das últimas 24 horas como já atendido e responde do histórico. A suíte
  gera CPF e CNPJ sintéticos a cada execução; repetir documento mediria o histórico.
- **Placa tem de ser real.** O portal consulta a placa. Por isso `SMOKE_PLACAS` é
  obrigatória e não tem valor padrão: placa inventada reprovaria o cenário por um motivo
  que não é do produto.
- **Não mede preço certo.** Ela confere que a cotação saiu e chegou; se o valor está
  correto, quem garante é a conferência de preços do próprio produto.
- **Fala com produção.** Não existe ambiente de homologação do portal da corretora. Toda
  rodada aparece na caixa da Lia e no histórico do AGGER.

## Quando um cenário reprova

1. Rode ele sozinho (`--so <id>`), para descartar contaminação da conversa. A placa e a pessoa
   são as mesmas da rodada cheia.
2. Olhe a execução e a conversa pelos ids que a suíte imprime, em `autonomia_agent_tool_runs` e
   em `conversations`. Toda a medição do cenário cabe naquela conversa.
3. Se `failure_code` disser `faltam_dados`, leia **de quem** é o campo cobrado antes de
   concluir que o cliente esqueceu algo. Foi essa leitura que faltou em 20/09.
