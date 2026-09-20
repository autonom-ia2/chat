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

Um cenário só: `python3 tools/cotacao-smoke/smoke.py --so pj-condutor`.
Lista: `python3 tools/cotacao-smoke/smoke.py --listar`.

Sai com código 1 se algum cenário reprovar, então serve de portão em script de deploy.

## O que ela prova, e como

O veredito sai **do dado que o produto gravou**, nunca de ler o texto da Lia:

| pergunta | onde a resposta é lida |
|---|---|
| a cotação foi acionada? | `autonomia_agent_tool_runs`, execução nova na caixa |
| terminou bem? | `status = done`, `failure_code` vazio |
| chegou ao cliente? | `delivered_count`, e anexo em `attachments` |
| escalou para humano? | `autonomia_agent_events`, `event_type = 1` (`handed_off`) |
| o cliente foi respondido? | `messages` da caixa, depois da marca |

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
no portal da corretora. Hoje são dois por rodada. É o preço de saber, em três minutos, que
o deploy não quebrou o produto — contra descobrir pelo corretor, como aconteceu.

## Limitações, ditas na cara

- **Não isola contexto.** Todos os cenários caem na mesma conversa do WhatsApp, porque
  resolver conversa pela API do Chatwoot exige um token que hoje responde 401 — e, pior,
  `toggle_status` com token de usuário zera o `ai_assignee` e faria a IA sumir da conversa
  (é a causa já registrada em produção). Enquanto não houver um token próprio de teste, a
  suíte roda em conversa contínua. Isso é mais perto do cliente real, que não abre conversa
  nova a cada carro, mas significa que um cenário pode influenciar o próximo. Ao investigar
  uma falha, rode o cenário sozinho com `--so`.
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

1. Rode ele sozinho (`--so <id>`), para descartar contaminação da conversa.
2. Olhe a execução pelo id que a suíte imprime, em `autonomia_agent_tool_runs`.
3. Se `failure_code` disser `faltam_dados`, leia **de quem** é o campo cobrado antes de
   concluir que o cliente esqueceu algo. Foi essa leitura que faltou em 20/09.
