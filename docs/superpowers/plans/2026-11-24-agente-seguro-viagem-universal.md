# Plano de implementação: agente pronto "Seguro Viagem Universal" (PR 2 da #3211)

> Para quem executa: siga as tarefas na ordem. Cada tarefa tem spec que falha primeiro, implementação, verificação e
> dois commits (teste e código separados). As tarefas de tela só começam depois da Tarefa 24 (gate do mockup).

**Objetivo.** O corretor contrata, na área de Agentes, o agente "Seguro Viagem Universal": informa nome do agente,
nome e descrição da corretora, depois login e senha do portal da Universal, depois a caixa. O agente vende seguro viagem
ao viajante final de ponta a ponta, com instrução mantida por nós (`instrucao.md`, já commitada), base oficial semeada,
três ferramentas nativas (cotar, detalhes, proposta com link de pagamento) e as opções de conversa do PR 1 ligadas.

**Arquitetura.** O contratado é um agente `sdr` comum com a marca `config['contratado']`. `Agent#contratado?` lê a
marca; `Agent#instrucao_mantida?` passa a ser `insurance_quote || contratado?`, e isso tranca todos os escritores da
instrução sem código novo em cada um. A instrução é lida do arquivo a cada turno e recebe `$nomeAgente`,
`$nomeCorretora`, `$sobreCorretora` e `$dataDeHoje`. O catálogo (`Autonomia::Agents::Contratados`) diz o arquivo, as
ferramentas fixas, a base e as opções de conversa de cada modelo. A Universal é chamada por um cliente HTTP próprio
(`Autonomia::Seguradoras::Universal::Cliente`) com o acesso cifrado guardado por agente
(`Autonomia::Agents::AcessoDaSeguradora`). A cotação fica em `autonomia_cotacoes_de_viagem`, e a proposta lê dela:
preço e plano nunca vêm do modelo.

**Tecnologia.** Rails 7.2 (fork do Chatwoot), Postgres jsonb, ActiveRecord Encryption (`encrypts`), Net::HTTP, Prawn,
Sidekiq + sidekiq-cron, Vue 3 `<script setup>`, Tailwind, Vitest, Histoire + Playwright headless para os prints.

**Desenho aprovado.** `docs/superpowers/specs/2026-11-24-agente-seguro-viagem-universal-design.md` (tudo, menos a
seção 8, que é o PR 1). Instrução aprovada: `app/services/autonomia/agents/contratados/seguro_viagem_universal/instrucao.md`.

---

## Restrições globais

Regras da casa, como estão nos fatos levantados (copiadas sem mudança):

```text
- No local rspec: specs run only on CI. Write specs and do not run them locally. `pnpm eslint` and `pnpm test` (vitest) are allowed locally.
- No regex to interpret language. Avoid regex in general; use string methods and parsers.
- No native `<select>`: use `components-next/choice-select/ChoiceSelect.vue`.
- Tailwind only; no custom/scoped/inline CSS. Composition API `<script setup>`.
- i18n: only `en` and `pt_BR`, following `docs/i18n/fork-translations.md`; `pnpm i18n:fork:check`.
- Enterprise overlay: check `enterprise/` for counterparts.
- Guia: a new route/screen needs a block in `lib/operator_guide/porques.md` plus `pnpm guia:build`. Touching a controller or strong params needs `bundle exec rails autonomia:guia:formatos`.
- Commits in Conventional Commits, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never chain test && commit.
- The repo is PUBLIC: no client names or account numbers in code, comments, specs, PR or plan.
- Do not touch the Lia's behaviour (`insurance_quote`).
- A new screen needs a mockup in screenshots approved by Rodrigo before implementation. The UI tasks in the plan come after a "mockup approved" gate.
```

Guardas do repositório que varrem tudo e quebram a CI fora da pasta da feature (lidas no código e na memória do
projeto; cada uma tem tarefa própria abaixo):

- `spec/services/autonomia/exclusao_da_conta_spec.rb`: toda tabela nova com chave para `accounts` entra em
  `Autonomia::ExclusaoDaConta::ETAPAS` (Tarefa 5).
- `spec/services/autonomia/insurance/receita/sem_texto_fixo_ao_cliente_spec.rb`: todo ponto novo que cria mensagem em
  `app/services/autonomia` ou `app/jobs/autonomia` entra em `TextoAoCliente::PONTOS`, chave `arquivo::Classe#metodo`
  (Tarefa 14).
- `spec/services/autonomia/automacao/acoes_permitidas_spec.rb`: controller novo com ação de escrita entra em
  `lib/operator_guide/automacao-recursos.yml` (Tarefa 21).
- `spec/services/autonomia/agents/tools/native/base_escreve_declarado_spec.rb`: toda nativa do `Registry` declara
  `escreve?` (Tarefa 19).
- Vitest de outra pasta que importa as rotas reais quebra quando a rota muda: depois de mexer em rota, rodar também
  `pnpm test app/javascript/dashboard/modules` (Tarefa 29).

Como rodar o que é permitido localmente:

```sh
eval "$(rbenv init -)"
bundle exec rubocop <arquivos tocados>        # leia a saída inteira; sem -A sem reler o diff
pnpm eslint <arquivos tocados>
pnpm test <pasta ou arquivo do vitest>       # leia a linha de falhas, não a contagem
pnpm i18n:fork:check
pnpm guia:check
```

Specs Ruby: escreva, commite e deixe a CI rodar. Passo "Rodar" de toda tarefa Ruby: **não rodar localmente; roda na CI.**

---

## Foco da revisão (o que mais provavelmente morde)

| # | Modo de falha | Teste que pega | Tarefa dona |
|---|---|---|---|
| R1 | Estender `instrucao_mantida?` muda a Lia, ou muda em silêncio um leitor que não é escritor da instrução (passagem da IA do CRM, F1, material, foto). | `agent_lia_inalterada_spec.rb` (instrução, ferramentas, rodadas e predicados da Lia idênticos) e `leitores_de_instrucao_mantida_spec.rb` (um exemplo por leitor, com a decisão escrita). | 7 e 8 |
| R2 | Comissão, markup, ranking ou dado pessoal chega ao modelo, ao PDF, ao banco ou ao log. | `planos_spec.rb` monta os planos da resposta gravada e afirma que o JSON não contém `comissao`, `comissaoIntermediario`, `markup`, `rank`, `quotationPorcentagem`, `valorSemDesconto`; `cliente_spec.rb` captura o log e afirma que não tem `Senha`, login, CPF nem corpo. | 10 e 13 |
| R3 | Preço ou plano da proposta vem do texto do modelo; ou a proposta sai duas vezes. | `gerar_proposta_seguro_viagem_spec.rb`: `ValorCompra` e `CodigoProduto` enviados são os da cotação guardada; código inexistente é recusado sem chamar a Universal; segunda chamada igual não faz segundo `POST /v1/Compras`. | 17 |
| R4 | A ferramenta fica disponível para agente que não é o contratado (PATCH em `native_tool_slugs`), ou sem acesso conferido, ou a proposta para login "só cota". | `ferramentas_do_contratado_spec.rb`: `Registry.for_agent` de um `sdr` comum com os três slugs gravados devolve nenhum; do contratado com acesso `nao_conferido` devolve nenhum; com `soCotacao: true` devolve cotar e detalhes, sem proposta. | 19 |
| R5 | Login ou senha da Universal sai pela API, pelo jbuilder, por log ou por erro; a recusa da ferramenta não passa pelo registro e trava a próxima escrita do turno (`UmaEscritaPorTurno`). | `acesso_da_seguradora_spec.rb` (request): resposta sem `senha`, sem `login` completo, só `login_dica`; `falhas_spec.rb`: toda recusa chama `Tools::Recusa.registrar`, e o erro de HTTP nunca levanta da ferramenta. | 21 e 18 |

---

## Mapa de arquivos

Criar:

```text
db/migrate/20261125100000_create_autonomia_acessos_da_seguradora.rb
db/migrate/20261125100100_create_autonomia_cotacoes_de_viagem.rb
app/models/autonomia/agents/acesso_da_seguradora.rb
app/models/autonomia/agents/cotacao_de_viagem.rb
app/models/autonomia/agents/contratado.rb                       # concern do Agent: contratado?, marca, travas
app/services/autonomia/agents/contratados.rb                    # catálogo (módulo)
app/services/autonomia/agents/contratados/instrucao.rb          # render por turno
app/services/autonomia/agents/contratados/contratar.rb
app/services/autonomia/agents/contratados/dados_da_corretora.rb # editar os 3 campos
app/services/autonomia/agents/contratados/conferir_acesso.rb
app/services/autonomia/agents/contratados/base.rb               # semear a base oficial
app/services/autonomia/agents/contratados/seguro_viagem_universal/base/condicoes_gerais.md
app/services/autonomia/agents/contratados/seguro_viagem_universal/base/folheto_de_produtos.md
app/services/autonomia/seguradoras/universal/cliente.rb
app/services/autonomia/seguradoras/universal/destinos.rb
app/services/autonomia/agents/tools/native/cotar_seguro_viagem.rb
app/services/autonomia/agents/tools/native/detalhes_da_cotacao.rb
app/services/autonomia/agents/tools/native/gerar_proposta_seguro_viagem.rb
app/services/autonomia/agents/tools/native/seguro_viagem/pedido.rb
app/services/autonomia/agents/tools/native/seguro_viagem/planos.rb
app/services/autonomia/agents/tools/native/seguro_viagem/faixas.rb
app/services/autonomia/agents/tools/native/seguro_viagem/viajantes.rb
app/services/autonomia/agents/tools/native/seguro_viagem/compra.rb
app/services/autonomia/agents/tools/native/seguro_viagem/endereco_do_cep.rb
app/services/autonomia/agents/tools/native/seguro_viagem/falhas.rb
app/services/autonomia/agents/tools/native/seguro_viagem/comparativo_pdf.rb
app/services/autonomia/agents/tools/native/seguro_viagem/entrega_do_comparativo.rb
app/jobs/autonomia/agents/contratados/semear_base_job.rb
app/jobs/autonomia/agents/contratados/base_em_dia_job.rb
app/controllers/api/v1/accounts/autonomia/contratados_controller.rb
app/controllers/api/v1/accounts/autonomia/agents/contratado_controller.rb
app/controllers/api/v1/accounts/autonomia/agents/acesso_da_seguradora_controller.rb
spec/fixtures/universal/{setup,setup_so_cotacao,destinos,cotacao,compras_ok,compras_400}.json
app/javascript/dashboard/api/autonomia/contratados.js
app/javascript/dashboard/routes/dashboard/autonomia/agentes/composables/useContratados.js
app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/ProntosParaContratar.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/ContratadoCartao.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/ContratadoModeloPage.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/DadosDaCorretoraForm.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AcessoDaSeguradoraForm.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/GavetaDoContratado.vue
app/javascript/dashboard/routes/dashboard/autonomia/agentes/stories/Contratado.story.vue
```

Modificar (linhas lidas em 24/11, no HEAD `a390af7dce`):

```text
app/models/autonomia/agents/agent.rb                 63 (include), 217-219, 240-242, 249-254
app/controllers/api/v1/accounts/autonomia/agents_controller.rb      203 (RESERVED_CONFIG_KEYS)
app/controllers/api/v1/accounts/autonomia/agents/sources_controller.rb   2-3, 9, 32, 41
app/controllers/api/v1/accounts/autonomia/agents/tools_controller.rb     83-87
app/services/autonomia/ferramentas_prontas/incluir.rb                     27, 49-53
app/services/autonomia/agents/operate/inbox_connector.rb                  59-67
app/services/autonomia/agents/tools/registry.rb                           10-34
app/services/autonomia/exclusao_da_conta.rb                               antes da 139
app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder           31
config/routes.rb                                                          713-777 (bloco autonomia)
config/features.yml                                                       fim do arquivo
config/schedule.yml                                                       depois da 297
config/locales/en.yml, config/locales/pt_BR.yml                          autonomia.*
app/javascript/dashboard/featureFlags.js
app/javascript/dashboard/i18n/locale/{en,pt_BR}/agents.json
app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js   perto da 172
app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgenteEscolherPage.vue   65-231
app/javascript/dashboard/routes/dashboard/autonomia/agentes/utils/pagina.js                37-90
lib/operator_guide/porques.md, lib/operator_guide/automacao-recursos.yml (595-625)
spec/services/autonomia/insurance/receita/sem_texto_fixo_ao_cliente_spec.rb   PONTOS (19+)
```

---

## Interfaces que vêm do PR 1 (parâmetro deste plano)

O PR 1 (paridade da conversa, plano `2026-11-24-paridade-da-conversa.md`) cria opções por agente no `config`. Este PR
só as **liga** no `Contratar`. Nomes fixados pelo plano do PR 1 (`ParidadeDaConversa`); P6 (data e hora do turno) vale
para todos os agentes no PR 1 e não tem chave:

```ruby
# app/services/autonomia/agents/contratados.rb
CONVERSA_DO_PR1 = {
  'conversa_espera_a_fala' => true,   # P1: espera a fala anterior e junta a rajada
  'conversa_em_fila' => true,         # P2: fila atrás do turno em curso
  'conversa_entrega_inteira' => true, # P3: entrega não é cortada depois do 1º pedaço (exige P2)
  'conversa_ritmo_do_canal' => true   # P5: pausa pós-envio e "digitando" por canal
}.freeze
```

Já existem hoje e entram junto: `'humanize_delivery' => true` (quebra e cadência) e `'voice_reply' => true` (P7; a
regra "sem áudio quando a resposta tem link" é do PR 1). **Pré-condição deste PR: PR 1 mesclado.** Se o PR 2 precisar
abrir antes, a constante entra vazia e a Tarefa 20 tem um teste pendente nomeado `liga as opções de conversa do PR 1`.

---

## Tarefas

