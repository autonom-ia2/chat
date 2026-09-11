# Entrega 7 — medir para cobrar e para mostrar retorno

Data: 11/09/2026. Plano: entrega 7 do Agente de Cotação (6 termos de aceite). Issue-mãe: #291.
Depende das entregas 5 (intenção de envio) e 10 (pedido repetido), que são de onde saem as marcas do
handle que a medida lê para dizer o que NÃO sabe.

## O achado que define o desenho

O número de seguradoras acionadas **sempre existiu** — vem no `quote/result` a cada consulta do poll —
e **morria ali**. O handle guardava só `entregues`: quem COTOU, que é o que já foi para o cliente. Na
renovação real de 11/09/2026 eram onze de dezessete; as outras seis (recusa de risco) não deixavam
rastro nenhum, e a corretora pagou pelas dezessete.

Medido no mesmo dia, lendo por `agger quote result` as três cotações reais da conta de teste (leitura,
sem gastar cotação):

| cotação | `quoted` | `declined` | `auth_required` | **ofertas** |
|---|---|---|---|---|
| renovação `b0220871-…:1` | 11 | 6 | 0 | **17** |
| moto `91bef437-…:1` | 2 | 15 | 0 | **17** |
| caminhão `4c278fcf-…:1` | 1 | 15 | 1 | **17** |

Os mesmos dezessete códigos nas três (`1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55`). O caminhão é o
caso que decide a regra: **contar só `quoted` + `declined` diria dezesseis** — uma seguradora a menos
do que a corretora acionou, e justamente a que ela precisa ver (credencial recusada, critério 4.5).
Por isso `QuoteOffers#acionadas` conta TODAS as ofertas, em qualquer status.

## O desenho

- **A matéria-prima fica no handle da execução.** `InsuranceQuote::ACIONADAS_KEY`
  (`seguradoras_acionadas`) é gravada em `build_progress` — na primeira consulta e em todas as
  seguintes — como **união**, nunca como foto: o portal responde em pedaços (medido em 04/09: 3 de 6
  seguradoras em ~35 s, o negócio só assentou aos 392 s), e uma consulta que devolvesse menos do que a
  anterior apagaria seguradoras já pagas. União é idempotente: reconsulta não muda nada. Nenhuma
  chamada nova ao portal — o dado já vinha no `quote/result`.
- **A consulta é `Autonomia::Insurance::Medida`**, uma agregação jsonb sobre
  `autonomia_agent_tool_runs`, agrupada por `account_id` e filtrada por `slug` + `created_at`. O
  índice `idx_autonomia_tool_runs_account_slug (account_id, slug, created_at)` já existia e é
  exatamente o desta consulta — **sem migration**.
- **Nomes de chave vêm das constantes**, nunca digitados na consulta: um rename silencioso faria a
  medida devolver zero, e zero é o número que ninguém questiona (M11).
- **O que a medida não sabe, ela diz.** Três colunas separadas, nunca somadas nos totais:
  `cotacoes_sem_medida` (a cotação existe no portal e o número de seguradoras não foi lido — execução
  morta antes da primeira consulta, ou linha anterior a esta entrega), `cotacoes_sem_confirmacao`
  (intenção anotada sem número: PODE existir no portal) e `cotacoes_possivelmente_duplicadas` (pode
  haver uma A MAIS no portal do que a contada).
- **A janela é lida no fuso da CORRETORA** (`account.reporting_timezone`, o mesmo dos relatórios do
  Chatwoot) quando ela configurou um; sem configuração, o da instalação. "Setembro" da corretora
  termina às 23h59 dela: ler pelo nosso fuso jogaria para outubro toda cotação feita depois das 21h
  de 30/09 em São Paulo — o nosso valor no lugar do dela, numa conta de dinheiro. O resultado sempre
  devolve o fuso e os instantes exatos (a tela do Super Admin, que é cross-conta, usa o da instalação
  e diz isso).
