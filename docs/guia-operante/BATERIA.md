# Bateria de cenários reais do Guia (#900)

## O que é

Vinte e seis pedidos (C01a, C01b, C02 a C24 e C30) que um administrador de corretora faz de verdade,
mandados ao Guia de verdade — mesmo modelo, mesma instrução, mesmas ferramentas, escrevendo pela API da
plataforma no banco de teste. Cada cenário confere o **estado final do banco** (o que foi criado, mudado ou deixado como estava), não o
texto da resposta. O Guia age sem confirmação (#855), então o que importa é o que ficou gravado.

Do texto, a bateria só confere o que é objetivo: respondeu, a resposta não foi retida pelo portão de
confiança e o Guia não ofereceu suporte (`escalate`). O resto da resposta aparece no placar, para uma
pessoa ler. A exceção são o C01a e o C01b (o pedido da conta 18): neles um juiz — outro modelo, que lê
o sentido da resposta — confere se o Guia explicou que a caixa vem da participação nela, disse que não
existe conversa só leitura, propôs o mais próximo, perguntou antes e não ofereceu suporte. Desde a
#907/#879 ele também confere a **proposta concreta**: a pergunta cita pelo nome a pessoa (Carla) e a
caixa (Marketing) e não oferece o `inbox_view` como alternativa. O C21 e o C22 também passam pelo juiz
(no C22: explicou por que a newsletter virou card e avisou que o rodízio só pega quem está online). O
juiz custa centavos por cenário.

- Spec: `spec/services/autonomia/guide/bateria_admin_eval_spec.rb` (tags `:eval_pago` e `:bateria_guia`).
- Conta de partida e placar: `spec/support/bateria_do_guia.rb`. A conta tem três caixas (WhatsApp
  Vendas, Sinistros com saudação ligada, Marketing), Ana e Bruno atendendo, Carla no time de marketing,
  o funil Auto com três etapas, o card do Pedro com o Bruno e duas conversas sem responsável. A Carla
  é membro da caixa Marketing, menos no C01a e C01b, que a tiram antes do pedido para ficar como na conta 18.
- C22 a C24 (#860, a conta 16) somam à corretora a caixa de e-mail **Comercial** (`conta_formularios!`):
  card automático ligado no funil Comercial (etapa Novo), rodízio desligado, Ana e Bruno como agentes,
  quatro e-mails do formulário do site (três com a linha de aceite) e dois e-mails comuns (a newsletter
  da Anthropic e um fornecedor). Como em produção, o contato do formulário nasce com o e-mail no lugar
  do nome, sem telefone e numa empresa batizada pelo domínio, e todo e-mail vira card em Novo sem
  responsável. C22 arruma a caixa (desliga o card automático, liga o rodízio e explica), C23 corrige
  nome, telefone e empresa e confere que o desfazer volta tudo, C24 guarda o consentimento só de quem
  marcou, com a prova numa nota. O C25 (o formulário vira lead certo sozinho, com o Decisor da #858) ainda não
  foi escrito: o Decisor já está no lote 10, mas o cenário fica para depois. Não há C26 a C29.
- C30 (#858) põe seis contatos com conversa — três do formulário do site, três de outros canais — e pede
  para etiquetar com `lead-site` só os do site. Pega o Guia que não classifica com o Jev
  (`classificar_com_jev`) e responde de cabeça. Usa o Jev de verdade: precisa de `TYPESAFE_API_KEY`.
- Cada cenário diz no comentário qual falha ele pega.

## Quando rodar

Antes de todo lote que mexe no Guia: instrução (`lib/operator_guide/guia-instrucao.md`), ferramentas
(`app/services/autonomia/agents/tools/native/guia_*.rb`), `Autonomia::Guide::Acoes`, troca de modelo ou
de esforço de raciocínio. Também depois de mudar uma tela ou endpoint que um cenário usa.

Sem as variáveis abaixo os exemplos ficam pendentes: no CI e no `rspec` do dia a dia a bateria não
roda e não custa nada.

## Comando

Dentro do worktree, com o rbenv carregado:

```sh
SSL_CERT_FILE=/etc/ssl/cert.pem AUTONOMIA_EVAL_PAGO=1 OPENAI_API_KEY=<chave> \
  RAILS_ENV=test bundle exec rspec spec/services/autonomia/guide/bateria_admin_eval_spec.rb
```

- `AUTONOMIA_EVAL_PAGO=1` liga a bateria. Sem ele, tudo fica pendente.
- `OPENAI_API_KEY`: a chave da OpenAI. Nunca cole o valor em chat, commit ou log.
- `SSL_CERT_FILE`: sem ele, no Mac, a base do Guia fica vazia e as respostas saem retidas.
- `GUIA_ORCAMENTO_USD` (opcional, padrão 9): teto em dólar da bateria inteira.
- `TYPESAFE_API_KEY` (só para o C30, #858): a chave do Jev, que o `classificar_com_jev` usa. Sem ela o
  C30 fica pendente. O custo do Jev é nosso e aparece no placar junto com o resto.

Para rodar só alguns cenários: `-e C07` (um) ou `-e C07 -e C19` (vários).

## Custo

Estimativa de **US$ 4,7 a 8,1** a bateria inteira (cerca de 32 turnos): US$ 3 a 5 do C01a ao C21 (conta em
`tmp/900/bateria.md`), US$ 1,5 a 2,5 do C22 ao C24, que corrigem vários contatos num turno só, e US$ 0,15 a
0,60 do C30 — um turno do Guia; o Jev que ele chama para classificar as seis conversas sai a menos de
US$ 0,01 (US$ 0,042 por milhão de tokens de entrada, saída grátis; ver
`docs/audit/2026-09-30-typesafe-764-acceptance.md`). Sem `TYPESAFE_API_KEY` o C30 fica pendente e não custa.
O custo de cada ida ao modelo é lido de `Crm::AiUsageEvent` antes de a transação do exemplo ser
desfeita. Quando a soma passa de `GUIA_ORCAMENTO_USD`, os cenários seguintes são pulados e aparecem
como `pulado` no placar. O teto vale entre cenários: um cenário já começado termina, então o gasto
final pode passar do teto pelo custo de um cenário (pior caso perto de US$ 0,60 por turno).

Os embeddings da base do Guia, refeitos em cada cenário, custam menos de US$ 0,002 e não entram na conta.

## Como ler o resultado

O RSpec mostra as falhas como sempre. No fim, imprime o placar:

```
id   situação        US$  idas  passos
C01a passou       0.1520     5     1/1
C03  FALHOU       0.2100     7     1/2
...
total US$ 5.8400 de 9.00
```

- **situação**: `passou`, `FALHOU` ou `pulado` (orçamento).
- **US$**: custo do cenário.
- **idas**: chamadas do Guia ao modelo (`agente_resposta`). Perto de 10 num turno é o Guia andando em
  círculo.
- **passos**: escritas que deram certo / escritas tentadas. `1/2` num cenário que passou quer dizer
  que o Guia errou uma vez e se corrigiu — é o que o C03 e o C11 querem ver. `0/0` num cenário de
  pergunta, ambíguo ou impossível é o certo.

Embaixo vem o trecho do que o Guia respondeu em cada cenário. Leia nos que têm critério de texto:
C03 (avisou do ajuste no nome), C15 (disse que não
existe e o que é possível), C16 e C17 (perguntou qual), C18 (apontou o valor inválido).

## Automações compostas (#917)

C26 a C29 testam a máquina de automações inteira, com gatilhos diferentes:

- **C26** — o pedido de risco de cancelamento do Rodrigo, literal (`BateriaDoGuia::PEDIDO_C26`). Dois
  turnos: o pedido e, depois, a URL do webhook e a responsável (Ana). Toda proposta é confirmada pelo
  mesmo caminho do botão (`Acoes#executar`), uma por turno. O banco tem de ter: o time Retenção criado,
  a regra de tratamento (etiqueta, time, mensagem, e-mail ao time, webhook) protegida por "não tem a
  etiqueta X" + "adicionar X" e — sem o Jev — disparada pela etiqueta do caso (ou desligada), as regras
  de 15 e 30 minutos com atraso que reconferem aberta e sem atendente, e a transcrição ao resolver.
  Nenhuma condição de palavras em `content`; nenhuma regra de mensagem sem `message_type` incoming. O
  juiz confere que o Guia disse que a detecção por intenção chega com o Jev e como o alerta chega à pessoa.
- **C27** — conversa nova "fora do horário": a automação não tem condição de horário. Nada de regra que
  mande mensagem a toda conversa nova; o juiz confere que o Guia disse isso e apontou o horário da caixa.
- **C28** — card entra em Proposta: automação de ETAPA do funil (retorno em 1 dia + Bruno como
  responsável), não regra de conversa.
- **C29** — resolvidas do WhatsApp Vendas: transcrição por e-mail, só daquela caixa, com confirmação.

Um cenário que falha diz o que ficou gravado de errado. O Guia é um modelo: rode o cenário de novo
com `-e` antes de concluir que é regressão. Falhar duas vezes seguidas é regressão.