### Tarefa 0 — Insumos reais da Universal (gate de dados)

Depende de resposta do Rodrigo: **qual login da Universal usar no teste** (desenho §11, pergunta aberta).

- [ ] Com o login de teste, chamar só leitura, fora do repositório, num script no scratchpad (nunca commitado):
  `GET /v1/Emissor/Setup`, `GET /v1/destinos`, `POST /v1/Cotacao` com `{destinos:['PT'], passageiros:[{nome:'Viajante 1',
  dataNascimento:'1981-08-02'}], dataSaida:'2027-02-02', dataRetorno:'2027-02-06', tipoViagem:1, tipoTarifa:<do Setup>,
  produtoAvulso:false, cupom:'', classificacoes:[1]}`. Cotar não tem custo nem efeito. **Não chamar `/v1/Compras`.**
- [ ] Anotar os `idBeneficio` de "Despesas médicas e hospitalares", "Bagagem" (extravio) e "Cancelamento" — eles viram
  as constantes `ID_DMH`, `ID_BAGAGEM`, `ID_CANCELAMENTO` da Tarefa 13. **Já conhecidos numa cotação nacional real
  (24/11, `destinos: ['BR']` aceito):** `2898` "Despesas Médicas e Hospitalares (por evento)", `2595` "Perda de
  Bagagem", `2601` "Cancelamento de viagem - plus reason". A cotação internacional (`PT`) desta tarefa confirma se os
  ids internacionais são os mesmos; se forem outros, as constantes viram listas (`IDS_DMH = [2898, …]`).
  Nota: a mesma cotação real foi aceita com `tipoTarifa: 0` e devolveu `mostrarTarifaAcordo: true`; manter a regra do
  Setup (1/2) e conferir aqui que `2` funciona para o login de teste.
- [ ] Gravar as fixtures em `spec/fixtures/universal/` **anonimizadas**: `idCotacao` trocado por `'COT-TESTE-1'`,
  `fkEmpresa`/`idEmissor` por `1`, nenhum nome, CPF, e-mail ou login. Reduzir `cotacao.json` a 3 produtos (um sem
  despesas médicas, para o filtro) e manter os campos internos (`comissao`, `markup`, `rank`, ...) com valores
  fictícios, porque o teste prova que eles somem. `setup_so_cotacao.json` é cópia de `setup.json` com `soCotacao: true`.
  `compras_ok.json` = `{"codigoCarrinho": 987654, "codigoCotacao": "COT-TESTE-1", "urlVoucher":
  "https://pagamento.universal-assistance.com/?IdCarrinho=987654", "valorBrutoBrl": 312.45}` (forma da coleção, valores
  inventados). `compras_400.json` = `{"status": 400, "message": "Valor enviado no cartão é incompatível com a tarifa do produto"}`.
- [ ] Commit: `test(seguro-viagem): respostas gravadas da Universal, anonimizadas`.

### Tarefa 1 — Material oficial em texto (base de conhecimento)

**Arquivos.** Criar `app/services/autonomia/agents/contratados/seguro_viagem_universal/base/condicoes_gerais.md` e
`.../base/folheto_de_produtos.md`.

Fontes: as condições gerais vigentes (processo SUSEP 15414.644662/2023-04, o link que está na instrução, seção 4.1) e
o folheto comparativo de produtos (202605). As cópias baixadas na etapa 1 estão no scratchpad desta sessão
(`.../scratchpad/universal/postman/cc-15414.644662_2023-04.pdf` e `202605-ProdutosFolheto_comparativo_Completo.pdf`);
se o scratchpad tiver sido limpo, baixar de novo do site oficial da Universal. Os PDFs **não** entram no repositório.

- [ ] Extrair com `pdftotext -layout <pdf> <saida.txt>` para o scratchpad.
- [ ] Curar à mão em Markdown: um bloco por assunto, cada bloco começando por uma linha `### <assunto>` (é o separador
  do fatiamento da Tarefa 20). Texto oficial apenas: tirar cabeçalho e rodapé de página, juntar linhas quebradas, manter
  números, limites e prazos exatamente como estão. Nada inventado nem resumido.
- [ ] Primeira linha de cada arquivo: `<!-- fonte: <título oficial>, <versão/data>, <URL oficial> -->`.
- [ ] Conferir: nenhum bloco maior que 6.000 caracteres (dividir em subassuntos); nenhum nome de cliente.
- [ ] Commit: `docs(seguro-viagem): base oficial da Universal em texto (condições gerais e folheto)`.

### Tarefa 2 — Migrations

**Arquivos.** Criar as duas migrations do mapa.

**Interfaces.** Produz as tabelas `autonomia_acessos_da_seguradora` e `autonomia_cotacoes_de_viagem`.

- [ ] Spec que falha: `spec/db/autonomia_seguro_viagem_tabelas_spec.rb`

```ruby
it 'acesso: um por agente, credenciais em text' do
  cols = ActiveRecord::Base.connection.columns('autonomia_acessos_da_seguradora').index_by(&:name)
  expect(cols.keys).to include('account_id', 'autonomia_agent_id', 'seguradora', 'login', 'senha', 'login_dica',
                               'estado', 'conferido_em', 'motivo', 'capacidades')
  expect(cols['login'].type).to eq(:text)
  expect(cols['senha'].type).to eq(:text)
  indice = ActiveRecord::Base.connection.indexes('autonomia_acessos_da_seguradora')
                             .find { |i| i.columns == ['autonomia_agent_id'] }
  expect(indice.unique).to be(true)
end

it 'cotação: jsonb para pedido, planos e proposta' do
  cols = ActiveRecord::Base.connection.columns('autonomia_cotacoes_de_viagem').index_by(&:name)
  expect(cols.slice('pedido', 'planos', 'proposta').values.map(&:sql_type)).to all(eq('jsonb'))
  expect(cols['conversation_id'].null).to be(false)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar `CreateAutonomiaAcessosDaSeguradora` (`ActiveRecord::Migration[7.2]`):
  `account_id` bigint not null FK accounts **sem cascata**; `autonomia_agent_id` bigint not null FK `autonomia_agents`
  `on_delete: :cascade`, índice único; `seguradora` string not null default `'universal'`; `login` text; `senha` text;
  `login_dica` string; `estado` string not null default `'nao_conferido'`; `conferido_em` datetime; `motivo` string;
  `capacidades` jsonb not null default `{}`; timestamps.
- [ ] Implementar `CreateAutonomiaCotacoesDeViagem`: `account_id` FK sem cascata; `conversation_id` not null FK
  `conversations` `on_delete: :cascade`; `autonomia_agent_id` not null FK `autonomia_agents` `on_delete: :cascade`;
  `id_cotacao` string not null; `pedido` jsonb not null default `{}`; `planos` jsonb not null default `[]`;
  `proposta` jsonb (nulo); timestamps; índice `[:conversation_id, :id]`.
  Comentário no topo explicando: tabelas novas e vazias, nenhuma trava em tabela existente, nenhum job enfileirado.
- [ ] `bundle exec rails db:migrate` local **não** (sem banco de teste local); gerar `db/schema.rb` pela CI não
  existe, então escrever o trecho do `schema.rb` à mão, na ordem alfabética das tabelas, e conferir no diff.
- [ ] Commits: `test(seguro-viagem): tabelas de acesso e cotação` e `feat(seguro-viagem): tabelas de acesso e cotação`.

### Tarefa 3 — Model `AcessoDaSeguradora`

**Arquivos.** Criar `app/models/autonomia/agents/acesso_da_seguradora.rb`.

**Interfaces.**
- Produz: `Autonomia::Agents::AcessoDaSeguradora` com `ESTADOS = %w[nao_conferido ok recusado].freeze`,
  `SEGURADORAS = %w[universal].freeze`, `belongs_to :account`, `belongs_to :agent` (`foreign_key: :autonomia_agent_id`),
  `encrypts :login`, `encrypts :senha`, `#ok?`, `#so_cotacao?` (lê `capacidades['soCotacao'] == true`),
  `#tarifa_acordo?`, `#payload_publico -> Hash` (`seguradora, login_dica, estado, motivo, conferido_em, so_cotacao`).
- Consome: `Chatwoot.encryption_configured?` (mesma guarda de `Insurance::Connection#credentials_require_encryption`).

- [ ] Spec que falha: `spec/models/autonomia/agents/acesso_da_seguradora_spec.rb`

```ruby
it 'guarda login e senha cifrados' do
  acesso = described_class.create!(account: account, agent: agente, login: 'corretor.teste', senha: 's3nha-teste')
  cru = ActiveRecord::Base.connection.select_one("SELECT login, senha FROM autonomia_acessos_da_seguradora WHERE id = #{acesso.id}")
  expect(cru['login']).not_to include('corretor.teste')
  expect(cru['senha']).not_to include('s3nha-teste')
end

it 'dica do login: dois primeiros, três pontos, dois últimos' do
  expect(described_class.new(login: 'corretor.teste').tap(&:valid?).login_dica).to eq('co•••te')
  expect(described_class.new(login: 'abcd').tap(&:valid?).login_dica).to eq('•••')
end

it 'payload público nunca tem login nem senha' do
  payload = acesso.payload_publico
  expect(payload.keys).to contain_exactly(:seguradora, :login_dica, :estado, :motivo, :conferido_em, :so_cotacao)
  expect(payload.to_json).not_to include('s3nha-teste', 'corretor.teste')
end

it 'recusa gravar sem cofre configurado' do
  allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
  expect { described_class.create!(account: account, agent: agente, login: 'x1', senha: 'y1') }
    .to raise_error(ActiveRecord::RecordInvalid)
end

it 'um por agente' do
  described_class.create!(account: account, agent: agente, login: 'a1b2c3', senha: 'x')
  expect { described_class.create!(account: account, agent: agente, login: 'd4e5f6', senha: 'y') }
    .to raise_error(ActiveRecord::RecordInvalid)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. `before_validation :derivar_login_dica` (se `login` mudou): `login.length > 4 ?
  "#{login.first(2)}•••#{login.last(2)}" : '•••'`. Validações: `estado` em `ESTADOS`, `seguradora` em `SEGURADORAS`,
  `autonomia_agent_id` único, `validate :credenciais_exigem_cofre`. `motivo` só aceita códigos de
  `Seguradoras::Universal::Cliente::CODIGOS` (Tarefa 10) ou nil.
- [ ] Commits: `test(seguro-viagem): acesso cifrado por agente` / `feat(seguro-viagem): acesso cifrado por agente`.

### Tarefa 4 — Model `CotacaoDeViagem`

**Arquivos.** Criar `app/models/autonomia/agents/cotacao_de_viagem.rb`.

**Interfaces.** Produz `Autonomia::Agents::CotacaoDeViagem` (`belongs_to :account, :conversation, :agent`),
`.ultima_da_conversa(conversation_id) -> CotacaoDeViagem|nil` (maior `id`), `#plano(codigo) -> Hash|nil`,
`#do_dia?(fuso) -> Boolean` (`created_at.in_time_zone(fuso).to_date == fuso.today`), `#idades -> Array<Integer>`
(lê `pedido['idades']`).

- [ ] Spec que falha: `spec/models/autonomia/agents/cotacao_de_viagem_spec.rb`

```ruby
it 'a última da conversa é a de maior id' do
  a = criar_cotacao(planos: [{ 'codigo' => 'P1' }])
  b = criar_cotacao(planos: [{ 'codigo' => 'P1' }])
  expect(described_class.ultima_da_conversa(conversa.id)).to eq(b)
end

it 'plano pelo código; código desconhecido é nil' do
  c = criar_cotacao(planos: [{ 'codigo' => 'P1', 'preco_total' => '312.45' }])
  expect(c.plano('P1')['preco_total']).to eq('312.45')
  expect(c.plano('P9')).to be_nil
end

it 'do dia no fuso da conta' do
  fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  travel_to(Time.utc(2026, 11, 25, 2, 0)) do            # 24/11 23h em São Paulo
    c = criar_cotacao
    expect(c.do_dia?(fuso)).to be(true)
  end
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar (sem callbacks).
- [ ] Commits: `test(seguro-viagem): cotação guardada` / `feat(seguro-viagem): cotação guardada`.

### Tarefa 5 — Exclusão da conta

**Arquivos.** Modificar `app/services/autonomia/exclusao_da_conta.rb` (antes da linha 139,
`['Autonomia::Agents::AgentInbox', :por_conta]`).

- [ ] Spec: nenhuma nova. A guarda existente `spec/services/autonomia/exclusao_da_conta_spec.rb` já falha com as
  tabelas da Tarefa 2 (é o teste vermelho desta tarefa).
- [ ] Implementar: duas linhas, com comentário de uma linha ("cotação e acesso apontam para o agente; ninguém aponta
  para eles"): `['Autonomia::Agents::CotacaoDeViagem', :por_conta]`, `['Autonomia::Agents::AcessoDaSeguradora', :por_conta]`.
- [ ] Commit: `fix(seguro-viagem): exclusão da conta apaga cotações e acessos`.

### Tarefa 6 — Catálogo e instrução por turno

**Arquivos.** Criar `app/services/autonomia/agents/contratados.rb` e `contratados/instrucao.rb`.

**Interfaces.**
- Produz:
  - `Autonomia::Agents::Contratados::MARCA = 'contratado'`.
  - `Autonomia::Agents::Contratados::MODELOS -> Hash<String, Hash>` com uma entrada `'seguro_viagem_universal' => {
    flag: 'agente_seguro_viagem_universal', agent_type: 'sdr', pasta: <Pathname>, arquivo: 'instrucao.md',
    ferramentas_nativas: %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem],
    prontas: %w[cep cpf], seguradora: 'universal', conversa: CONVERSA_DO_PR1.merge('humanize_delivery' => true,
    'voice_reply' => true) }`.
  - `.modelo(agent) -> Hash|nil` (lê `agent.config['contratado']['modelo']`), `.disponiveis(account) -> Array<String>`,
    `.disponivel?(account, chave) -> Boolean` (flag do modelo **e** `FerramentasProntas.ligada?` **e**
    `account.feature_enabled?(FerramentasProntas::FLAG_CONSULTAS)` **e** `Chatwoot.encryption_configured?`).
  - `.ferramentas(agent) -> Array<String>|nil` (nil para quem não é contratado).
  - `Contratados::DadosIncompletos < Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas` (subclasse, para
    as portas que já tratam a da Lia tratarem esta sem mudança).
  - `Contratados::Instrucao::VARIAVEIS = { '$nomeAgente' => 'nome_agente', '$nomeCorretora' => 'nome_corretora',
    '$sobreCorretora' => 'sobre_corretora', '$dataDeHoje' => :hoje }`, `MAX_NOME = 120`, `MAX_SOBRE = 1_000`.
  - `Contratados::Instrucao.renderizar(agent, hoje: nil) -> String|nil`; `.substituir(texto, valores) -> String`;
    `.data_por_extenso(date) -> String`; `.marcador_dentro?(valor) -> Boolean`.

Algoritmo de `substituir` (sem regex, uma passada, o valor inserido nunca é relido):

```ruby
# percorre com String#index('$', pos); em cada '$', procura o marcador com texto[pos, m.length] == m;
# achou: anexa o valor e pula m.length; não achou: anexa '$' e anda 1.
```

`data_por_extenso(Date.new(2026, 11, 24))` → `'24/11/2026 (terça-feira)'`, com
`DIAS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado]` indexado por `wday`.
`hoje` padrão: `Autonomia::FerramentasProntas.fuso_da_conta(agent.account).today`.

- [ ] Spec que falha: `spec/services/autonomia/agents/contratados/instrucao_spec.rb`

```ruby
let(:marca) do
  { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
    'sobre_corretora' => 'Corretora de seguros desde 2010.' }
