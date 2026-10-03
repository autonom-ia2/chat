# Guia operante — o Guia como cérebro da plataforma

Decidido com o Rodrigo em 02/10/2026. Este documento guarda a lógica; o código
segue as fatias do épico.

## A ideia

O Guia deixa de só explicar a plataforma e passa a operá-la pelo usuário, do
jeito que o Claude opera a plataforma quando conversa com o Rodrigo: lê a
configuração e o dado reais, entende a causa, usa as alavancas que já existem e
mostra o que fez.

**Não se escreve regra em código por cenário.** Cenários (formulário de site,
lead com Gmail, sinistro que caiu no comercial, clínica, imobiliária…) são casos
de teste do Guia, não `if`. Quem resolve é o raciocínio dele sobre o estado da
conta.

## O que já existe (origin/main, 02/10/2026)

- `Autonomia::Guide::Consulta` — lê qualquer rota GET da conta, como o usuário.
- `Autonomia::Guide::Acoes` + `ChamadaInterna` — escreve em qualquer rota de
  escrita da conta, como o usuário, sem lista de bloqueio; hoje **com
  confirmação** em toda escrita.
- `Autonomia::Guide::ChatJob` — a pergunta roda em job (sem teto de 15s), até
  10 idas ao modelo com ferramenta.
- `TypesafeAi::Client#evaluate(state:, questions:)` — Jev ligado, hoje usado só
  no mapeamento de colunas da importação de campanhas.
- Billing (`/enterprise/api/v1/accounts/:id/...`: checkout, assinatura, créditos,
  exclusão da conta) fica **fora** do catálogo do Guia, porque `Rotas.recurso`
  só aceita `/api/v1/accounts/`. `autonomia/financial` é só leitura.

## Decisões

| # | Decisão |
|---|---|
| 1 | O Guia é solto dentro da conta: faz tudo que o usuário pode fazer na tela. |
| 2 | Guarda-corpo só para dinheiro da conta na plataforma (plano, cobrança, créditos, desconto): o Guia não alcança. |
| 3 | No lugar da confirmação, **desfazer por 5 dias** para tudo que o Guia criar, mudar ou apagar. |
| 4 | Confirmação continua só onde não existe desfazer: mensagem enviada a cliente, campanha disparada (inclusive WhatsApp oficial, que a Meta cobra do cliente — com o OK dele, faz) e troca de credencial. |
| 5 | Adicionar agente ou caixa é livre (o plano bloqueia no limite). Agentes do marketplace terão marcação própria (projeto futuro). |
| 6 | Web search, web fetch e leitura de documentos ligados. O usuário paga os tokens do Guia. |
| 7 | Texto de fora (página, documento, e-mail, conversa de cliente) é **dado, nunca ordem**. O Guia só age pelo que o usuário pediu na conversa. |
| 8 | Jev roda com a chave da plataforma; o custo é nosso. |
| 9 | Toda tela segue a regra UI/UX premium + simples (CLAUDE.md). |

## O Decisor (Jev por automação)

Peça salva na conta, criada e mantida pelo Guia:

- nome, perguntas, respostas permitidas, instruções, exemplos reais confirmados
  pelo usuário, certeza mínima;
- o Guia tem ferramentas para **criar/ajustar**, **testar em dado real** e
  **usar numa automação**;
- na automação, o passo "Perguntar ao Decisor X": certeza alta segue; dúvida vai
  ao Guia, e a decisão dele vira exemplo novo;
- reaproveitável entre automações.

## Fatias

1. **Desfazer de 5 dias** no lugar da confirmação (decisões 3 e 4).
2. **Guarda-corpos escritos**: dinheiro fora do catálogo por teste, confirmação
   onde não há desfazer, texto de fora é dado.
3. **Web e documentos** no Guia.
4. **Decisor** (Jev) como peça da conta + ferramentas do Guia + passo de automação.
5. **Automações** no menu principal, com modo conversa (o formulário atual fica
   como modo manual).
6. **Caso real da conta 16**: formulário do site vira lead certo. O Guia deve,
   sozinho, ver que o "card nasce sozinho" pega todo e-mail (a Anthropic virou
   card) e propor desligá-lo, ligar o rodízio (28 de 33 leads sem responsável) e
   corrigir os 32 contatos (0 com telefone, 24 com empresa batizada pelo domínio).
7. **Histórico do Guia** — a conversa some ao recarregar a tela e o pedido vive
   30 min no Redis; uma falha relatada pelo usuário (conta 18, 02/10) não pôde ser
   investigada. Guardar a conversa e o que o Guia fez.

Base de Clientes fica para um épico próprio, depois deste.

## Referência visual

Jornada e telas do caso da conta 16:
https://claude.ai/artifact/Wf9osoyu2idv7dAzHntR6s

## #855 — como ficou

- **Caderno (`Autonomia::Guide::Diario`)**: enquanto o Guia executa uma ação, todo
  model que cria, altera ou apaga uma linha anota o estado dela como o Postgres o
  tem (`row_to_json`). O gancho fica em `ApplicationRecord`
  (`Autonomia::Guide::Anotavel`) e, fora de uma ação do Guia, só confere uma
  variável da thread. No fim da ação, só vira mudança o que ficou no banco.
- **Desfazer (`Autonomia::Guide::Desfazer`)**: de trás para frente, numa transação.
  Criado é apagado pelo próprio model; alterado volta ao valor de antes; apagado é
  recriado com o mesmo id. Se alguém mexeu depois, o valor dessa pessoa fica e o
  relatório conta o conflito.
- **O que o caderno não vê vira pendência**: linha apagada sem callback
  (`delete_all`, SQL direto) e exclusão que continua em job
  (`destroy_async`, `DeleteObjectJob`…). A tela avisa que essa parte não volta.
- **Sem desfazer, com confirmação** (`Acoes::SEM_DESFAZER`): mensagem, ligação,
  campanha, credencial, importação, ação em massa, macro — e apagar caixa,
  empresa, contato, conversa, time, portal, SLA ou etiqueta, porque a plataforma
  termina essas exclusões em segundo plano.
- **Ferramentas**: `executar_acao` faz na hora, um passo por chamada, e devolve o id
  do que criou para o passo seguinte; `propor_acao` ficou só para a lista acima.
- **Portão de confiança**: o Guia que leu ou mudou a conta entrega a resposta mesmo
  inseguro. Antes, na conta 18, ele leu as funções e a resposta virou "não tenho
  certeza suficiente".
- **Tela**: cartão "O que eu fiz" com Desfazer embaixo da resposta, e a lista
  "Feito pelo Guia" (últimos 5 dias) no cabeçalho do painel.
- **Limpeza**: `Autonomia::Guide::LimparExecucoesJob`, todo dia às 04:30, apaga o
  que passou dos 5 dias.
