# #3006 — consulta pronta que falhou não é dado do turno

- Issue: https://github.com/autonom-ia2/chat/issues/3006
- PR aberto: https://github.com/autonom-ia2/chat/pull/3008
- Branch: `fix/3006-consulta-que-falhou-nao-e-dado`.
- Segunda rodada, depois da revisão independente do commit `5e1d52f380`: desenho sem estado, no commit seguinte da mesma branch.
- Specs escritos e ajustados, sem execução nesta máquina. Rodaram na CI do PR: verde no commit `e70d07117d` (28 passaram, 2 puladas).

## Decisão

A ferramenta ligada (`Tools::Bound`) não guarda situação nem contexto da leitura entre chamadas. O módulo
`Tools::LeituraDaPronta` expõe `situacao_da_pronta(output)`: recebe a própria saída devolvida por `execute` e lê
`situacao` somente quando a ferramenta é pronta e a saída é um objeto JSON. Nos demais casos, devolve `nil`.
Não interpreta frases nem aplica expressão regular. A leitura ocorre depois do corte de tamanho do Bound.

O Answerer usa esse valor local à chamada, mantendo o contexto em `@delivery` e `@operador`. O Guia (com operador)
fica fora da classificação. Só uma ferramenta direta do principal, identificada por `ferramenta_do_sistema?`,
passa por essa leitura; o despacho ao especialista ou ajudante mantém a regra anterior.

| Situação da resposta | Dado | Recusa do turno |
| --- | --- | --- |
| `encontrado` | sim | não |
| `nao_encontrado` | sim | não |
| `documento_invalido` | sim | não |
| `pedido_invalido` | não | não; uma tentativa corrigida pode contar |
| `nao_consegui_consultar` | não | sim; permanece até o fim do turno |

`Answerer#ler_saida_pronta` registra somente `nao_consegui_consultar`, depois do despacho e antes da comparação
do contador. Usa `Recusa.registrar` com o agente e a conversa do `@delivery`, sem `Recusa.para_modelo` ou
`Recusa.saida`: o texto devolvido pela ferramenta ao modelo não muda. O gatilho da varredura passa a ser
`answerer.rb#ler_saida_pronta#1`, disparado pelo caminho real do Answerer no spec de registro.

A consulta interna do especialista e do ajudante não registra a nova recusa. HTTP cadastrada e nativa não têm a
`situacao` interpretada. Nenhum arquivo de cotação foi alterado. O desenho respeita o contexto por chamada descrito
em `app/services/autonomia/agents/tools/delivery.rb:8` e `app/services/autonomia/guide/contexto.rb:8`; o primeiro
arquivo fica em `agents/tools`, não em `agents/delivery.rb`.

## Onde a resposta pode ser barrada

No atendimento ao cliente, `Operate::Responder` passa `trust_instruction: true`
(`app/services/autonomia/agents/operate/responder.rb:515`). O Answerer retorna antes do portão
(`app/services/autonomia/agents/answerer.rb:156`). Portanto, este conserto não barra a resposta ao cliente: nesse
caminho, o efeito é a linha de recusa no log e sua contagem no turno.

O Testar de agente que não é a Lia também usa `trust_instruction: true`
(`Playground.como_no_atendimento?` e `Playground#run`). O portão que este conserto religa para as prontas é o do
Copiloto, que chama sem `trust_instruction`. Os exemplos do Answerer que verificam bloqueio usam esse modo
explicitamente pelo padrão `false` do construtor; não demonstram bloqueio no atendimento nem no Testar real.
O Testar da Lia mantém seu desvio com portão, mas a Lia não recebe ferramentas prontas.

## Premium

Não foi encontrada situação adicional de saldo ou cobrança no JSON que a execução devolve ao turno. As situações
internas são convertidas pela execução antes de chegar ao Bound:

- `sem_registro` vira `nao_encontrado`: continua sendo dado.
- `falha` vira `nao_consegui_consultar`: não é dado e passa pelo registro de recusa do principal.
- `documento_invalido` é a resposta da fonte, inclusive do cache: continua sendo dado e consulta contada.
- `em_andamento` é um resultado da telemetria do Experimente, não uma situação final do executor no turno.
- `gratis`, `cobrada`, `sem_cobranca`, `do_cache`, `sem_clique_no_preco` e `entrega_incerta` são estados ou motivos de
  cobrança/telemetria. Nenhuma regra deles foi alterada. O cache conserva a situação da leitura original.
- `desligada` aparece na API do Experimente Premium, fora deste caminho; foi preservada.

## Cobertura escrita, sem execução