end

it 'troca as quatro variáveis e não deixa marcador' do
  texto = described_class.renderizar(agente(marca), hoje: Date.new(2026, 11, 24))
  expect(texto).to start_with('# Instrução de Bia: Seguro Viagem Universal Assistance')
  expect(texto).to include('Você é Bia, da Corretora Exemplo, corretora de seguros.')
  expect(texto).to include('Sobre a corretora: Corretora de seguros desde 2010.')
  expect(texto).to include('Hoje é 24/11/2026 (terça-feira) (no fuso da conta).')
  %w[$nomeAgente $nomeCorretora $sobreCorretora $dataDeHoje].each { |m| expect(texto).not_to include(m) }
end

it 'valor com marcador não é relido (uma passada)' do
  expect(described_class.substituir('$nomeAgente e $nomeCorretora', 'nome_agente' => '$nomeCorretora',
                                    'nome_corretora' => 'X')).to eq('$nomeCorretora e X')
end

it 'lê o arquivo a cada chamada (o deploy seguinte vale)' do
  allow(File).to receive(:read).and_call_original
  2.times { described_class.renderizar(agente(marca), hoje: Date.new(2026, 11, 24)) }
  expect(File).to have_received(:read).with(satisfy { |p| p.to_s.end_with?('seguro_viagem_universal/instrucao.md') }).twice
end

it 'nil para quem não é contratado' do
  expect(described_class.renderizar(agente(nil))).to be_nil
end

it 'marca presente e incompleta para com o nome do campo' do
  expect { described_class.renderizar(agente(marca.except('nome_corretora'))) }
    .to raise_error(Autonomia::Agents::Contratados::DadosIncompletos, 'nome_corretora')
end

it 'sobre vazio vale (a instrução trata o texto vazio)' do
  expect(described_class.renderizar(agente(marca.merge('sobre_corretora' => '')), hoje: Date.new(2026, 11, 24)))
    .to include('Sobre a corretora: ')
end

it 'cabe no teto da coluna com os maiores valores' do
  grande = marca.merge('nome_agente' => 'a' * 120, 'nome_corretora' => 'b' * 120, 'sobre_corretora' => 'c' * 1_000)
  expect(described_class.renderizar(agente(grande), hoje: Date.new(2026, 11, 24)).length)
    .to be <= Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH
end
```

E `spec/services/autonomia/agents/contratados_spec.rb`:

```ruby
it 'disponível só com a flag do modelo, as duas das prontas e o cofre' do
  account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                           'agente_ferramentas_prontas_consultas')
  expect(described_class.disponiveis(account)).to eq(['seguro_viagem_universal'])
  account.disable_features!('agente_ferramentas_prontas_consultas')
  expect(described_class.disponiveis(account)).to eq([])
end

it 'os slugs do catálogo existem no Registry' do
  slugs = described_class::MODELOS.values.flat_map { |m| m[:ferramentas_nativas] }
  expect(slugs - Autonomia::Agents::Tools::Registry.slugs).to eq([])
end
```

(O segundo exemplo fica pendente até a Tarefa 19 registrar as ferramentas: marcar com `pending` e tirar na 19.)

- [ ] Rodar: não rodar localmente; roda na CI. `bundle exec rubocop app/services/autonomia/agents/contratados*`.
- [ ] Implementar. `renderizar`: retorna nil se `MARCA` ausente; confere `nome_agente` e `nome_corretora` presentes
  (`DadosIncompletos, campo`), `sobre_corretora` pode ser vazio; lê `pasta.join(arquivo).read` a cada chamada.
- [ ] Commits: `test(seguro-viagem): catálogo e instrução por turno` / `feat(seguro-viagem): catálogo e instrução por turno`.

### Tarefa 7 — O `Agent` contratado (e a Lia inalterada)

**Arquivos.** Criar `app/models/autonomia/agents/contratado.rb`; modificar `app/models/autonomia/agents/agent.rb`
(63: `include Autonomia::Agents::Contratado` logo depois de `MarcaDoModeloPronto`; 217-219; 240-242; 249-254).

**Interfaces.**
- Produz (concern `Autonomia::Agents::Contratado`): `#contratado? -> Boolean` (`config.to_h[MARCA].is_a?(Hash) &&
  Contratados::MODELOS.key?(marca['modelo'])`), `#marca_do_contratado -> Hash|nil`, `has_one :acesso_da_seguradora`
  (`foreign_key: :autonomia_agent_id, dependent: :destroy`), `validate :contratado_fica_no_tipo` (persistido com marca:
  `agent_type` não muda), `validate :atender_exige_acesso_conferido, on: %i[update ativacao], if: :passa_a_atender?`
  (erro `I18n.t('autonomia.contratados.acesso_pendente')`), `before_update :manter_marca_salva` (o mesmo desenho de
  `MarcaDoModeloPronto`: se o save muda o `config` sem mexer na marca, relê a marca sob a trava e mantém a salva).
- Muda em `Agent`:
  - `instrucao_mantida?` → `agent_type == 'insurance_quote' || contratado?`
  - `instrucao_do_sistema` → `Contratados::Instrucao.renderizar(self) || QuoteAgent::Builder.instrucao_do_principal(self) || instruction`
  - `ferramentas_nativas` → `Contratados.ferramentas(self) || <expressão atual inteira, sem mudança>`

- [ ] Spec que falha 1: `spec/models/autonomia/agents/contratado_spec.rb`

```ruby
it 'é contratado só com a marca de um modelo do catálogo' do
  expect(build_agent(config: { 'contratado' => marca }).contratado?).to be(true)
  expect(build_agent(config: { 'contratado' => marca.merge('modelo' => 'outro') }).contratado?).to be(false)
  expect(build_agent(config: {}).contratado?).to be(false)
end

it 'instrução mantida: recusa refresh, rollback, Construtor e modo manual' do
  agente = criar_contratado
  expect { agente.refresh_instruction!('x', expected_instruction: agente.instruction) }
    .to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
  expect { agente.apply_builder_config!('t', { instruction: 'x' }) }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
  agente.mode = :manual
  expect(agente).not_to be_valid
end

it 'o prompt é o arquivo renderizado, não a coluna' do
  agente = criar_contratado
  agente.update_columns(instruction: 'velha')
  expect(agente.instrucao_do_sistema).to include('Você é Bia, da Corretora Exemplo')
end

it 'ferramentas fixas do catálogo, mesmo com native_tool_slugs gravado' do
  agente = criar_contratado(config_extra: { 'native_tool_slugs' => %w[agendar_reuniao] })
  expect(agente.ferramentas_nativas).to eq(%w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem])
end

it 'o tipo não muda depois de contratado' do
  agente = criar_contratado
  agente.agent_type = 'custom'
  expect(agente).not_to be_valid
end

it 'não passa a atender sem acesso ok' do
  agente = criar_contratado
  agente.assign_attributes(status: :active, enabled: true)
  expect(agente.valid?(:ativacao)).to be(false)
  agente.create_acesso_da_seguradora!(account: agente.account, login: 'corretor.teste', senha: 'x', estado: 'ok')
  expect(agente.errors.full_messages.join).not_to include(I18n.t('autonomia.contratados.acesso_pendente')) if agente.valid?(:ativacao)
end

it 'save comum com cópia velha não desfaz a edição dos três campos' do
  agente = criar_contratado
  velho = Autonomia::Agents::Agent.find(agente.id)
  agente.update!(config: agente.config.merge('contratado' => marca.merge('nome_corretora' => 'Nova')))
  velho.update!(config: velho.config.merge('greeting_extra' => 'x'))
  expect(agente.reload.config['contratado']['nome_corretora']).to eq('Nova')
end
```

- [ ] Spec que falha 2 (R1): `spec/models/autonomia/agents/agent_lia_inalterada_spec.rb`

```ruby
let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora Exemplo').call }

it 'instrução da Lia é exatamente a do Builder' do
  expect(lia.instrucao_do_sistema).to eq(Autonomia::Insurance::QuoteAgent::Builder.instrucao_do_principal(lia))
end

it 'ferramentas da Lia são exatamente as do Builder' do
  expect(lia.ferramentas_nativas).to eq(Autonomia::Insurance::QuoteAgent::Builder.ferramentas_mantidas(lia))
end

it 'predicados e rodadas da Lia não mudam' do
  expect(lia.instrucao_mantida?).to be(true)
  expect(lia.contratado?).to be(false)
  expect(Autonomia::Agents::RodadasDoTurno.para(lia)).to eq(Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia))
end

it 'agente comum continua sem instrução mantida' do
  comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')
  expect(comum.instrucao_mantida?).to be(false)
  expect(comum.instrucao_do_sistema).to eq(comum.instruction)
end
```

- [ ] Rodar: não rodar localmente; roda na CI. `bundle exec rubocop app/models/autonomia/agents/agent.rb app/models/autonomia/agents/contratado.rb`.
- [ ] Implementar. O comentário de `instrucao_mantida?` ganha uma linha: "ou o agente contratado do catálogo (#3211)".
- [ ] Commits: `test(agentes): agente contratado e a Lia inalterada` / `feat(agentes): agente contratado com instrução mantida`.

### Tarefa 8 — Leitores de `instrucao_mantida?` que não são escritores (auditoria com teste)

Estender o predicado também muda estes leitores (lidos no código em 24/11). A decisão de cada um fica escrita no spec.

| Leitor | Efeito no contratado | Decisão deste plano |
|---|---|---|
| `agents_controller.rb:170-171`, `build_threads_controller.rb:158,208`, `playground_controller.rb:48` | recusa editar instrução, modo e tipo; Construtor recusado | desejado |
| `sources_controller.rb:60,146` (foto, leitura Fase 2) | não lê foto nem roda a leitura da Fase 2 | desejado (base é nossa) |
| `base_de_seguros.rb:25`, `material.rb:11`, `knowledge/resumo_por_secao.rb:84`, `knowledge/fotos_da_criacao.rb:31`, `knowledge/processors/pdf.rb:78,87`, `knowledge/instruction_refresher.rb:72` | sem troca de base de seguros, sem conferência de material, sem refresh da instrução | desejado |
| `crm/ai/fatos_da_conversa.rb:122` (F1: fala do agente protegido fica fora) | a IA do CRM não conta a fala do contratado como "fala do nosso robô" | **mantido igual à Lia; confirmar com o Rodrigo** |
| `crm/ai/handoff_executor.rb:110` (promessa do robô) | a IA do CRM não cumpre "alguém vai continuar" dito pelo contratado; a passagem vem do campo de passagem do próprio agente | **mantido igual à Lia; confirmar com o Rodrigo** |

- [ ] Spec que falha: `spec/services/autonomia/agents/contratados/leitores_de_instrucao_mantida_spec.rb`, um exemplo por
  linha da tabela, afirmando o efeito com um contratado criado pelo `Contratar` (Tarefa 20) ou à mão com a marca.
  Exemplo da linha F1:

```ruby
it 'F1: a fala do contratado é tratada como a do agente protegido' do
  expect(Crm::Ai::FatosDaConversa.send(:agente_protegido?, account.id, vinculo.agent_bot_id)).to be(true)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar: nada de código (é só prova). Se o Rodrigo decidir o contrário nas duas linhas marcadas, a troca é
  um predicado novo `Agent#agente_protegido_do_crm?` (só Lia) usado nesses dois leitores, com o exemplo invertido.
- [ ] Commit: `test(agentes): o que muda para o contratado em cada leitor da instrução mantida`.

### Tarefa 9 — Travas da API: marca reservada, ferramentas e base

**Arquivos.** Modificar `agents_controller.rb:203`, `tools_controller.rb:83-87`, `ferramentas_prontas/incluir.rb:27,49-53`,
`agents/sources_controller.rb:2-3`; `config/locales/{en,pt_BR}.yml`.