- **Duas superfícies, uma fonte.** Super Admin → *Quote Measurement* (`/super_admin/insurance_measurement`)
  para a operação cobrar; `GET /api/v1/accounts/:id/autonomia/insurance/measurement` para a corretora
  ver o retorno. As duas leem a MESMA `Medida` — dois números diferentes para o mesmo mês, um na
  fatura e outro na tela do cliente, seriam pior do que número nenhum.

### Por que a página do Super Admin, e não só o endpoint (termo 4)

O termo é "não depende de engenheiro". Um endpoint da conta ainda exige token, `curl` e alguém que
saiba montar a URL — é caminho de integração, não de operação. A página do Super Admin custa um
controller (16 linhas), uma view ERB e uma rota, reusa o layout e o gate que já existem, e resolve o
termo de verdade: abre, escolhe duas datas, lê a tabela. O endpoint fica porque a **corretora** não
tem Super Admin e precisa do mesmo número que a fatura dela usa.

### `proposals` é zero, e o contador é real (termo 3)

A ferramenta de proposta por seguradora é a entrega 8. O contador já existe e conta de verdade
(`InsuranceQuote::PROPOSTAS_KEY`, lido pela medida); hoje lê zero porque **ninguém escreve a chave**.
Não é um `0` literal — a mutação M8 troca a coluna por `0` e um exemplo reprova.

**Ponto de registro da entrega 8:** o handle da execução, na passada que gerar a proposta. O caminho é
`quote/proposal` com `insurer_code` (o conector já o tem; `comparison_pdf` usa o mesmo endpoint SEM
código para o comparativo). Escrever ali a lista de códigos faz a medida contar sem mudar uma linha.

## Termos (6)

| # | Termo | Estado | Guarda / evidência |
|---|---|---|---|
| 1 | Consulta por corretora e por período devolve cotações E seguradoras acionadas | Fechado | `medida_spec` ("os dois números", "isolamento e janela", incluindo as DUAS bordas da janela e a recusa de medir conta que não se sabe qual é), `measurement_spec` (API, as duas bordas), `insurance_measurements_controller_spec` (Super Admin); M4, M7, M14, M16 |
| 2 | O número bate com o caso conhecido: dezessete acionadas → dezessete | Fechado | `medida_spec` "conta dezessete seguradoras quando a execução acionou dezessete" (os 17 códigos reais); `insurance_quote_medida_spec` "grava as dezessete, em qualquer status" (1 quoted + 15 declined + 1 auth_required, o desenho do caminhão real) e "nao infla a lista quando o portal repete o mesmo resultado" (duas passadas, dezessete nas duas); M1, M2, M15 |
| 3 | Quantas cotações viraram proposta individual; contador definido e zerado, ponto de registro documentado | Fechado | `medida_spec` "propostas individuais (entrega 8)" (zero hoje; conta de verdade quando a chave existe); M8; ponto de registro na seção acima e em `insurance_quote.rb` |
| 4 | A consulta não depende de engenheiro | Fechado | Página do Super Admin + endpoint da conta, documentados em `docs/insurance/README.md`; `insurance_measurements_controller_spec`, `measurement_spec` (gate e permissão); M6 |
| 5 | Nada aqui vira freio | Fechado | `medida_nao_e_freio_spec` (por AST: a medida só é nomeada pelas superfícies de leitura, não é alcançada do caminho da cotação, e não escreve); M9 |
| 6 | O teto de oito por hora não voltou | Fechado | `bound_async_spec` "there is NO ceiling" (vinte execuções na ÚLTIMA HORA, a vigésima primeira é aceita) + `async_config_sem_teto_de_execucoes_spec` (a constante pelo nome); M10 |

### O que fica para prova real / produção