- `answerer_dado_de_ferramenta_spec.rb`: contador na falha direta, fluxo real principal → Runner do especialista →
  pronta indisponível, resposta do principal preservada e contador inalterado nesse fluxo interno. O Guia também
  percorre o Answerer, com resposta e contador preservados. Mantidos os casos de pedido corrigido e dados válidos.
- `answerer_interacao_spec.rb`: dublê do Bound adaptado a `situacao_da_pronta(output)`.
- `tools/bound_pronta_spec.rb`: leitura das respectivas saídas fora da ordem de execução, saída sem objeto JSON com
  a chave, HTTP cadastrado ignorado e falha recebida na janela do segundo plano. Removido o exemplo interno que
  só executava o Bound e conferia o contador; ele não exercitava o principal nem o especialista.
- `tools/recusa_registro_spec.rb`: gatilho `answerer.rb#ler_saida_pronta#1` e conferência do registro pelo Answerer,
  com agente e conversa do turno.
- `premium/execucao_premium_spec.rb`: falha 504 pelo Answerer, com texto da ferramenta preservado e recusa; pedido
  corrigido, ausência de registro e documento inválido na fonte/cache pela leitura das respectivas saídas.

Nenhum desses specs foi rodado nesta rodada.

## Limites conhecidos

- A saída cortada em 8.000 letras deixa de ser JSON e conta como dado. Isso inclui um `pedido_invalido` maior que
  o teto. Não há tentativa de inferir a situação pelo prefixo do texto.
- A consulta em segundo plano que falhou depois de o turno desistir devolve texto, não JSON, ao turno seguinte;
  esse texto conta como dado. Hoje isso é inerte para o portão: o segundo plano exige conversa e quem tem conversa
  roda sem portão, com `trust_instruction: true`.
- `consulta_pronta_indisponivel` cobre também limite do dia, conta sem acesso e flag desligada. A causa real fica
  somente na linha `[autonomia][pronta] motivos=`; o código da recusa não distingue essas causas.
- A falha de pronta fica fora de `RecusasRecentes::NA_NOTA` de propósito. Incluí-la criaria uma nota privada nova
  no atendimento; essa mudança depende de decisão do dono do produto. A lista foi preservada.

## Validação executada nesta revisão

Somente os oito arquivos Ruby tocados nesta rodada:

```sh
eval "$(rbenv init -)" && RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop --no-server \
  app/services/autonomia/agents/answerer.rb \
  app/services/autonomia/agents/tools/bound.rb \
  app/services/autonomia/agents/tools/leitura_da_pronta.rb \
  spec/services/autonomia/agents/answerer_dado_de_ferramenta_spec.rb \
  spec/services/autonomia/agents/answerer_interacao_spec.rb \
  spec/services/autonomia/agents/tools/bound_pronta_spec.rb \
  spec/services/autonomia/agents/tools/recusa_registro_spec.rb \
  spec/services/autonomia/ferramentas_prontas/premium/execucao_premium_spec.rb
```

Saída final completa do RuboCop, retorno 0:

```text
Inspecting 8 files
........

8 files inspected, no offenses detected

Tip: Based on detected gems, the following RuboCop extension libraries might be helpful:
  * rubocop-rspec_rails (https://rubygems.org/gems/rubocop-rspec_rails)

You can opt out of this message by adding the following to your config (see https://docs.rubocop.org/rubocop/extensions.html#extension-suggestions for more options):
  AllCops:
    SuggestExtensions: false
```

As duas primeiras passagens encontraram cinco infrações de alinhamento cada; foram corrigidas sem desativar
regras ou alterar limites. A passagem seguinte não encontrou infrações. Na conferência estática final, a pronta
Premium do spec passou a ser criada antes de o Answerer montar o catálogo; o RuboCop foi repetido após esse ajuste.

`ruby -c` retornou `Syntax OK` para os oito arquivos Ruby tocados. A sintaxe do spec Premium foi conferida de novo
após o último ajuste. `git diff --check` terminou sem saída.
Não foram executados RSpec, build, servidor, Rails, consultas a banco ou avaliações com provedores pagos.

## Riscos e entrega

- A validação local é estática; os specs rodaram só na CI do PR. Não há prova de produção.
- A recusa permanece no turno mesmo se outra consulta posterior tiver sucesso. Prontas são leitura: o contador
  recebido por `UmaEscritaPorTurno#concluir` não muda quais escritas contam como feitas.
- O contador continua isolado por fio de execução. Paralelizar ferramentas em outros fios exigiria transportar a
  recusa; o Bound agora não guarda estado da leitura, mas o contador não foi redesenhado.
- Não foi encontrado override correspondente no Enterprise para os componentes alterados.
- O PR #3008 está aberto, em rascunho. Nenhum merge ou deploy foi feito.
- Rollback: reverter a alteração de classificação no código, sem migração ou mudança de dados.