**Interfaces.**
- `RESERVED_CONFIG_KEYS` ganha `Autonomia::Agents::Contratados::MARCA`.
- `ToolsController#refuse_quote_agent` passa a recusar também `@agent.contratado?` (mesma mensagem nova
  `autonomia.agents.ferramenta_no_contratado`); SuperAdmin continua passando.
- `FerramentasProntas::Incluir#initialize(..., pelo_contratar: false)`; `conferir!` levanta `Recusado,
  'agente_contratado'` quando `@agent.contratado? && !@pelo_contratar`.
- `SourcesController`: `before_action :recusar_base_do_contratado, only: %i[create destroy resync]` → 422
  `I18n.t('autonomia.agents.base_do_contratado')`.

- [ ] Spec que falha: `spec/requests/api/v1/accounts/autonomia/contratado_travas_spec.rb`

```ruby
it 'PATCH não grava nem troca a marca' do
  patch agent_url, params: { agent: { config: { contratado: { modelo: 'seguro_viagem_universal', nome_corretora: 'Forjada' } } } },
                   headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:ok)
  expect(agente.reload.config['contratado']['nome_corretora']).to eq('Corretora Exemplo')
end

it 'POST create não nasce contratado pela API genérica' do
  post agents_url, params: { agent: { name: 'X', agent_type: 'sdr', config: { contratado: marca } } },
                   headers: admin.create_new_auth_token, as: :json
  expect(Autonomia::Agents::Agent.last.contratado?).to be(false)
end

it 'PATCH com instruction recusa com instrucao_mantida' do
  patch agent_url, params: { agent: { instruction: 'x' } }, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:unprocessable_entity)
end

it 'ferramentas: dono não cria nem apaga' do
  post tools_url, params: { tool: { name: 'x' } }, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:unprocessable_entity)
end

it 'base: dono não envia, apaga nem relê material' do
  post sources_url, params: { source: { source_type: 'text', content: 'x' } }, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:unprocessable_entity)
  expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.base_do_contratado'))
end
```

E em `spec/services/autonomia/ferramentas_prontas/incluir_contratado_spec.rb`: `Incluir.new(..., agent: contratado,
fonte: 'cep').call` levanta `Recusado` com `motivo == 'agente_contratado'`; com `pelo_contratar: true` cria a ferramenta.

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. i18n en + pt_BR: `autonomia.agents.ferramenta_no_contratado`, `autonomia.agents.base_do_contratado`.
- [ ] Commits: `test(agentes): travas da API no contratado` / `feat(agentes): travas da API no contratado`.

### Tarefa 10 — Cliente HTTP da Universal

**Arquivos.** Criar `app/services/autonomia/seguradoras/universal/cliente.rb`.

**Interfaces.**
- Produz `Autonomia::Seguradoras::Universal::Cliente.new(login:, senha:)` com:
  `#setup -> Hash`, `#cotar(pedido) -> Hash`, `#comprar(pedido) -> Hash`, `#destinos -> Array<Hash>`.
- `BASE_URL = ENV.fetch('UNIVERSAL_API_BASE_URL', 'https://api-br.universal-assistance.com')` (lido em
  `base_url`, não no boot); `ABERTURA = 5`; `LEITURA = { setup: 15, destinos: 15, cotar: 40, comprar: 40 }`.
- `CODIGOS = %w[acesso_recusado pedido_invalido indisponivel].freeze`;
  `class Erro < StandardError; attr_reader :codigo, :mensagem_da_seguradora; end` (mensagem do `super` é só o código).
- Mapa: 401/403 → `acesso_recusado`; 400/404/409/422 → `pedido_invalido` com `mensagem_da_seguradora =
  corpo['message'].to_s.first(200)` quando o corpo é JSON; 5xx, `Net::OpenTimeout`, `Net::ReadTimeout`,
  `SocketError`, `Errno::ECONNREFUSED`, JSON inválido em 2xx → `indisponivel`.
- Cabeçalhos: `Login`, `Senha`, `Content-Type: application/json`, `Accept: application/json`.
- Log: uma linha por chamada, `"[autonomia][universal] chamada=#{nome} status=#{status} ms=#{ms}"`. **Nunca**
  cabeçalho, corpo, login, URL com query, nem `e.message`.

- [ ] Spec que falha: `spec/services/autonomia/seguradoras/universal/cliente_spec.rb` (WebMock + fixtures da Tarefa 0)

```ruby
let(:base) { 'https://api-br.universal-assistance.com' }
let(:cliente) { described_class.new(login: 'corretor.teste', senha: 's3nha-teste') }

it 'manda Login e Senha nos cabeçalhos' do
  stub = stub_request(:get, "#{base}/v1/Emissor/Setup")
         .with(headers: { 'Login' => 'corretor.teste', 'Senha' => 's3nha-teste', 'Accept' => 'application/json' })
         .to_return(status: 200, body: file_fixture('../universal/setup.json').read)
  cliente.setup
  expect(stub).to have_been_requested
end

it '401 vira acesso_recusado' do
  stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401, body: '')
  expect { cliente.setup }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('acesso_recusado') }
end

it '400 vira pedido_invalido com a mensagem curta da seguradora' do
  stub_request(:post, "#{base}/v1/Compras").to_return(status: 400, body: file_fixture('../universal/compras_400.json').read)
  expect { cliente.comprar({}) }.to raise_error(described_class::Erro) { |e|
    expect(e.codigo).to eq('pedido_invalido')
    expect(e.mensagem_da_seguradora).to eq('Valor enviado no cartão é incompatível com a tarifa do produto')
  }
end

it 'timeout vira indisponivel' do
  stub_request(:post, "#{base}/v1/Cotacao").to_timeout
  expect { cliente.cotar({}) }.to raise_error(described_class::Erro) { |e| expect(e.codigo).to eq('indisponivel') }
end

it 'URL base pela ENV' do
  with_modified_env(UNIVERSAL_API_BASE_URL: 'https://universal.exemplo.test') do
    stub = stub_request(:get, 'https://universal.exemplo.test/v1/destinos').to_return(status: 200, body: '[]')
    cliente.destinos
    expect(stub).to have_been_requested
  end
end

it 'log sem credencial, sem corpo, sem dado pessoal (R2/R5)' do
  saida = StringIO.new
  allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(saida))
  stub_request(:post, "#{base}/v1/Compras").to_return(status: 400, body: file_fixture('../universal/compras_400.json').read)
  begin
    cliente.comprar('DadosTitular' => { 'Documento' => '52998224725', 'Nome' => 'Fulano' })
  rescue described_class::Erro
    nil
  end
  expect(saida.string).to include('chamada=comprar status=400')
  expect(saida.string).not_to include('corretor.teste', 's3nha-teste', '52998224725', 'Fulano', 'incompatível')
end
```

- [ ] Rodar: não rodar localmente; roda na CI. `bundle exec rubocop app/services/autonomia/seguradoras`.
- [ ] Implementar com `Net::HTTP` (modelo: `Autonomia::Insurance::Connector::Http#perform`), `use_ssl` pelo
  esquema da URL, `JSON.generate` no corpo, `JSON.parse` na resposta.
- [ ] Commits: `test(seguro-viagem): cliente da Universal` / `feat(seguro-viagem): cliente da Universal`.

### Tarefa 11 — Destinos em cache

**Arquivos.** Criar `app/services/autonomia/seguradoras/universal/destinos.rb`.

**Interfaces.** `Destinos.siglas(cliente) -> Set<String>|nil` (nil quando a Universal não respondeu: quem chama não
barra a cotação por isso). Cache `Rails.cache` chave `'autonomia:universal:destinos:v1'`, `expires_in: 1.day`, guarda
só `siglaPais` maiúsculas. `Destinos.validas?(siglas, cliente) -> [Boolean, Array<String> invalidas]`.

- [ ] Spec que falha: `spec/services/autonomia/seguradoras/universal/destinos_spec.rb`: com a fixture, `siglas` inclui
  `'PT'` e `'ES'`; segunda chamada não chama a API (`have_been_requested.once`); `validas?(%w[PT XX])` →
  `[false, ['XX']]`; API fora → `siglas` nil e `validas?` → `[true, []]`.
- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): destinos da Universal` / `feat(seguro-viagem): destinos da Universal`.

### Tarefa 12 — Conferir o acesso (Setup)

**Arquivos.** Criar `app/services/autonomia/agents/contratados/conferir_acesso.rb`.

**Interfaces.** `ConferirAcesso.new(agent:, login:, senha:).call -> AcessoDaSeguradora`: grava login e senha (upsert
no acesso do agente), chama `Cliente#setup`, grava `estado: 'ok'`, `conferido_em: Time.current`, `motivo: nil`,
`capacidades: setup.slice('soCotacao', 'emiteFaturado', 'emiteBoleto', 'tarifaAcordo')` (só booleanos). Erro
`acesso_recusado` → `estado: 'recusado', motivo: 'acesso_recusado'`; `indisponivel` → `estado: 'nao_conferido',
motivo: 'indisponivel'`. Nunca levanta `Cliente::Erro` para fora.

- [ ] Spec que falha: `spec/services/autonomia/agents/contratados/conferir_acesso_spec.rb`

```ruby
it 'Setup ok grava ok e as capacidades, só booleanos' do
  acesso = described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call
  expect(acesso.estado).to eq('ok')
  expect(acesso.capacidades.keys).to contain_exactly('soCotacao', 'emiteFaturado', 'emiteBoleto', 'tarifaAcordo')
  expect(acesso.capacidades.values).to all(be_in([true, false]))
end

it '401 grava recusado com o código' do
  stub_request(:get, "#{base}/v1/Emissor/Setup").to_return(status: 401)
  expect(described_class.new(agent: contratado, login: 'x1x1x', senha: 'y').call).to have_attributes(estado: 'recusado', motivo: 'acesso_recusado')
end

it 'trocar o login refaz a conferência e não cria segunda linha' do
  2.times { described_class.new(agent: contratado, login: 'corretor.teste', senha: 's3nha-teste').call }
  expect(Autonomia::Agents::AcessoDaSeguradora.where(autonomia_agent_id: contratado.id).count).to eq(1)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): conferir o acesso pelo Setup` / `feat(seguro-viagem): conferir o acesso pelo Setup`.

### Tarefa 13 — `cotar_seguro_viagem` (pedido, planos, ferramenta)

**Arquivos.** Criar `native/seguro_viagem/pedido.rb`, `native/seguro_viagem/planos.rb`, `native/cotar_seguro_viagem.rb`.

**Interfaces.**
- `SeguroViagem::Pedido.new(params, hoje:, tarifa_acordo:).conferir -> [Hash pedido_da_universal, nil] | [nil, Falta]`
  com `Falta = Data.define(:campo, :texto)`. Constantes: `IDADE_MAX = 120`, `TIPO_VIAGEM_UNICA = 1`,
  `TARIFA = { folheto: 1, acordo: 2 }`, `CLASSIFICACAO = { nil => 1, 'lazer' => 4, 'estudo' => 5, 'negocios' => 6,
  'gestante' => 7, 'cruzeiro' => 8 }`, `MOTIVOS = %w[lazer estudo negocios gestante cruzeiro]`.
  Regras: `destinos` array não vazio de 2 letras (`upcase`, `length == 2`, `all?` letra via `match?`-free:
  `sigla.each_char.all? { |c| ('A'..'Z').cover?(c) }`); datas por `Date.iso8601` (erro → Falta); `data_saida >= hoje`;
  `data_retorno >= data_saida`; `idades` array não vazio de inteiros 0..120; `motivo` nil ou em `MOTIVOS`.
  Data técnica de nascimento: `data_saida << (idade * 12 + 6)`.
  Pedido: `{ 'destinos' => [...], 'passageiros' => [{ 'nome' => "Viajante #{i + 1}", 'dataNascimento' => 'AAAA-MM-DD' }],
  'dataSaida', 'dataRetorno', 'tipoViagem' => 1, 'tipoTarifa' => tarifa_acordo ? 2 : 1, 'produtoAvulso' => false,
  'cupom' => '', 'classificacoes' => [CLASSIFICACAO.fetch(motivo)] }`.
- `SeguroViagem::Planos.de(resposta, idades:) -> Array<Hash>`: **lista branca** (nunca copia o produto cru).
  `ID_DMH`, `ID_BAGAGEM`, `ID_CANCELAMENTO` = valores da Tarefa 0. Cada plano: `codigo` (`"P#{n}"`, n a partir de 1, na
  ordem da Universal depois do filtro), `id_produto`, `id_produto_acordo`, `nome` (`descricao`), `descricao_adicional`,
  `preco_total` (string decimal de `tarifa.valor`), `valor_moeda`, `moeda` (`simboloMoeda`), `cambio`, `max_parcelas`,
  `idade_minima`, `idade_maxima`, `regra_cancelamento`, `faixas` (`tarifaIdade` → `[{de, ate, valor, valor_moeda}]`),
  `coberturas` (`[{id_beneficio, nome, descricao_completa, valor, moeda}]`, nome e descrição vindos de
  `resposta['beneficios']` pelo `idBeneficio`), `principais` (`{despesas_medicas, bagagem, cancelamento}` como
  `"#{moeda} #{valor}"` ou nil). Filtro: só produtos com cobertura `ID_DMH`; e fora os que têm uma idade fora de
  `idade_minima..idade_maxima`. `Planos.resumo(planos) -> Array<Hash>` com `codigo, nome, preco_total` formatado
  (`'R$ 1.480,25'` por `ActiveSupport::NumberHelper.number_to_currency(v, unit: 'R$ ', separator: ',', delimiter: '.')`),
  `max_parcelas`, `principais`.
- `Native::CotarSeguroViagem < Native::Base`: `slug 'cotar_seguro_viagem'`, `escreve? true`,
  `args_registraveis %w[destinos data_saida data_retorno motivo]`, `available_for?(agent)` (Tarefa 19), `params`:

