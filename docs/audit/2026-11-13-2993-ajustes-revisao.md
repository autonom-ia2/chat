# #2993 — ajustes da revisão do PR #3001

Branch: `feat/2993-veiculo-pela-placa`. Alterações locais, sem commit, push ou operação de troca/limpeza de Git.

## Decisões e alterações

- A: a listagem vem de `FerramentasProntasController#index` e `FerramentasProntas.da_vitrine`. A quantidade das fontes grátis
  foi acrescentada à representação já existente em `index.json.jbuilder`, como `consultas: fonte.consultas.size`.
  `useVitrine` repassa a conta ao cartão; `catalogo.js` deixou de guardar quantidades. Sem conta ou com uma consulta,
  não há selo. Premium continua usando sua conta existente. Textos en/pt_BR e ajuda condicionam a consulta pela placa
  à disponibilidade na instalação. O roteiro pede marca/modelo/ano sem essa ferramenta e registra a origem sem confirmação.
- B: `Fipe::VEICULO` instrui o modelo a guardar os identificadores para a equipe, sem revelar chassi nem placa achada pelo chassi.
- C: cadastro inválido avisa só o campo, uma vez por processo, com mutex. Variável ausente não avisa.
- D: a conversão dos status de ausência em `NaoEncontrado` avisa só nome interno e status. `Execucao` não mudou.
- E: comentários e termos foram reduzidos ao necessário, sem descrever o protocolo ou exemplos que identifiquem a fonte.
- F: `ano_fabricacao` é identificação e não recebe separador de milhar no Experimente.
- G: dois exemplos de schema cobrem a presença/ausência da configuração e a exigência de tipo por consulta; sem alterar o schema.
- H: `inspect` e `to_s` ocultam o estado do provedor, como em `Premium::Tokens`.
- I: o host desligado é conferido antes da entrada, com `Falha, 'provedor_desligado'`.
- J: exemplos cobrem falha pelo servidor sem contar queda de proxy e POST com redirecionamento recusado sem seguir o destino.

Não foi acrescentado teto diário ao host. Não houve alteração em `teto_do_provedor.rb`, `Execucao` ou permissões.
A busca no overlay Enterprise não encontrou implementação correspondente que precisasse mudar.
Não houve operação externa no PR ou no Project. Review, aprovação e entrega continuam pendentes.

## Validação permitida

- Leitura estática dos caminhos e revisão do diff; `git diff --check`: sucesso.
- `seguro_auto.md`: 6.327 bytes; teto de 8.000 em `ModelosDeRamo::Formato::ROTEIRO_MAX`, coberto pelo spec de modelos de ramo.
- Leitura dos quatro JSONs en/pt_BR editados com o parser JSON: sintaxe válida.
- `ruby -c` nos seis caminhos abaixo: seis saídas `Syntax OK`.
- Nenhum spec foi rodado. RSpec, Vitest, build e servidor não foram executados. Nenhum runtime Rails foi iniciado.
- O checker i18n não foi executado; a validação ficou limitada à sintaxe dos catálogos e às verificações autorizadas.

Arquivos Ruby/Jbuilder conferidos:

```text
app/services/autonomia/ferramentas_prontas/fontes/fipe.rb
app/services/autonomia/ferramentas_prontas/fontes/fipe/pela_placa.rb
app/views/api/v1/accounts/autonomia/ferramentas_prontas/index.json.jbuilder
spec/services/autonomia/ferramentas_prontas/fontes_fipe_veiculo_spec.rb
spec/services/autonomia/ferramentas_prontas/cliente_http_saida_spec.rb
spec/requests/api/v1/accounts/autonomia/ferramentas_prontas/vitrine_spec.rb
```

RuboCop: a primeira tentativa parou por permissão ao escrever no cache externo à worktree. O cache foi desativado.
As passagens seguintes apontaram complexidade e alinhamento, corrigidos antes da última execução (retorno 0).

Comando final (com inicialização do rbenv):

```sh
eval "$(rbenv init -)" && bundle exec rubocop --cache false \
  app/services/autonomia/ferramentas_prontas/fontes/fipe.rb \
  app/services/autonomia/ferramentas_prontas/fontes/fipe/pela_placa.rb \
  app/views/api/v1/accounts/autonomia/ferramentas_prontas/index.json.jbuilder \
  spec/services/autonomia/ferramentas_prontas/fontes_fipe_veiculo_spec.rb \
  spec/services/autonomia/ferramentas_prontas/cliente_http_saida_spec.rb \
  spec/requests/api/v1/accounts/autonomia/ferramentas_prontas/vitrine_spec.rb
```

Saída integral da última execução:

```text
Inspecting 6 files
......

6 files inspected, no offenses detected

Tip: Based on detected gems, the following RuboCop extension libraries might be helpful:
  * rubocop-rspec_rails (https://rubygems.org/gems/rubocop-rspec_rails)

You can opt out of this message by adding the following to your config (see https://docs.rubocop.org/rubocop/extensions.html#extension-suggestions for more options):
  AllCops:
    SuggestExtensions: false
```

## Specs alterados, todos sem execução

- `spec/requests/api/v1/accounts/autonomia/ferramentas_prontas/vitrine_spec.rb`: listagem com contagens e FIPE com três/quatro consultas.
- `spec/services/autonomia/ferramentas_prontas/fontes_fipe_veiculo_spec.rb`: avisos sem dados, schema, descrição, inspect e bloqueio antes da rede.
- `spec/services/autonomia/ferramentas_prontas/cliente_http_saida_spec.rb`: falha pelo servidor e redirecionamentos no POST.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/VitrineCartao.spec.js`: conta do servidor e ausência do selo.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/VitrinePage.spec.js`: mock da leitura de contagens.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/useVitrine.spec.js`: transporte da contagem da API.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/resultadoDasFontes.spec.js`: ano de fabricação sem agrupamento em pt_BR/en.