Nada de comportamento novo em conversa: a entrega não muda uma linha do que o cliente lê nem do que
o modelo recebe. O que só a produção fecha é o **dado**: linhas anteriores a 11/09/2026 não têm
`seguradoras_acionadas` e aparecem em `cotacoes_sem_medida` — inclusive as três cotações reais da
conta 16, que foram lidas por CLI e não pelo poll desta versão. A medida passa a ser completa a
partir da primeira cotação depois do deploy. **Não há backfill**: reprocessar exigiria chamar
`quote/result` de cada cotação antiga, e o portal não garante a leitura de cotação encerrada.

## Rodada de correção — duas regras que só existiam no comentário

Revisão cega reprovou a primeira versão com dois achados, e os dois eram reais: reproduzi cada um
antes de corrigir, e nos dois casos os 62 exemplos do trilho passaram COM a regra desligada.

- **A janela só tinha a borda de baixo.** `created_at: inicio..fim` virava `created_at: inicio..` sem
  nada ficar vermelho. Nenhum exemplo criava execução DEPOIS do `fim` — "respeita o periodo pedido"
  só exercitava a linha de 40 dias atrás. O estrago é o pior tipo: a operação pede setembro, a
  cotação de 01/10 entra na fatura de setembro, e a conta fica MAIOR. Número inflado em fatura
  ninguém questiona.
- **A união não era provada idempotente.** O comentário dizia "reconsulta não muda nada" e trocar
  `|` por `+` passava em 62 exemplos do trilho E em 590 de `spec/services/autonomia/agents` +
  `spec/jobs/autonomia`. O portal lista as dezessete desde a PRIMEIRA consulta e o poll consulta a
  cada passada: com `+`, a segunda passada grava 34, a vigésima grava 340 — a medida cobraria
  trezentas e quarenta seguradoras por UMA cotação. Os exemplos existentes não pegavam porque
  "nao perde quem ja tinha aparecido" usa handle `%w[3 9]` contra resultado `['8']` (sem interseção)
  e "nao repete a mesma seguradora" só cobre duplicata DENTRO de uma consulta.

A classe do defeito é uma só — **regra escrita no comentário e não exercitada por nenhum exemplo** —,
então varri as demais decisões da entrega em vez de corrigir só os dois casos. A varredura achou mais
uma: `call` sem conta tem `raise ArgumentError` e nenhuma spec o sustentava; sem ele, `por_conta.first`
devolve a linha da PRIMEIRA corretora com o nome desta, numa conta de dinheiro. Está guardada em M16.
As demais (slug, escopo por conta, `jsonb_typeof`, `.sort`, `.uniq`, `.presence`, fuso, janela
invertida, janela padrão) já tinham guarda — conferido mutação a mutação.

## Mutações (16) — todas aplicadas, rodadas, restauradas e conferidas

Cada uma desliga UMA regra e reprova o exemplo que a sustenta. Restauração conferida por comparação
do conteúdo do arquivo com o original.