```ruby
[
  { 'name' => 'destinos', 'type' => 'array', 'items' => 'string', 'required' => true,
    'description' => 'Siglas ISO 3166 alfa-2 de cada país do roteiro com permanência. Viagem nacional: ["BR"].' },
  { 'name' => 'data_saida', 'type' => 'string', 'required' => true, 'description' => 'Data de ida, AAAA-MM-DD.' },
  { 'name' => 'data_retorno', 'type' => 'string', 'required' => true, 'description' => 'Data de volta, AAAA-MM-DD.' },
  { 'name' => 'idades', 'type' => 'array', 'items' => 'integer', 'required' => true,
    'description' => 'Idade de cada viajante, um inteiro por pessoa, na ordem em que o cliente informou.' },
  { 'name' => 'motivo', 'type' => 'string', 'required' => false, 'enum' => %w[lazer estudo negocios gestante cruzeiro],
    'description' => 'Só quando o cliente contou: gestante, estudo, negocios ou cruzeiro. Sem indicação, null.' }
]
```

  `#call`: sem `delivery` → `error('cotacao_sem_conversa')`; `Pedido#conferir` com falta → `recusar('pedido_invalido',
  falta.texto, faltando: [falta.campo])`; siglas inválidas → `recusar('destino_invalido', ..., faltando: ['destinos'])`;
  `Cliente#cotar`; `Cliente::Erro` → `Falhas.tratar` (Tarefa 18); sem plano por idade →
  `recusar('idade_fora_do_limite', <texto com as idades>, faltando: ['idades'])`; sem plano → `recusar('sem_plano', ...)`;
  grava `CotacaoDeViagem`; `EntregaDoComparativo.postar` (Tarefa 14); devolve
  `JSON.generate({ cotacao: { destinos:, data_saida:, data_retorno:, idades: }, planos: Planos.resumo(planos), pdf_enviado: })`.

- [ ] Spec que falha 1: `spec/services/autonomia/agents/tools/native/seguro_viagem/pedido_spec.rb`

```ruby
let(:hoje) { Date.new(2026, 11, 24) }
let(:base) { { 'destinos' => ['pt'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45] } }

it 'idade vira data técnica: saída − idade anos − 6 meses' do
  pedido, = described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir
  expect(pedido['passageiros']).to eq([{ 'nome' => 'Viajante 1', 'dataNascimento' => '1981-08-02' }])
  expect(pedido['destinos']).to eq(['PT'])
end

it 'tarifa: Acordo com tarifaAcordo, senão Folheto (nunca 0)' do
  expect(described_class.new(base, hoje: hoje, tarifa_acordo: true).conferir.first['tipoTarifa']).to eq(2)
  expect(described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir.first['tipoTarifa']).to eq(1)
end

it 'motivo vira classificação; sem motivo é 1' do
  { nil => 1, 'lazer' => 4, 'estudo' => 5, 'negocios' => 6, 'gestante' => 7, 'cruzeiro' => 8 }.each do |motivo, codigo|
    expect(described_class.new(base.merge('motivo' => motivo), hoje: hoje, tarifa_acordo: false).conferir.first['classificacoes'])
      .to eq([codigo])
  end
end

it 'pedido fixo da viagem única' do
  pedido, = described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir
  expect(pedido.slice('tipoViagem', 'produtoAvulso', 'cupom')).to eq('tipoViagem' => 1, 'produtoAvulso' => false, 'cupom' => '')
end

it 'recusas com o campo' do
  { { 'data_saida' => '2026-11-23' } => 'data_saida', { 'data_retorno' => '2027-02-01' } => 'data_retorno',
    { 'data_saida' => '02/02/2027' } => 'data_saida', { 'idades' => [] } => 'idades', { 'idades' => [121] } => 'idades',
    { 'destinos' => [] } => 'destinos', { 'destinos' => ['PRT'] } => 'destinos', { 'motivo' => 'ferias' } => 'motivo' }.each do |troca, campo|
    _, falta = described_class.new(base.merge(troca), hoje: hoje, tarifa_acordo: false).conferir
    expect(falta.campo).to eq(campo)
  end
end

it 'saída hoje é aceita' do
  expect(described_class.new(base.merge('data_saida' => '2026-11-24'), hoje: hoje, tarifa_acordo: false).conferir.last).to be_nil
end
```

- [ ] Spec que falha 2 (R2): `.../seguro_viagem/planos_spec.rb`

```ruby
let(:resposta) { JSON.parse(file_fixture('../universal/cotacao.json').read) }

it 'só planos com despesas médicas e hospitalares, com código nosso' do
  planos = described_class.de(resposta, idades: [45])
  expect(planos.pluck('codigo')).to eq(%w[P1 P2])
  expect(planos).to all(satisfy { |p| p['coberturas'].any? { |c| c['id_beneficio'] == described_class::ID_DMH } })
end

it 'nunca leva campo interno da tarifa' do
  texto = JSON.generate(described_class.de(resposta, idades: [45]))
  %w[comissao comissaoIntermediario markup rank quotationPorcentagem valorSemDesconto].each do |campo|
    expect(texto).not_to include(campo)
  end
end

it 'resumo em reais com duas casas' do
  expect(described_class.resumo(described_class.de(resposta, idades: [45])).first['preco_total']).to start_with('R$ ')
end

it 'tira o produto que não aceita a idade' do
  expect(described_class.de(resposta, idades: [99]).pluck('codigo')).to eq(<conforme fixture>)
end
```

- [ ] Spec que falha 3: `.../native/cotar_seguro_viagem_spec.rb`

```ruby
it 'cota, guarda e devolve só o resumo' do
  saida = JSON.parse(ferramenta(params).call)
  expect(saida['planos'].first.keys).to contain_exactly('codigo', 'nome', 'preco_total', 'max_parcelas', 'principais')
  cotacao = Autonomia::Agents::CotacaoDeViagem.last
  expect(cotacao.id_cotacao).to eq('COT-TESTE-1')
  expect(cotacao.pedido['passageiros']).to eq([{ 'nome' => 'Viajante 1', 'dataNascimento' => '1981-08-02' }])
  expect(a_request(:post, "#{base}/v1/Cotacao").with(body: hash_including('tipoTarifa' => 2, 'classificacoes' => [1]))).to have_been_made
end

it 'sem conversa não cota' do
  expect(described_class.new(agent: contratado, params: params, delivery: nil).call).to include('cotacao_sem_conversa')
  expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
end

it 'data errada recusa com o campo e registra a recusa (não trava a escrita do turno)' do
  expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pedido_invalido', hash_including(faltando: ['data_saida']))
  ferramenta(params.merge('data_saida' => '2020-01-01')).call
end

it 'timeout não levanta' do
  stub_request(:post, "#{base}/v1/Cotacao").to_timeout
  expect { ferramenta(params).call }.not_to raise_error
end
```

- [ ] Rodar: não rodar localmente; roda na CI. Rubocop nos três arquivos.
- [ ] Implementar. Commits: `test(seguro-viagem): cotar seguro viagem` / `feat(seguro-viagem): cotar seguro viagem`.

### Tarefa 14 — PDF comparativo e entrega na conversa

**Arquivos.** Criar `native/seguro_viagem/comparativo_pdf.rb`, `native/seguro_viagem/entrega_do_comparativo.rb`;
modificar `spec/services/autonomia/insurance/receita/sem_texto_fixo_ao_cliente_spec.rb` (`PONTOS`).

**Interfaces.**
- `ComparativoPdf.new(cotacao:, nome_corretora:).render -> String` (bytes `%PDF-`), Prawn, A4 paisagem, cores de
  `Autonomia::Desempenho::Exportacao::Pdf::COR` (navy, tinta, linha) e `FONTES` de `Relatorios::Pdf::FONTES`.
  Conteúdo: nome da corretora; destino(s), datas, viajantes por idade; tabela lado a lado (uma coluna por plano):
  preço total, preço por pessoa (por faixa de cada idade), parcelas, **todas** as coberturas com valor e moeda (linhas
  pela união dos `id_beneficio`, "—" quando o plano não tem); data da cotação. Sem comissão, sem `id_produto`, sem
  código `P1`.
- `EntregaDoComparativo.postar(conversation:, cotacao:, agent:) -> Boolean`. Grava o blob
  (`ActiveStorage::Blob.create_and_upload!(io:, filename: 'comparativo-seguro-viagem.pdf', content_type: 'application/pdf')`)
  e, **sob o lock da conversa**, cria a mensagem com `Messages::MessageBuilder` (`content: nil`, `attachments:
  [blob.signed_id]`, `message_type: 'outgoing'`, `sender_type: 'AgentBot'`, `sender_id:` do `agent_inbox` da conversa
  (`Autonomia::Agents::QuemResponde.agent_inbox`), `private: conversation.assignee_id.present?`,
  `content_attributes: { 'autonomia_agent_id' => agent.id, 'autonomia_comparativo_viagem' => cotacao.id }`), só se ainda
  não houver mensagem com esse `autonomia_comparativo_viagem` (mesma peneira de `NotaNaHora.postada?`). Falha → log com
  ids e classe, `false`, nunca levanta.
- `PONTOS` ganha `'app/services/autonomia/agents/tools/native/seguro_viagem/entrega_do_comparativo.rb::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo#criar' => { tipo: :anexo_sem_texto, motivo: 'o comparativo da cotação de seguro viagem, em PDF, sem legenda (#3211)' }` (ajustar o nome do método ao que for implementado: a chave é `arquivo::Classe#metodo`).

- [ ] Spec que falha: `.../seguro_viagem/comparativo_pdf_spec.rb` (bytes começam com `%PDF-`; o texto extraído por
  `PDF::Reader` — `pdf-reader 2.16.0` está no `Gemfile.lock` — inclui o nome da corretora, `'R$ '` e o nome de cada
  cobertura, e não inclui `'comissao'` nem `'P1'`) e `.../entrega_do_comparativo_spec.rb`:

```ruby
it 'posta o PDF uma vez por cotação, sem texto' do
  2.times { described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado) }
  mensagens = conversa.messages.where("content_attributes::text LIKE '%autonomia_comparativo_viagem%'")
  expect(mensagens.count).to eq(1)
  expect(mensagens.first.content).to be_nil
  expect(mensagens.first.attachments.first.file.content_type).to eq('application/pdf')
end

it 'com responsável na conversa vira nota privada' do
  conversa.update!(assignee: atendente)
  described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado)
  expect(conversa.messages.last.private).to be(true)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): comparativo em PDF na conversa` / `feat(seguro-viagem): comparativo em PDF na conversa`.

### Tarefa 15 — `detalhes_da_cotacao`

**Arquivos.** Criar `native/detalhes_da_cotacao.rb`.

**Interfaces.** `slug 'detalhes_da_cotacao'`, `escreve? false`, `args_registraveis %w[codigos_dos_planos]`, `params`:
`[{ 'name' => 'codigos_dos_planos', 'type' => 'array', 'items' => 'string', 'required' => true, 'description' =>
'Códigos dos planos da última cotação desta conversa. Lista vazia: todos.' }]`. `#call`: sem `delivery` →
`error('cotacao_sem_conversa')`; sem cotação → `recusar('sem_cotacao', ...)`; código desconhecido →
`recusar('plano_inexistente', ..., faltando: ['codigos_dos_planos'])`; devolve JSON com, por plano: `codigo, nome,
descricao_adicional, preco_total, preco_por_pessoa` (lista por viajante, pela faixa da idade cotada),
`max_parcelas, cambio, moeda, idade_minima, idade_maxima, regra_cancelamento, coberturas` (todas, com
`descricao_completa`). Sem chamada à Universal.

- [ ] Spec que falha: `.../native/detalhes_da_cotacao_spec.rb`

```ruby
it 'lê a cotação guardada, sem chamar a Universal' do
  saida = JSON.parse(ferramenta('codigos_dos_planos' => ['P1']).call)
  expect(saida['planos'].first['coberturas'].first.keys).to include('nome', 'valor', 'moeda', 'descricao_completa')
  expect(a_request(:any, /universal-assistance/)).not_to have_been_made
end

it 'preço por pessoa pela faixa de cada idade cotada' do
  expect(JSON.parse(ferramenta('codigos_dos_planos' => []).call)['planos'].first['preco_por_pessoa'].size).to eq(cotacao.idades.size)
end

it 'sem campo interno' do
  expect(ferramenta('codigos_dos_planos' => []).call).not_to include('comissao', 'markup', 'rank', 'id_produto')
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): detalhes da cotação` / `feat(seguro-viagem): detalhes da cotação`.

### Tarefa 16 — Endereço pelo CEP, do lado do servidor

**Arquivos.** Criar `native/seguro_viagem/endereco_do_cep.rb`.

**Interfaces.** `EnderecoDoCep.buscar(agent:, cep:) -> Hash|nil` (`'logradouro', 'bairro', 'cidade', 'uf', 'cep'`).
Consome `FerramentasProntas::Fontes::Cep::FONTE.consulta('endereco')`, `Consulta#conferir({ 'cep' => cep })`,
`FerramentasProntas::Cache.new(FONTE, consulta, params).ler`; no cache vazio, roda a pronta do agente
(`FerramentasProntas::Execucao.new(tool: agent.tools.find_by(fonte_pronta: 'cep'), params: { 'consulta' => 'endereco',
'cep' => cep }).call`) e lê o cache de novo. O endereço nunca vem do modelo.

- [ ] Spec que falha: `.../seguro_viagem/endereco_do_cep_spec.rb`: cache com `{'situacao' => 'encontrado', 'dados' =>
  {'cep' => '01310-100', 'logradouro' => 'Avenida Paulista', 'bairro' => 'Bela Vista', 'cidade' => 'São Paulo', 'uf' =>
  'SP'}}` → devolve o hash sem chamar provedor; cache vazio + ViaCEP gravado com WebMock → devolve e chama a
  `Execucao` uma vez; CEP com 7 dígitos → nil; `nao_encontrado` → nil.
- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): endereço pelo CEP no servidor` / `feat(seguro-viagem): endereço pelo CEP no servidor`.

### Tarefa 17 — `gerar_proposta_seguro_viagem`

**Arquivos.** Criar `native/seguro_viagem/viajantes.rb`, `native/seguro_viagem/faixas.rb`,
`native/seguro_viagem/compra.rb`, `native/gerar_proposta_seguro_viagem.rb`.

**Interfaces.**
- `Viajantes.conferir(titular:, demais:) -> [Array<Hash>, nil] | [nil, Falta]`: nome completo com pelo menos duas
  palavras (`split`), CPF por `FerramentasProntas::Fontes::Cpf.valido?(Parametro.digitos(cpf, 11))`, CPFs sem
  repetição, nascimento `Date.iso8601`, e-mail com `@` e ponto depois dele (`split('@')`), telefone 10 ou 11 dígitos,
  CEP 8 dígitos, `numero` presente; `complemento` pode ser nil.
- `Faixas.idade_em(nascimento, data) -> Integer`; `Faixas.mesma_faixa?(plano, idades_cotadas, idades_reais) ->
  Boolean` (compara as **multisets** das faixas `de..ate` de cada idade; idade sem faixa ou fora de
  `idade_minima..idade_maxima` → false).
- `Compra.montar(cotacao:, plano:, viajantes:, endereco:, contato:) -> Hash` com as chaves exatas dos fatos:
  `DadosBasicos{Destinos, TipoViagem: 1, TipoTarifa: cotacao.pedido['tipoTarifa'], DataSaida, DataRetorno (ISO, da
  cotação), ValorCompra: plano['preco_total'] (número), FormaPagamento: 8, NomeContatoBrasil, TelefoneContatoBrasil,
  CelularContatoBrasil}`, `DadosTitular{Codigo: 1, Nome, Sobrenome (split(' ', 2)), Documento, TipoDocumento: 1,
  Telefone, Celular, Email, DataNascimento ISO, Endereco, CEP, Numero, Cidade, Bairro, UF, SiglaPaisEndereco: 'BR',
  Complemento, Idade}`, `DadosIntegrantes[{Codigo: 2.., Nome, Sobrenome, TipoDocumento: 1, Documento, DataNascimento,
  Idade}]`, `DadosProdutos{CodigoProduto: plano['id_produto'], ValorProduto: plano['preco_total'],
  CodigoPeriodoMultiViagem: 0, CodigoTarifaAcordo: plano['id_produto_acordo'], Cambio: plano['cambio']}`,
  `DadosBeneficios: [], DadosBeneficiosCustomizavel: [], DadosProdutosAvulsos: []`, `DadosPagamento{NomeTitularCartao,
  CPFTitular}` (do titular). `FORMA_DE_PAGAMENTO_LINK = 8`.
- `Compra.link(codigo_carrinho) -> String|nil`: `URI::HTTPS.build(host: 'pagamento.universal-assistance.com', path: '/',
  query: URI.encode_www_form('IdCarrinho' => codigo)).to_s`; codigo vazio → nil.
- `Native::GerarPropostaSeguroViagem`: `slug 'gerar_proposta_seguro_viagem'`, `escreve? true`,
  `args_registraveis %w[codigo_do_plano]`, `params`:

```ruby
VIAJANTE = [
  { 'name' => 'nome_completo', 'type' => 'string', 'required' => true, 'description' => 'Nome completo.' },
  { 'name' => 'cpf', 'type' => 'string', 'required' => true, 'description' => 'CPF completo.' },
  { 'name' => 'data_nascimento', 'type' => 'string', 'required' => true, 'description' => 'AAAA-MM-DD.' }
].freeze
[
  { 'name' => 'codigo_do_plano', 'type' => 'string', 'required' => true,
    'description' => 'Código do plano escolhido, da última cotação desta conversa.' },
  { 'name' => 'titular', 'type' => 'object', 'required' => true, 'properties' => VIAJANTE + [
    { 'name' => 'email', 'type' => 'string', 'required' => true, 'description' => 'E-mail do titular.' },
    { 'name' => 'telefone', 'type' => 'string', 'required' => true, 'description' => 'Telefone com DDD.' },
    { 'name' => 'cep', 'type' => 'string', 'required' => true, 'description' => 'CEP do endereço, 8 dígitos.' },
    { 'name' => 'numero', 'type' => 'string', 'required' => true, 'description' => 'Número do endereço.' },
    { 'name' => 'complemento', 'type' => 'string', 'required' => false, 'description' => 'Complemento; null sem.' }
  ] },
  { 'name' => 'demais_viajantes', 'type' => 'array', 'required' => true, 'items' => { 'properties' => VIAJANTE },
    'description' => 'Os outros viajantes da cotação. Lista vazia quando só o titular viaja.' },
  { 'name' => 'contato_de_emergencia', 'type' => 'object', 'required' => true, 'properties' => [
    { 'name' => 'nome', 'type' => 'string', 'required' => true, 'description' => 'Nome de quem fica no Brasil.' },
    { 'name' => 'telefone', 'type' => 'string', 'required' => true, 'description' => 'Telefone com DDD.' }
  ] }
]
```

  `#call`, nesta ordem: sem `delivery` → `error('proposta_sem_conversa')`; acesso só cota →
  `recusar('so_cotacao', ...)`; `CotacaoDeViagem.ultima_da_conversa` nil → `recusar('sem_cotacao', ...)`; cotação de
  outro dia (`do_dia?(fuso)` falso) → `recusar('recotar', ...)`; `cotacao.plano(codigo)` nil →
  `recusar('plano_inexistente', ..., faltando: ['codigo_do_plano'])`; `Viajantes.conferir` falta →
  `recusar('pedido_invalido', falta.texto, faltando: [falta.campo])`; quantidade diferente de `cotacao.idades.size` →
  `recusar('quantidade_de_viajantes', ...)`; `Faixas.mesma_faixa?` falso → `recusar('recotar', 'A idade real pela data
  de nascimento muda a faixa de preço. Cote de novo com as idades: [..]', faltando: ['idades'])`;
  `EnderecoDoCep.buscar` nil → `recusar('cep_nao_encontrado', ..., faltando: ['titular.cep'])`; então
  `cotacao.with_lock`: chave `Digest::SHA256.hexdigest([cotacao.id, codigo, cpfs.sort].join('|'))`; se
  `cotacao.proposta&.dig('chave') == chave` → devolve a mesma proposta guardada; senão `Cliente#comprar(Compra.montar(...))`,
  `Cliente::Erro` → `Falhas.tratar`; `Compra.link` nil → `Falhas.sem_link` (nota + recusa); grava
  `proposta: { 'chave', 'codigo_do_plano', 'codigo_carrinho', 'link', 'valor_bruto_brl', 'gerada_em' }` (nenhum dado
  pessoal); devolve `JSON.generate({ link_de_pagamento:, numero_do_carrinho:, plano: plano['nome'], total: <R$> })`.

- [ ] Spec que falha 1: `.../seguro_viagem/faixas_spec.rb`

```ruby
let(:plano) { { 'idade_minima' => 0, 'idade_maxima' => 85,
                'faixas' => [{ 'de' => 0, 'ate' => 64 }, { 'de' => 65, 'ate' => 75 }, { 'de' => 76, 'ate' => 85 }] } }

it 'idade na data da saída' do
  expect(described_class.idade_em(Date.new(1981, 3, 15), Date.new(2027, 2, 2))).to eq(45)
  expect(described_class.idade_em(Date.new(1981, 2, 2), Date.new(2027, 2, 2))).to eq(46)
end

it 'mesma faixa por multiset, não pela ordem' do
  expect(described_class.mesma_faixa?(plano, [45, 70], [71, 44])).to be(true)
  expect(described_class.mesma_faixa?(plano, [45], [66])).to be(false)
  expect(described_class.mesma_faixa?(plano, [45], [90])).to be(false)
end
```

- [ ] Spec que falha 2: `.../seguro_viagem/compra_spec.rb` — `FormaPagamento == 8`; `ValorCompra` e `ValorProduto`
  iguais ao `preco_total` do plano; `CodigoProduto` e `CodigoTarifaAcordo` do plano; datas da cotação;
  `TipoTarifa` igual ao do pedido guardado; `DataNascimento` do titular é a informada (não 1º de janeiro);
  `Compra.link(987654) == 'https://pagamento.universal-assistance.com/?IdCarrinho=987654'`; `Compra.link(nil)` nil.
- [ ] Spec que falha 3 (R3): `.../native/gerar_proposta_seguro_viagem_spec.rb`

```ruby
it 'preço e produto saem da cotação guardada' do
  ferramenta(params).call
  expect(a_request(:post, "#{base}/v1/Compras").with { |r|
    corpo = JSON.parse(r.body)
    corpo['DadosBasicos']['ValorCompra'].to_d == BigDecimal(plano['preco_total']) &&
      corpo['DadosProdutos']['CodigoProduto'] == plano['id_produto'] && corpo['DadosBasicos']['FormaPagamento'] == 8
  }).to have_been_made.once
end

it 'devolve o link montado do codigoCarrinho' do
  expect(JSON.parse(ferramenta(params).call)['link_de_pagamento'])
    .to eq('https://pagamento.universal-assistance.com/?IdCarrinho=987654')
end

it 'idempotente: a mesma chamada não gera segunda proposta' do
  2.times { ferramenta(params).call }
  expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.once
end

it 'código inexistente recusa sem chamar a Universal' do
  expect(ferramenta(params.merge('codigo_do_plano' => 'P9')).call).to be_present
  expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
end

it 'faixa mudou: recotar, registrado (não conta como escrita feita)' do
  expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('recotar', anything)
  ferramenta(params_com_titular_nascido_em('1960-01-10')).call
end

it 'cotação de ontem: recotar' do
  cotacao.update_columns(created_at: 2.days.ago)
  expect(ferramenta(params).call).to include('Cote de novo').or include('recotar')
end

it 'acesso que só cota não gera' do
  acesso.update!(capacidades: acesso.capacidades.merge('soCotacao' => true))
  ferramenta(params).call
  expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
end

it 'proposta guardada não tem dado pessoal' do
  ferramenta(params).call
  expect(cotacao.reload.proposta.to_json).not_to include('52998224725', 'Fulano', '@')
end
```

- [ ] Rodar: não rodar localmente; roda na CI. Rubocop nos arquivos.
- [ ] Implementar. Commits: `test(seguro-viagem): proposta com link de pagamento` / `feat(seguro-viagem): proposta com link de pagamento`.

### Tarefa 18 — Falhas da Universal: nota à equipe e passagem

**Arquivos.** Criar `native/seguro_viagem/falhas.rb` (módulo incluído nas duas ferramentas que chamam a Universal;
fazer **antes** das Tarefas 13 e 17 se for mais natural, a ordem dos commits não importa); i18n backend.

**Interfaces.** `SeguroViagem::Falhas#tratar_falha(erro, acao:) -> String` (privado, usa `recusar` da `Base`):
- `acesso_recusado`: `agent.acesso_da_seguradora.update!(estado: 'recusado', motivo: 'acesso_recusado')`;
  `Insurance::NotaNaHora.postar(delivery.conversation, I18n.t('autonomia.contratados.universal.notas.acesso_recusado'),
  chave: "universal:acesso_recusado:#{delivery.turno}")`; devolve `recusar('acesso_recusado', TEXTO_PASSAR)` com
  `TEXTO_PASSAR = 'A seguradora recusou o acesso da corretora. Não tente de novo. Passe a conversa para a equipe agora e
  diga ao cliente só que alguém da equipe vai continuar, sem falar do erro.'`.
- `indisponivel`: nota (`notas.indisponivel`, chave com `acao` e turno) e `recusar('indisponivel', 'O sistema da
  seguradora não respondeu. Tente uma vez de novo; se falhar de novo, passe a conversa para a equipe, sem mostrar o erro.')`.
- `pedido_invalido`: `recusar('pedido_invalido', "A seguradora não aceitou o pedido: #{erro.mensagem_da_seguradora}.
  Corrija com o cliente só o dado em questão.")` (a mensagem não vai a log).
- `sem_link`: nota (`notas.sem_link`) e recusa que manda passar para a equipe.
Textos das notas em en e pt_BR, sem dado do cliente.

- [ ] Spec que falha: `.../seguro_viagem/falhas_spec.rb`

```ruby
it 'acesso recusado: marca o acesso, posta nota privada uma vez, registra a recusa' do
  expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('acesso_recusado', anything).twice
  2.times { ferramenta_com_erro('acesso_recusado').call }
  expect(acesso.reload.estado).to eq('recusado')
  expect(conversa.messages.where(private: true).count).to eq(1)
end

it 'a frase ao modelo não traz o erro técnico nem a credencial' do
  texto = ferramenta_com_erro('acesso_recusado').call
  expect(texto).not_to include('401', 'corretor.teste')
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): falhas da seguradora` / `feat(seguro-viagem): falhas da seguradora`.

### Tarefa 19 — Registro das ferramentas e porta por agente

**Arquivos.** Modificar `app/services/autonomia/agents/tools/registry.rb:10-34` (três classes no fim de
`DE_ATENDIMENTO`, depois de `EnviarContato`, com comentário `# #3211 — o agente contratado Seguro Viagem Universal`).

**Interfaces.** `available_for?(agent)` das três:
`agent.contratado? && Contratados.ferramentas(agent)&.include?(slug) && agent.acesso_da_seguradora&.ok?`; a de
proposta também `&& !agent.acesso_da_seguradora.so_cotacao?`.

- [ ] Spec que falha (R4): `spec/services/autonomia/agents/tools/ferramentas_do_contratado_spec.rb`

