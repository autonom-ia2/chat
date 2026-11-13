# #3006 — consulta pronta que falhou não é dado do turno

- Issue: https://github.com/autonom-ia2/chat/issues/3006
- Branch: `fix/3006-consulta-que-falhou-nao-e-dado`.
- Escopo: o conserto da Issue. Escrito sem rodar os specs na máquina; eles rodam na CI do PR.

## Decisão

A ferramenta ligada (`Tools::Bound`) guarda a `situacao` da resposta JSON antes do seu corte de tamanho. O módulo
`Tools::LeituraDaPronta` declara `sem_dado?`; não interpreta frases nem aplica expressão regular.

| Situação da resposta | Dado | Recusa do turno |
| --- | --- | --- |
| `encontrado` | sim | não |
| `nao_encontrado` | sim | não |
| `documento_invalido` | sim | não |
| `pedido_invalido` | não | não; uma tentativa corrigida pode contar |
| `nao_consegui_consultar` | não | sim; permanece até o fim do turno |

O principal pede o registro após o despacho da ferramenta direta e antes de comparar o contador de recusas. A
recusa usa `Recusa.registrar`, sem `Recusa.para_modelo` ou `Recusa.saida`: o JSON entregue ao modelo continua igual.
O motivo novo, `consulta_pronta_indisponivel`, evita afirmar que toda falha foi uma resposta HTTP com erro
(`tool_http_error`) ou uma exceção (`tool_execution_error`): a mesma saída também cobre flag, acesso e limites.

O registro fica restrito às chamadas diretas de ferramenta do principal. As consultas internas do especialista e
do ajudante não pedem esse registro. O Guia (`operador`) não recebe a nova classificação. HTTP cadastrada e nativa
não têm a `situacao` interpretada. Nenhum arquivo de cotação foi alterado.

O Answerer ganhou duas linhas, sem reordenação ou refatoração. O predicado `Bound#consulta_em_andamento?` foi movido,
com corpo idêntico, para o módulo de leitura: a inclusão e a anotação excediam o limite de tamanho do Bound.

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

- Answerer: fonte indisponível com resposta contendo valor, pedido inválido sozinho, tentativa corrigida no mesmo
  turno, ausência de registro e falha com dado de outra ferramenta no turno.
- Bound/prontas: texto original preservado, contador de recusas, pedido corrigido, Guia, consulta interna de
  especialista/ajudante, HTTP cadastrado com o mesmo JSON e falha recebida na janela do segundo plano.
- Premium: falha 504, pedido corrigido, ausência de registro e documento inválido na fonte/cache, mantendo a cobrança.
- Guarda de recusas: gatilho para a nova saída e seu motivo no catálogo.
- Os dois dublês existentes do Bound no Answerer foram atualizados para os métodos do contrato.

## Validação executada

Comando final (somente os nove arquivos Ruby alterados):

```sh
eval "$(rbenv init -)" && RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop --no-server \
  app/services/autonomia/agents/answerer.rb \
  app/services/autonomia/agents/tools/bound.rb \
  app/services/autonomia/agents/tools/recusa.rb \
  app/services/autonomia/agents/tools/leitura_da_pronta.rb \
  spec/services/autonomia/agents/answerer_dado_de_ferramenta_spec.rb \
  spec/services/autonomia/agents/answerer_interacao_spec.rb \
  spec/services/autonomia/agents/tools/bound_pronta_spec.rb \
  spec/services/autonomia/agents/tools/recusa_registro_spec.rb \
  spec/services/autonomia/ferramentas_prontas/premium/execucao_premium_spec.rb
```

Saída final, retorno 0:

```text
Inspecting 9 files
.........

9 files inspected, no offenses detected
```

O RuboCop também exibiu uma sugestão opcional de extensão, sem infração. A primeira tentativa foi bloqueada antes
da análise ao tentar criar cache fora do worktree (`Errno::EPERM`); as seguintes usaram cache local e `--no-server`.
As infrações intermediárias de tamanho, complexidade e formatação foram corrigidas sem desativar regras.

`ruby -c` retornou `Syntax OK` para cada um dos nove arquivos. `git diff --check` terminou sem saída.
Não foram executados RSpec, Vitest, build, servidor, Rails ou consultas a banco.

## Dúvidas e riscos

- Não há prova de execução dos specs: foram escritos e conferidos estaticamente, como solicitado.
- A busca em `app`, `enterprise` e `lib` encontrou as marcas `@dado_de_sistema` e `@recusa_no_turno` somente no
  Answerer. `leu_dado_de_sistema?` alimenta os três portões descritos na issue: confiança, especificidades sem base
  e afirmação do negócio sem âncora. A recusa permanece no turno mesmo se outra consulta posterior tiver sucesso.
- `UmaEscritaPorTurno#concluir` recebe a mesma comparação de recusas. Prontas são leitura, portanto a nova recusa
  não muda quais escritas contam como feitas.
- `Recusa.registrar` também chama `RecusasRecentes.anotar`. A lista `NA_NOTA` não inclui o motivo novo; a falha
  fica no log/contador, mas não acrescenta uma nota à equipe. A lista foi preservada.
- O contador continua isolado por fio de execução, como antes. Uma futura execução paralela das ferramentas em
  outros fios precisaria transportar a recusa; nada dessa concorrência foi alterado aqui.
- Situação desconhecida conserva a regra anterior. Saída em segundo plano que já chegue como JSON cortado também
  conserva a regra anterior; não foi criada inferência sobre prefixo de texto. As falhas de consulta atuais são
  respostas curtas. A classificação local ocorre antes do corte do Bound.
- Não foi encontrado override correspondente no Enterprise para os componentes alterados.
- A entrega está limitada ao working tree por instrução explícita. O fluxo de PR/review/release permanece pendente;
  nenhum merge ou deploy foi solicitado. Reverter esta alteração local restaura a classificação anterior, sem
  migração ou alteração de dados.