| # | Mutação | Arquivo | Reprova |
|---|---|---|---|
| M1 | `acionadas` conta só `quoted` + `declined` | `quote_offers.rb` | "grava as dezessete, em qualquer status" (dá 16 — o caso do caminhão) |
| M2 | `build_progress` não grava `ACIONADAS_KEY` | `insurance_quote.rb` | 8 exemplos de "seguradoras acionadas no handle" |
| M3 | a lista vira a foto da última consulta (sem união) | `insurance_quote.rb` | "nao perde quem ja tinha aparecido numa consulta anterior" e "nao conta de novo quem o handle ja tinha" |
| M4 | a medida conta execução em vez de cotação no portal | `medida.rb` | "nao conta execução que nunca virou cotação", "separa o envio sem confirmação" |
| M5 | `cotacoes_sem_medida` vira `0` | `medida.rb` | 3 exemplos (serviço + API) |
| M6 | data ilegível cai na janela padrão em silêncio | `medida.rb` | 3 exemplos (serviço + API + Super Admin) |
| M7 | a medida deixa de escopar por conta | `medida.rb` | "nao mistura corretoras" (API) |
| M8 | `propostas` vira zero escrito à mão | `medida.rb` | "conta as propostas registradas no handle" |
| M9 | a medida entra no caminho da cotação (o freio pela porta dos fundos) | `insurance_quote.rb` | os 2 exemplos de alcance de `medida_nao_e_freio_spec` |
| M10 | `MAX_RUNS_PER_CONVERSATION = 8` por hora de volta no `Bound` | `bound.rb` | a guarda pelo nome E o exemplo de comportamento |
| M11 | a medida lê um slug digitado à mão | `medida.rb` | 12 exemplos, a começar por "le o slug da propria ferramenta" |
| M12 | o job descarta a chave (`ACIONADAS_KEY` entra em `MARCAS`) | `async_run_job.rb` | "sobrevive ao job e fica no handle que a medida soma" |
| M13 | a janela ignora o fuso da corretora | `medida.rb` | "le as datas no fuso de relatorio da corretora" |
| M14 | a janela perde a borda de cima (`inicio..fim` → `inicio..`) | `medida.rb` | "nao conta cotação feita depois do fim da janela" (serviço + API) |
| M15 | a união vira soma (`\|` → `+`) | `insurance_quote.rb` | "nao infla a lista quando o portal repete o mesmo resultado" e "nao conta de novo quem o handle ja tinha" |
| M16 | a medida de uma conta aceita não saber qual é (sem o `raise`) | `medida.rb` | "recusa medir uma conta sem saber qual é" |

M12 é a que mais importa: sem ela, uma chave que a ferramenta grava e o job descarta passaria em
todos os exemplos de unidade e sumiria em produção. M14 e M15 são as duas que a primeira versão não
tinha, e as duas inflavam o número de COBRANÇA — erro que ninguém contesta, porque quem paga a mais
não reclama de um total que parece grande.

## Comandos rodados

```bash
# leitura real, sem gastar cotação (conta de teste)
set -a; . ~/dev/projetos.noindex/agger_full/env.local; set +a
export AGGER_TEST_EMAIL=$LOGIN_AGGER_TESTE AGGER_TEST_PASSWORD=$SENHA_AGGER_TESTE
npx tsx src/cli/main.ts agger quote result 'b0220871-e7da-4a84-adb7-bcff2641eb1e:1'   # 17 ofertas
npx tsx src/cli/main.ts agger quote result '91bef437-e764-41c9-b6e8-bcfcf8e62d15:1'   # 17
npx tsx src/cli/main.ts agger quote result '4c278fcf-a456-447a-a06e-e49f7a93baa8:1'   # 17

# chat2you (banco de teste próprio do trilho)
eval "$(rbenv init -)"; export POSTGRES_DATABASE=chatwoot_test_e7
RAILS_ENV=test bundle exec rails db:create db:schema:load
bundle exec rspec <specs do trilho> --format json --out r.json      # 67 exemplos, 0 falhas
bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia \
  --format json --out ampla.json                                    # suíte ampla
bundle exec rubocop --format json --out rubocop.json <arquivos tocados>   # 0 ofensas
uv run python3 mutacoes.py                                          # M1–M16 (919 na suíte ampla)
```

## Arquivos

Novos: `app/services/autonomia/insurance/medida.rb`,
`app/controllers/api/v1/accounts/autonomia/insurance/measurement_controller.rb`,
`app/views/api/v1/accounts/autonomia/insurance/measurement/show.json.jbuilder`,
`app/controllers/super_admin/insurance_measurements_controller.rb`,
`app/views/super_admin/insurance_measurements/show.html.erb`, e cinco specs.

Tocados: `quote_offers.rb` (`#acionadas`), `insurance_quote.rb` (as duas chaves e a união),
`async_config.rb` (o comentário apontava para uma spec que não existia — agora existe),
`_navigation.html.erb`, `config/routes.rb`, `docs/insurance/README.md`, `bound_async_spec.rb`
(a hora explícita no exemplo do teto).