```ruby
SLUGS = %w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem].freeze

it 'agente comum com os slugs gravados não recebe nenhuma' do
  comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', config: { 'native_tool_slugs' => SLUGS })
  expect(Autonomia::Agents::Tools::Registry.for_agent(comum).map(&:slug)).to eq([])
end

it 'contratado sem acesso ok não recebe nenhuma' do
  expect(Autonomia::Agents::Tools::Registry.for_agent(contratado).map(&:slug)).to eq([])
end

it 'contratado com acesso ok recebe as três' do
  acesso_ok!
  expect(Autonomia::Agents::Tools::Registry.for_agent(contratado).map(&:slug)).to eq(SLUGS)
end

it 'login que só cota: sem proposta' do
  acesso_ok!(capacidades: { 'soCotacao' => true })
  expect(Autonomia::Agents::Tools::Registry.for_agent(contratado).map(&:slug)).to eq(SLUGS.first(2))
end

it 'schema strict aceito: required lista todas as chaves' do
  schema = Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem.openai_schema(contratado)
  expect(schema[:parameters][:required]).to eq(%w[codigo_do_plano titular demais_viajantes contato_de_emergencia])
end
```

Tirar o `pending` do exemplo de slugs da Tarefa 6.

- [ ] Rodar: não rodar localmente; roda na CI. Conferir que `base_escreve_declarado_spec.rb` e
  `base_contrato_de_nivel_spec.rb` (varrem o `Registry`) continuam válidos por leitura do código.
- [ ] Implementar. Commits: `test(seguro-viagem): ferramentas só no contratado com acesso` / `feat(seguro-viagem): ferramentas no catálogo`.

### Tarefa 20 — `Contratar`, dados da corretora e base semeada

**Arquivos.** Criar `contratados/contratar.rb`, `contratados/dados_da_corretora.rb`, `contratados/base.rb`,
`app/jobs/autonomia/agents/contratados/semear_base_job.rb`, `.../base_em_dia_job.rb`; modificar `config/schedule.yml`
(depois da 297).

**Interfaces.**
- `Contratar.new(account:, user:, modelo:, nome_agente:, nome_corretora:, sobre_corretora:).call -> Agent`.
  `class Recusado < StandardError` com `motivo` (`indisponivel`, `nome_agente`, `nome_corretora`, `sobre_corretora`,
  `marcador`). Confere: `Contratados.disponivel?`; nomes 1..120; sobre 0..1000; nenhum valor com marcador
  (`Instrucao.marcador_dentro?`). Transação: cria o `Agent` (`agent_type: 'sdr'`, `name: nome_agente`, `status:
  :paused`, `enabled: false`, `mode: :guided`, `created_by: user`, `instruction:` retrato do nascimento
  `Instrucao.renderizar` sobre o novo, `config: { 'contratado' => marca, 'with_knowledge' => true }.merge(modelo[:conversa])`),
  `save!(context: %i[create ativacao])`; inclui as prontas `cep` e `cpf` com `FerramentasProntas::Incluir.new(...,
  pelo_contratar: true, usar_quando: USAR_QUANDO[fonte]).call` (`USAR_QUANDO = { 'cep' => 'na proposta, para achar o
  endereço do titular pelo CEP', 'cpf' => 'na proposta, para conferir cada CPF assim que chegar' }`). Depois do commit:
  `SemearBaseJob.perform_later(agent.id)`. Várias cópias por conta são permitidas (uma por corretora).
- `DadosDaCorretora.new(agent:, nome_agente:, nome_corretora:, sobre_corretora:).call -> Agent`: as mesmas conferências;
  `agent.with_lock` regrava `config['contratado']` (sem tocar `modelo`) e `name`; não re-semeia a base.
- `Base::VERSAO -> String` (`Digest::SHA256` do conteúdo dos arquivos de `base/` ordenados, 16 caracteres);
  `Base.em_dia?(agent) -> Boolean` (`config['contratado_base_versao'] == versao` e entradas prontas existem);
  `Base.semear!(agent)`: lê `base/*.md`, fatia nos blocos que começam por `### ` (por `each_line` + `start_with?`, sem
  regex), embebe com `EmbeddingService.new(account:, model: Config.active_embedding_model).embed_batch`, recria a fonte
  `source_type: 'md', kind: :knowledge, reference: 'Base oficial Universal', metadata: { 'contratado_base' => true }`,
  `status: ready`, `review_status: 'accepted'`, e as `KnowledgeEntry` (mesmo desenho de `Guide::Seed#ensure_knowledge`,
  incluindo a coluna `embedding_large`), e grava `contratado_base_versao` com `update_columns` no jsonb (`jsonb_set`)
  para não passar pelo save comum. Sob `pg_advisory_lock` por agente.
- `SemearBaseJob#perform(agent_id)`: `Base.semear!` se não `em_dia?`; agente apagado ou não contratado: nada.
- `BaseEmDiaJob#perform`: para cada contratado `kept` com versão diferente, `SemearBaseJob.perform_later`. Cron
  `autonomia_contratados_base_em_dia_job: cron: '17 * * * *'`, `queue: scheduled_jobs`.
- `contratado_base_versao` entra em `RESERVED_CONFIG_KEYS` (Tarefa 9, mesma linha).

- [ ] Spec que falha: `spec/services/autonomia/agents/contratados/contratar_spec.rb`

```ruby
it 'nasce sdr, parado, com a marca, as opções de conversa e as duas prontas' do
  agente = contratar.call
  expect(agente).to have_attributes(agent_type: 'sdr', status: 'paused', enabled: false, mode: 'guided', name: 'Bia')
  expect(agente.config['contratado']).to eq('modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia',
                                            'nome_corretora' => 'Corretora Exemplo', 'sobre_corretora' => 'Desde 2010.')
  expect(agente.config).to include('humanize_delivery' => true, 'voice_reply' => true)
  expect(agente.tools.pluck(:fonte_pronta)).to contain_exactly('cep', 'cpf')
  expect(Autonomia::FerramentasProntas.rodadas(agente)).to include(max_rodadas: 3, uma_escrita_por_turno: true)
end

it 'liga as opções de conversa do PR 1' do
  expect(contratar.call.config).to include(Autonomia::Agents::Contratados::CONVERSA_DO_PR1)
end

it 'enfileira a base depois do commit' do
  expect { contratar.call }.to have_enqueued_job(Autonomia::Agents::Contratados::SemearBaseJob)
end

it 'recusa nome com marcador, só com o campo' do
  expect { contratar(nome_corretora: '$nomeAgente').call }.to raise_error(described_class::Recusado) { |e| expect(e.motivo).to eq('marcador') }
end

it 'conta sem a flag: indisponivel, nada criado' do
  account.disable_features!('agente_seguro_viagem_universal')
  expect { contratar.call }.to raise_error(described_class::Recusado)
  expect(Autonomia::Agents::Agent.count).to eq(0)
end
```

E `base_spec.rb` (fatiamento: um texto com 3 blocos `### ` vira 3 entradas; versão muda quando o arquivo muda; com
`EmbeddingService` stubado devolvendo vetores, a fonte fica `accepted`/`ready` e a segunda semeadura apaga as entradas
antigas), `dados_da_corretora_spec.rb` (troca os três, mantém `modelo`, não enfileira a base) e os dois jobs.

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): contratar e base oficial` / `feat(seguro-viagem): contratar e base oficial`.

### Tarefa 21 — API: catálogo, contratar, dados e acesso

**Arquivos.** Criar os três controllers do mapa; modificar `config/routes.rb` (no bloco das linhas 713-777: dentro de
`resources :agents` → `patch 'contratado', to: 'agents/contratado#update'` e `resource :acesso_da_seguradora, only:
[:show, :create], controller: 'agents/acesso_da_seguradora'`; fora dele, ao lado de `modelos_de_ramo` →
`get 'contratados', to: 'contratados#index'` e `post 'contratados/:modelo', to: 'contratados#create'`);
`_agent.json.jbuilder:31` (novo bloco `json.contratado`); `lib/operator_guide/automacao-recursos.yml:599-625`;
i18n backend.

**Interfaces.**
- `GET /api/v1/accounts/:account_id/autonomia/contratados` → `{ modelos: ['seguro_viagem_universal'] }` (só chaves;
  textos são da tela; vazio sem flag).
- `POST /api/v1/accounts/:account_id/autonomia/contratados/:modelo` params `{ nome_agente, nome_corretora,
  sobre_corretora }` → 201 com o agente (`render 'api/v1/accounts/autonomia/agents/show'`); `Recusado` → 422
  `{ error:, code: motivo }`.
- `PATCH /api/v1/accounts/:account_id/autonomia/agents/:agent_id/contratado` mesmos params → 200 com o agente; agente
  não contratado → 404.
- `POST .../agents/:agent_id/acesso_da_seguradora` `{ login, senha }` → `ConferirAcesso` → 200
  `acesso.payload_publico`; `GET` → 200 `payload_publico` ou `{ estado: 'nao_conferido' }` sem linha.
- jbuilder: `json.contratado(agent.contratado? ? agent.config['contratado'].slice('modelo', 'nome_agente',
  'nome_corretora', 'sobre_corretora').merge('acesso' => agent.acesso_da_seguradora&.payload_publico) : nil)`.
- `automacao-recursos.yml`: `autonomia/contratados`, `autonomia/agents/contratado`,
  `autonomia/agents/acesso_da_seguradora` no grupo "Rotas de IA, do CRM e dos agentes. Sempre fora".
- Permissão: herda `check_module_permission!('autonomia')` do `BaseController` (escrita = `autonomia_manage`).

- [ ] Spec que falha: `spec/requests/api/v1/accounts/autonomia/contratados_spec.rb`,
  `.../agents/contratado_spec.rb`, `.../agents/acesso_da_seguradora_spec.rb`

```ruby
it 'acesso: POST confere e nunca devolve a senha nem o login (R5)' do
  post acesso_url, params: { login: 'corretor.teste', senha: 's3nha-teste' }, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:ok)
  expect(response.body).not_to include('s3nha-teste', 'corretor.teste')
  expect(response.parsed_body).to include('estado' => 'ok', 'login_dica' => 'co•••te')
end

it 'acesso: GET do agente mostra só a dica' do
  get agent_url, headers: admin.create_new_auth_token, as: :json
  expect(response.parsed_body.dig('contratado', 'acesso', 'login_dica')).to eq('co•••te')
  expect(response.body).not_to include('senha')
end

it 'agente de quem só vê não contrata' do
  post contratar_url, params: tres_campos, headers: agente_sem_funcao.create_new_auth_token, as: :json
  expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
end

it 'contrata e responde o agente com a marca pública' do
  post contratar_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:created)
  expect(response.parsed_body.dig('contratado', 'modelo')).to eq('seguro_viagem_universal')
end

it 'agente de outra conta: 404' do
  patch outro_contratado_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json
  expect(response).to have_http_status(:not_found)
