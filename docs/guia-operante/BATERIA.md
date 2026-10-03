# Bateria de cenários reais do Guia (#900)

## O que é

Vinte pedidos que um administrador de corretora faz de verdade, mandados ao Guia de verdade — mesmo
modelo, mesma instrução, mesmas ferramentas, escrevendo pela API da plataforma no banco de teste. Cada
cenário confere o **estado final do banco** (o que foi criado, mudado ou deixado como estava), não o
texto da resposta. O Guia age sem confirmação (#855), então o que importa é o que ficou gravado.

Do texto, a bateria só confere o que é objetivo: respondeu, a resposta não foi retida pelo portão de
confiança e o Guia não ofereceu suporte (`escalate`). O resto da resposta aparece no placar, para uma
pessoa ler — por exemplo, se no C01 o Guia explicou que o acesso à caixa vem da participação nela.

- Spec: `spec/services/autonomia/guide/bateria_admin_eval_spec.rb` (tags `:eval_pago` e `:bateria_guia`).
- Conta de partida e placar: `spec/support/bateria_do_guia.rb`. A conta tem três caixas (WhatsApp
  Vendas, Sinistros com saudação ligada, Marketing), Ana e Bruno atendendo, Carla no time de marketing,
  o funil Auto com três etapas, o card do Pedro com o Bruno e duas conversas sem responsável.
- Cada cenário diz no comentário qual falha ele pega.

## Quando rodar

Antes de todo lote que mexe no Guia: instrução (`lib/operator_guide/guia-instrucao.md`), ferramentas
(`app/services/autonomia/agents/tools/native/guia_*.rb`), `Autonomia::Guide::Acoes`, troca de modelo ou
de esforço de raciocínio. Também depois de mudar uma tela ou endpoint que um cenário usa.

Sem as variáveis abaixo os 20 exemplos ficam pendentes: no CI e no `rspec` do dia a dia a bateria não
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
- `GUIA_ORCAMENTO_USD` (opcional, padrão 6): teto em dólar da bateria inteira.

Para rodar só alguns cenários: `-e C07` (um) ou `-e C07 -e C19` (vários).

## Custo

Estimativa de **US$ 3 a 5** a bateria inteira (cerca de 28 turnos; conta em `tmp/900/bateria.md`).
O custo de cada ida ao modelo é lido de `Crm::AiUsageEvent` antes de a transação do exemplo ser
desfeita. Quando a soma passa de `GUIA_ORCAMENTO_USD`, os cenários seguintes são pulados e aparecem
como `pulado` no placar. O teto vale entre cenários: um cenário já começado termina, então o gasto
final pode passar do teto pelo custo de um cenário (pior caso perto de US$ 0,60 por turno).

Os embeddings da base do Guia, refeitos em cada cenário, custam menos de US$ 0,002 e não entram na conta.

## Como ler o resultado

O RSpec mostra as falhas como sempre. No fim, imprime o placar:

```
id   situação        US$  idas  passos
C01  passou       0.1520     5     1/1
C03  FALHOU       0.2100     7     1/2
...
total US$ 3.8400 de 6.00
```

- **situação**: `passou`, `FALHOU` ou `pulado` (orçamento).
- **US$**: custo do cenário.
- **idas**: chamadas do Guia ao modelo (`agente_resposta`). Perto de 10 num turno é o Guia andando em
  círculo.
- **passos**: escritas que deram certo / escritas tentadas. `1/2` num cenário que passou quer dizer
  que o Guia errou uma vez e se corrigiu — é o que o C03 e o C11 querem ver. `0/0` num cenário de
  pergunta, ambíguo ou impossível é o certo.

Embaixo vem o trecho do que o Guia respondeu em cada cenário. Leia nos que têm critério de texto:
C01 (explicou que a caixa vem da participação), C03 (avisou do ajuste no nome), C15 (disse que não
existe e o que é possível), C16 e C17 (perguntou qual), C18 (apontou o valor inválido).

Um cenário que falha diz o que ficou gravado de errado. O Guia é um modelo: rode o cenário de novo
com `-e` antes de concluir que é regressão. Falhar duas vezes seguidas é regressão.