end
```

- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] `bundle exec rails autonomia:guia:formatos` (strong params novos) e incluir o resultado; rubocop.
- [ ] Commits: `test(seguro-viagem): API do agente contratado` / `feat(seguro-viagem): API do agente contratado` /
  `chore(guia): formatos regerados com a API do contratado`.

### Tarefa 22 — Caixa só com acesso conferido

**Arquivos.** Modificar `app/services/autonomia/agents/operate/inbox_connector.rb:59-67`; i18n
`autonomia.agents.operate.connect_errors.acesso_da_seguradora_pendente` (en + pt_BR).

**Interfaces.** Em `recusa_de_conexao`, antes de `:agent_not_active`:
`return :acesso_da_seguradora_pendente if @agent.contratado? && !@agent.acesso_da_seguradora&.ok?`.

- [ ] Spec que falha: `spec/services/autonomia/agents/operate/inbox_connector_contratado_spec.rb`: contratado sem
  acesso ok → `result.error == :acesso_da_seguradora_pendente` e nenhum `AgentInbox` criado; com acesso ok e
  `ativar: true` → vínculo criado e agente `active`/`enabled`; agente comum inalterado.
- [ ] Rodar: não rodar localmente; roda na CI.
- [ ] Implementar. Commits: `test(seguro-viagem): caixa só com acesso conferido` / `feat(seguro-viagem): caixa só com acesso conferido`.

### Tarefa 23 — Flag da conta

**Arquivos.** Modificar `config/features.yml` (fim do arquivo) e `app/javascript/dashboard/featureFlags.js`.

**Interfaces.** Flag `agente_seguro_viagem_universal`, `display_name: 'Agentes › pronto Seguro Viagem Universal'`,
`enabled: true` (vale para conta nova; nas existentes a Orquestração liga depois do piloto), coluna
`feature_flags_ext_2` se ainda houver posição livre no rebase (hoje sobram 3, segundo o comentário da linha 1510),
senão `feature_flags_ext_3`. Front: `AGENTE_SEGURO_VIAGEM_UNIVERSAL: 'agente_seguro_viagem_universal'`.

- [ ] Spec: a guarda de flags existente (`spec/config` / `spec/lib` que conferem `features.yml`) é o teste; conferir
  por leitura que o nome é único e a coluna tem posição.
- [ ] Commit: `feat(seguro-viagem): flag do agente pronto`.

### Tarefa 24 — GATE: mockup em prints aprovado pelo Rodrigo

Nenhuma tarefa de tela (25 a 29) começa antes deste gate fechar.

- [ ] Escrever `app/javascript/dashboard/routes/dashboard/autonomia/agentes/stories/Contratado.story.vue` com dados
  fictícios (nome "Bia", "Corretora Exemplo"), uma variante por estado da jornada:
  1. Área de Agentes → seção "Prontos para contratar" com o cartão "Seguro Viagem Universal";
  2. Página do modelo (o que ele faz, o que precisa, botão **Contratar**);
  3. Três campos (nome do agente, nome da corretora, descrição da corretora), com erro de campo;
  4. Login e senha da Universal: vazio, conferindo, "Acesso conferido", recusado, "esse login só cota";
  5. Passagem para a escolha da caixa (gaveta Onde, que já existe).
- [ ] Gerar os prints sem servidor: Histoire + Playwright headless a **1440 px** e **390 px** (modelo de
  `vitest-e-prints-em-worktree-sem-deps`: link de `node_modules`, Vite avulso), salvar em
  `$TMPDIR/prints-3211/` (fora do repositório).
- [ ] Abrir cada PNG e conferir. Rodar o agente `diretor-de-arte` com os prints, o i18n e os componentes; corrigir os
  achados antes de mostrar.
- [ ] Mostrar ao Rodrigo; registrar a aprovação (data e texto) no PR. Sem `<select>` nativo; escolhas com `ChoiceSelect`.
- [ ] Commit (só a história): `chore(seguro-viagem): história do mockup do agente contratado`.

### Tarefa 25 — Cliente da API e composable (front)

**Arquivos.** Criar `app/javascript/dashboard/api/autonomia/contratados.js` e `.../agentes/composables/useContratados.js`.

**Interfaces.** `ContratadosAPI.lista() -> GET contratados`; `.contratar(modelo, { nomeAgente, nomeCorretora,
sobreCorretora })` (snake_case no corpo); `.salvarDados(agentId, campos) -> PATCH agents/:id/contratado`;
`.acesso(agentId) -> GET`; `.conferirAcesso(agentId, { login, senha }) -> POST`. `useContratados()` → `{ modelos }`
(lista vazia em falha, `console.warn` só com o status, como `useRamosDeSeguro`).

- [ ] Spec que falha (vitest): `specs/contratados/useContratados.spec.js` e `specs/contratados/contratadosApi.spec.js`
  (URL e corpo exatos; senha nunca guardada em estado depois do POST).
- [ ] Rodar: `pnpm test app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/contratados`.
- [ ] Implementar; `pnpm eslint`. Commits: teste / `feat(seguro-viagem): cliente da API do contratado no painel`.

### Tarefa 26 — Cartão "Prontos para contratar"

**Arquivos.** Criar `ProntosParaContratar.vue`, `ContratadoCartao.vue`; modificar `AgenteEscolherPage.vue` (65-231:
seção nova depois de `RamosProntos`, antes dos modelos gerais, como no mockup aprovado).

**Interfaces.** Props `modelos: Array`, `podeUsar: Boolean`; emite `abrir(chave)` → rota `autonomia_contratado_modelo`.
Só aparece com lista não vazia.

- [ ] Spec que falha: `specs/contratados/ProntosParaContratar.spec.js` (sem modelos não renderiza; com
  `['seguro_viagem_universal']` mostra o título do i18n e leva à rota com `params.modelo`; quem não gerencia vê sem botão).
- [ ] Rodar vitest; implementar; eslint. Commits: teste / `feat(seguro-viagem): cartão Prontos para contratar`.

### Tarefa 27 — Página do modelo e os três campos

**Arquivos.** Criar `ContratadoModeloPage.vue`, `DadosDaCorretoraForm.vue`.

**Interfaces.** Página recebe `modelo`; mostra o que o agente faz e o que vai pedir; **Contratar** abre o formulário
(3 campos, `maxlength` 120/120/1000, contador no de descrição). Envio → `ContratadosAPI.contratar` → rota
`autonomia_agent_panel` com `?gaveta=contratado` (Tarefa 28). Erro 422 mostra a mensagem do campo (`code`).
`DadosDaCorretoraForm` é o mesmo componente da edição depois (prop `inicial`).

- [ ] Spec que falha: `specs/contratados/ContratadoModeloPage.spec.js` (campos obrigatórios bloqueiam o envio; corpo
  enviado exato; sucesso navega para o agente criado com a gaveta; 422 `nome_corretora` marca o campo).
- [ ] Rodar vitest; implementar; eslint. Commits: teste / `feat(seguro-viagem): página do modelo e dados da corretora`.

### Tarefa 28 — Gaveta do contratado (dados e acesso) e regras da página

**Arquivos.** Criar `GavetaDoContratado.vue`, `AcessoDaSeguradoraForm.vue`; modificar `utils/pagina.js:37-90`.

**Interfaces.**
- `pagina.js`: `export const ehContratado = agente => Boolean(agente?.contratado)`; `GAVETA.CONTRATADO = 'contratado'`;
  `podeMudarConversando` falso para contratado; `gavetasPermitidas` para contratado com quem gerencia:
  `[GAVETA.CONTRATADO, GAVETA.ONDE, GAVETA.TESTAR, GAVETA.SABE, GAVETA.FOTO, GAVETA.VOLTAR]` (Saber só leitura, sem
  enviar material); quem só vê: `[GAVETA.TESTAR, GAVETA.SABE]`. `gavetaDaUrl` aceita `contratado`.
- `AcessoDaSeguradoraForm`: login + senha (`type="password"`, `autocomplete="off"`), botão Conferir; mostra
  `login_dica` e estado; senha limpa do estado depois do envio; estado `ok` mostra **Escolher a caixa** → gaveta ONDE.
  Com `so_cotacao` avisa que o login só cota.

- [ ] Spec que falha: `specs/contratados/regrasDoContratado.spec.js` (as listas exatas acima; `podeMudarConversando`
  falso; a Lia e o agente comum com as mesmas listas de antes — comparar com o resultado atual de `gavetasPermitidas`
  para eles) e `specs/contratados/AcessoDaSeguradoraForm.spec.js` (POST com corpo exato; depois do POST nenhum
  `input` tem a senha; estados `recusado` e `so_cotacao` mostram os textos do i18n).
- [ ] Rodar vitest (também `specs/pagina`), implementar, eslint. Commits: teste / `feat(seguro-viagem): gaveta do contratado`.

### Tarefa 29 — Rota, i18n do painel e Guia

**Arquivos.** Modificar `autonomia.routes.js` (rota `autonomia_contratado_modelo`, path
`accounts/:accountId/agents/prontos/:modelo`, `meta: { ...agentsManageMeta, featureFlag:
FEATURE_FLAGS.AGENTE_SEGURO_VIAGEM_UNIVERSAL }`, `beforeEnter: [ensureAutonomiaEnabled,
comFlags(FEATURE_FLAGS.AGENTE_SEGURO_VIAGEM_UNIVERSAL)]`, **antes** de `autonomia_agent_panel` para `prontos` não
casar como `agentId`); `i18n/locale/{en,pt_BR}/agents.json` (namespace `AGENTS.CONTRATADOS.*`); `lib/operator_guide/porques.md`.

- [ ] Spec que falha: `autonomia.routes.spec.js` ganha `rota('autonomia_contratado_modelo')` com a flag e a ordem.
- [ ] i18n: en e pt_BR juntos (catálogo do fork); `pnpm i18n:fork:check`.
- [ ] `porques.md`: bloco `### contratar_agente_seguro_viagem_universal` com `titulo`, `rota:
  autonomia_contratado_modelo`, `intent` (como contrato o agente de seguro viagem; onde ponho o login da Universal;
  por que não consigo mudar a instrução dele), `onde_fica`, `pre_requisitos` (flag e prontas ligadas; login do portal
  da Universal), `passos` (Contratar → 3 campos → login e senha → Escolher a caixa), `gotchas` (instrução e base são
  mantidas pela Autonom.ia; não dá para incluir ferramenta; login que só cota não gera proposta).
  `pnpm guia:build` e enviar o gerado; `pnpm guia:check`.
- [ ] Rodar `pnpm test app/javascript/dashboard/routes/dashboard/autonomia` e `pnpm test app/javascript/dashboard/modules`.
- [ ] Commits: teste / `feat(seguro-viagem): rota da página do modelo e Guia`.

### Tarefa 30 — Validação, revisão e teste pago

- [ ] Local: rubocop em todos os `.rb` tocados; `pnpm eslint` nos `.vue`/`.js`; `pnpm test` das pastas tocadas e de
  `modules`; `pnpm i18n:fork:check`; `pnpm guia:check`. Ler a saída inteira de cada um.
- [ ] Prints finais da tela implementada (1440 e 390) comparados com o mockup aprovado; `diretor-de-arte` de novo.
- [ ] Abrir o PR com `Refs #3211` (não `Closes`: a jornada paga e o piloto ficam depois). CI verde lida linha a linha.
- [ ] Revisor `agentes-ia-refactor-reviewer` no diff inteiro, com os cinco itens do Foco da revisão.
- [ ] Teste pago na conta piloto, **com OK do Rodrigo e teto de US$ 10**: viajante "QI 60" do "oi" ao link, cotação e
  proposta reais na Universal (uma proposta de teste fica registrada, sem pagamento). Confirma `FormaPagamento: 8` e o
  link. Se o `8` falhar, a decisão volta ao Rodrigo (boleto ou faturado).
- [ ] Merge e deploy pela gestora da fila; testador depois do deploy; limpeza (branch, worktree, snapshot).

---

## Decisões que o desenho não fixava (tomadas neste plano; conferir no review)

1. Ferramentas prontas do agente: `pronta_cep` e `pronta_cpf` (as que a instrução lista). `pronta_cidades`, citada no
   desenho como "a confirmar", fica fora.
2. O cartão só aparece quando a conta tem também as flags das prontas (`agente_ferramentas_prontas` e `_consultas`):
   sem elas o `Incluir` recusa e o agente ficaria com uma rodada de ferramenta só, sem CEP nem CPF.
3. O PDF sai **na hora da ferramenta**, antes do texto da resposta, por uma mensagem própria com token por cotação
   (não pelo caminho assíncrono da Lia nem pelos cartões do turno). Se o turno for superado, o PDF já saiu.
4. Rua, bairro, cidade e UF da proposta vêm do cache da pronta de CEP (ou da própria pronta rodada no servidor).
5. `detalhes_da_cotacao` recebe `codigos_dos_planos` (lista; vazia = todos).
6. Plano com viajante fora da idade do produto sai da lista; se nenhum sobra, recusa `idade_fora_do_limite`.
7. Cotação de outro dia (fuso da conta) é recusada na proposta com `recotar`.
8. Idempotência da proposta por `(cotação, plano, CPFs)` sob lock da linha; `proposta` guarda só ids, link e valor.
9. `pedido_invalido` repassa ao modelo a mensagem da Universal cortada em 200 caracteres (nunca ao log).
10. Testar (sem conversa) não cota nem propõe: recusa `cotacao_sem_conversa`.
11. Marca protegida contra save com cópia velha (desenho de `MarcaDoModeloPronto`); opções de conversa continuam
    editáveis pela tela como em qualquer agente.
12. Reemissão da base por cron de hora em hora (só re-embebe quem está com versão velha); custo na chave de IA da conta.
13. `DadosIncompletos` é subclasse de `EscolhasIncompletas`, para as portas que já tratam a da Lia tratarem esta.
14. F1 e a promessa da IA do CRM tratam o contratado como a Lia (Tarefa 8): **perguntar ao Rodrigo**.

## O que não deu para determinar pelo código

- Os `idBeneficio` de despesas médicas, bagagem e cancelamento (as fontes só têm a forma, não os valores; o fluxo
  externo filtra por texto) — Tarefa 0.
- Se `BR` existe em `/v1/destinos` (viagem nacional) e se o `FormaPagamento: 8` vale para o emissor de teste.
- O login da Universal para o teste (pergunta aberta do desenho).
- ~~Os nomes das chaves de `config` do PR 1.~~ Fixados (seção "Interfaces que vêm do PR 1").

---

## Autorrevisão

- **Cobertura do desenho.** §6.1 → T6, T7, T9, T20; §6.2 → T3, T12, T21, T22; §6.3 → T10, T11; §6.4 → T13;
  §6.4.1 → T15; §6.4.2 → T14; §6.5 → T16, T17; §6.6 → T18; §6.7 → T1, T20; §6.8 → T24-T29; §6.9 → T23;
  §7 → T30; §11 (acesso por agente, base travada, edição dos 3 campos, várias cópias) → T2, T9, T20, T21. §8 fica no PR 1.
- **Anti-objetivos.** Preço do modelo → T17 (R3). Credencial em tela/log/API → T3, T10, T21 (R5). Erro de login ao
  viajante → T18. Campo interno ao viajante → T13, T15 (R2). Conversa robótica → opções do PR 1 ligadas em T20.
  Corretor alterando a instrução → T7, T9 (instrução, tipo, modo, marca, ferramentas, base).
- **Contrato com a instrução.** Nomes das ferramentas e parâmetros conferidos com `instrucao.md` 1.2, 7.5 e 7.14:
  `cotar_seguro_viagem(destinos, data_saida, data_retorno, idades, motivo)`, `detalhes_da_cotacao`,
  `gerar_proposta_seguro_viagem(codigo_do_plano, titular, demais_viajantes, contato_de_emergencia)`, `pronta_cep`,
  `pronta_cpf`. A recusa `recotar` e o "uma nova tentativa" da instrução batem com T17 e T18.
- **Lia.** Nenhum arquivo de `insurance/quote_agent/` muda; o `||` novo vem antes e devolve nil para a Lia; T7 prova
  instrução, ferramentas, rodadas e predicados iguais.
- **Guardas do repositório.** Exclusão da conta (T5), texto ao cliente (T14), recursos da automação (T21), formatos
  (T21), `escreve?` declarado (T19), rotas e `modules` no vitest (T29).
- **Sem regex** em código novo: substituição por `String#index`, fatiamento por `start_with?`, sigla por `each_char`,
  e-mail por `split`, link por `URI`.
- **Repo público.** Nomes fictícios ("Bia", "Corretora Exemplo", "corretor.teste"); fixtures anonimizadas; nenhuma
  conta, cliente ou número de conta citado.
