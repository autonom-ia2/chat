# Entrega 9 — dúvidas de cobertura durante a cotação (#397, Part of #291)

Data: 2026-09-12
Branch: `feat/entrega-9-duvidas-de-cobertura` (de `origin/main` 1f49bba324)
Commits: `52dc223949` (entrega) · `c65553865f` (rodada de correção — ver §9)
Escopo: instrução do principal (§7.1) + duas specs de guarda + **uma mudança de comportamento em
código de produção**, vinda da rodada de correção: `web_search` sai do catálogo do agente de cotação
(§2.3). A ferramenta de condições gerais já existia, já estava ligada e não foi tocada.

## 1. O fato que originou a entrega: a ferramenta já estava ligada

O plano do Agente de Cotação dizia que `consultar_condicoes_gerais` "não está ligada nesta jornada".
**É falso.** O estado medido em `origin/main` 1f49bba324:

| Onde | Estado |
| --- | --- |
| `app/services/autonomia/insurance/quote_agent/builder.rb:23` | `TOOLS_DO_PRINCIPAL = %w[consultar_produtos_cotacao consultar_condicoes_gerais]` |
| `app/services/autonomia/agents/tools/registry.rb:17` | `Native::InsuranceGeneralConditions` no catálogo |
| `Builder#criar_agente` | grava `native_tool_slugs = TODAS_AS_TOOLS` (principal + especialista) |
| `TOOLS_DO_ESPECIALISTA` | **não** contém a CG — nenhum especialista a reserva, logo ela é visível ao principal (`Answerer#enabled_agent_tools`) |
| `InsuranceGeneralConditions.available_for?` | só exige o módulo de seguros; **não** exige conexão AGGER |
| Agente 24 (produção) | `native_tool_slugs` com a CG — auditoria da entrega 2 |
| `principal.md` §2, §5, §13 | já mandavam consultar as CGs e proibiam responder de memória |

A ferramenta é **síncrona** (`async?` falso), não toca em `autonomia_agent_tool_runs` e não fala com
o portal. Nada nela podia interromper uma cotação `running` — mas isso não estava escrito na
instrução nem provado por nenhuma spec. O que esta entrega acrescenta é **texto e prova** — mais
**uma capacidade RETIRADA** na rodada de correção (§2.3): a busca web, que competia com a cláusula.

## 2. O que mudou

### 2.1 `instrucoes/principal.md` — seção nova §7.1 (17 linhas)

Inserida ao fim da §7 ("Quando a mensagem traz várias coisas de uma vez"). **Intervalo real no
arquivo: título na linha 152, corpo até a 167** (a 168 é a linha em branco antes do `## 8`; o texto
original desta auditoria dizia "152-165", que era o intervalo antes da rodada de correção §9). Diz,
em três parágrafos:

1. **"Dúvida sozinha não é pedido de cotação."** Mensagem que é só pergunta de cobertura, com os
   preços correndo: `não acione o especialista e não mande cotar de novo` — consulta
   `consultar_condicoes_gerais`, responde com a cláusula, e diz que **a cotação continua correndo**.
   Ressalva da §9: **se escalar, não prometa isso** — com responsável na conversa a entrega assíncrona
   vira NOTA PRIVADA (`tools/async_publisher.rb`, `private: conversation.assignee_id.present?`), e
   quem fala com o cliente passa a ser a pessoa.
2. Pedir de novo não adianta (mesmos dados); **enquanto a cotação corre**, só volta ao especialista
   quando o cliente **muda um dado ou pede outra configuração**. O "enquanto a cotação corre" é da
   §9: sem ele a frase contradizia a §5, que manda voltar ao especialista quando faltam dados.
3. **"Se ela não disse de qual seguradora"**: usa a que o cliente citou; se não citou nenhuma,
   pergunta o nome **sem listar seguradoras** — o principal não tem a lista das que estão sendo
   cotadas (e o aceite da cotação proíbe nomear seguradora: `insurance_quote/declaracao.rb`, `ACEITA`);
   o que a corretora atende sai de `consultar_produtos_cotacao`. A consulta é por seguradora.

§5 e §10 **não foram tocadas** (entrega 8 trabalha nelas em paralelo). Nenhuma variável `$…` nova.

### 2.2 Specs novas

| Arquivo | O que guarda | Exemplos |
| --- | --- | --- |
| `spec/services/autonomia/insurance/quote_agent/builder_instrucao_do_principal_promessas_spec.rb` | instrução ↔ ferramenta do principal, e a assinatura da §7.1 | 12 → **15** |
| `spec/services/autonomia/agents/answerer_duvida_durante_cotacao_spec.rb` | a cena real no `Answerer`, com a cotação `running` e com ela `pending` | 7 → **10** |

### 2.3 `agents/answerer.rb` — `web_search` fora do agente de cotação (rodada de correção)

Única mudança de comportamento em código de produção desta entrega, e ela nasceu do termo 4 (§9,
achado I3). `Answerer#answer_tools` concatenava `Crm::Ai::WebSearch.tools` para todo agente
(`allow_web_search` default `true`, e o `Operate::Responder` não passava `false`). A instrução manda
responder cobertura pela cláusula ou não responder; com a busca nativa no catálogo havia uma terceira
fonte para a mesma pergunta, sem cláusula e sem seguradora. Agora:

```ruby
def web_search_permitida?
  @allow_web_search && @agent.agent_type != 'insurance_quote'
end
```

No `Answerer` e não no `Responder`: a guarda tem de valer no atendimento, no Testar e no copiloto
(o Testar mostra o mesmo agente da produção), e tem de não tocar em nenhum outro tipo de agente —
provado pelos dois lados (o agente de cotação sem `web_search`, um agente `custom` da mesma conta
com `web_search`).

## 3. Decisões

**D1 — assinatura md5 do BLOCO da §7.1, não do arquivo (revista na §9).** A decisão original era não
assinar nada: a spec do especialista (entrega 3) assina `especialista_auto.md` inteiro, e aqui outra
pessoa edita §5/§10 do mesmo arquivo nesta janela (entrega 8) — a assinatura do arquivo viraria falha
cruzada. A rodada de correção mostrou que sem assinatura nenhuma a guarda é **cega à regra
invertida** (§9, achado I2). Decisão nova: assinar **só o bloco da §7.1**, extraído por
`texto[/### 7\.1.*?(?=\n## \d)/m]`, com a presença do bloco afirmada antes de cada asserção. Assim a
entrega 8 pode mexer em §5/§10 sem cruzar com esta guarda, e a §7.1 não muda sem revisão da tabela
`PROMESSAS`. **md5 atual do bloco: `197f319bce3a110da98823bb7d359dbf`.**

**D2 — "a cotação continua correndo" tem um invariante de código ATRÁS, mas não é ele que garante a
frase inteira (qualificada na §9).** O que é invariante: **executar somente a consulta às condições
gerais preserva a execução viva**. Só ferramenta assíncrona abre execução (`Bound#accept_async` →
`ToolRun.abrir_ou_repetida`), e é a abertura que supersedia a execução viva da conversa; a consulta é
síncrona e não escreve em `autonomia_agent_tool_runs`. É isso que a guarda `!CG.async? &&
COTACAO.async?` e a spec de integração amarram. O que **não** é invariante: que o modelo chame
somente a consulta. Se ele chamar também o especialista no mesmo turno, a cotação é reaberta e a
frase da instrução vira mentira — **escolher só a consulta é conduta, e se prova na conversa real**
(§7), não por máquina.

**D3 — a spec de integração coube no `Answerer`.** Não foi preciso descer ao `Bound#execute` +
`Registry`: o agente é o que o `Builder` cria (principal + especialista de auto), o catálogo é o do
turno real (com o especialista escondendo `cotar_seguro` e `consultar_placa`), e só o **modelo** é
dublado — ele devolve a `function_call` da CG, que é justamente a decisão que a §7.1 pede. A
ferramenta executada é a de verdade, contra `POST https://agent.autonomia.site/query` dublado por
WebMock.

**D4 — o agente da spec de integração roda com `with_knowledge = false`.** O `Builder` liga a base de
conhecimento; deixá-la ligada faria o `Retriever` pedir embedding a cada exemplo, o que não é o
assunto da entrega e tira o hermetismo. Único desvio do agente real, e está comentado na spec.

**D5 — o que a spec afirma é o que o código garante.** A saída da ferramenta (o que chega ao modelo)
e o estado do banco. A frase final ao cliente é do modelo e não se prova por máquina — a prova real
(§7) é que fecha isso.

## 4. Termos de aceite → guarda

| # | Termo | Estado | Guarda |
| --- | --- | --- | --- |
| 1 | Dúvida respondida com a cláusula, dizendo de qual seguradora é | **parcial** — a resposta ao cliente é conduta do modelo; fecha na prova real (§7) | `answerer_duvida_durante_cotacao_spec` §"o que chega ao modelo — contrato ferramenta→modelo": requisição feita com `insurer_name` = o que o cliente citou; a saída da ferramenta contém `Porto Seguro` + o trecho. O modelo é dublado e responde "cobre reboque" independentemente disso — o que a máquina prova é o INSUMO |
| 2 | A cotação em andamento não é interrompida | provado (executando só a consulta) | mesmo spec, «a execução running continua running, sem linha nova, sem superseded e sem chamar o portal», «a execução aceita e ainda não despachada continua pending» e «a cotação segue correndo mesmo quando a dúvida não teve resposta». Que o modelo chame só a consulta é conduta (D2) |
| 3 | Habilitada nos agentes que já existem | provado no código; **rollout é premissa** | `builder_instrucao_do_principal_promessas_spec` §"a ferramenta chega ao agente sem conexão com o portal": `available_for?` true sem conexão (contraste: `InsuranceQuote.available_for?` false), entra em `Bound.for_agent`, nenhum especialista a reserva, sai do prompt com o módulo desligado. **Negativo:** «agente já criado sem o slug em `native_tool_slugs` não recebe a ferramenta» — `Registry.for_agent` filtra pela lista gravada no nascimento, e **qualquer agente antigo sem o slug exige rollout**; o agente 24 já tem (auditoria da entrega 2, linha 144) |
| 4 | Sem cláusula, o agente diz que não encontrou | **parcial** — a resposta ao cliente é conduta do modelo; fecha na prova real (§7, item 9) | integração, «não repassa a prosa plausível e manda confirmar com um especialista» (`insufficient_context`/`grounded: false`) prova o que a FERRAMENTA entrega ao modelo. Somado a isso, a fonte concorrente foi removida: «o turno da dúvida não tem web_search no catálogo» (§2.3) |
| 5 | A resposta não duplica nem reinicia a cotação | provado (executando só a consulta) | integração: `runs.count == 1`, `where(slug: 'cotar_seguro').count == 1`, zero `superseded`, `quote_start` não recebido, contexto de entrega do turno sem execução aceita, e a execução viva continua sendo a da mensagem 77 |
| — | A instrução não promete o que o código não tem | provado | tabela `PROMESSAS` da §7.1 (4 frases-âncora) + «proíbe as duas coisas» + «todo slug do catálogo citado está em `TOOLS_DO_PRINCIPAL`» + **assinatura md5 do bloco da §7.1** (D1), que é o que pega texto ACRESCENTADO entre as âncoras |

## 5. Comandos e resultados

Banco de teste próprio: `chatwoot_test_e9` (criado com `db:create db:schema:load`, exit 0).

| Comando | Resultado (entrega) | Resultado (rodada de correção) |
| --- | --- | --- |
| `rspec <as duas specs novas>` | 19 exemplos, 0 falhas | **25 exemplos, 0 falhas**, exit 0 |
| `rspec <as duas> spec/services/autonomia/insurance/quote_agent spec/services/autonomia/agents` | 720 exemplos, 0 falhas | **726 exemplos, 0 falhas, 0 erros fora de exemplos**, exit 0 |
| `rspec spec/services/autonomia spec/services/crm/ai` (regressão do `Answerer`) | — | **1074 exemplos, 0 falhas, 3 pending, 0 erros fora**, exit 0 |
| `rubocop <arquivos tocados>` | 0 ofensas (2 arquivos) | **0 ofensas** (3 arquivos: `answerer.rb` + as duas specs) |

Todos com `POSTGRES_DATABASE=chatwoot_test_e9`, saída JSON lida pelo `summary_line` +
`errors_outside_of_examples_count`. Não existe `spec/services/autonomia/operate`: o Responder mora em
`spec/services/autonomia/agents/operate`, e entrou nas duas rodadas amplas acima.

## 6. Mutações

Cada mutação foi aplicada, medida e desfeita; o md5 de cada arquivo voltou ao original
(`principal.md` 960a4957dc51e31e4c44c8d24312c558, `builder.rb` 92fa0ade0b8e68e94e6a062b6603e219,
`insurance_general_conditions.rb` 805545009701e5795ce5b7021a49aa3b,
`answerer_duvida_durante_cotacao_spec.rb` 7475f071c1b5516e80e273e4b13b386f).

| # | Mutação | Resultado | Exemplos que caíram |
| --- | --- | --- | --- |
| M1 | Apagar a frase «Dúvida sozinha não é pedido de cotação.» da §7.1 | 11 passaram, **1 falhou** | «Dúvida sozinha não é pedido de cotação» tem o que a sustenta |
| M2 | Tirar `consultar_condicoes_gerais` de `TOOLS_DO_PRINCIPAL` | 19 exemplos, **6 falharam** | a promessa «Dúvida sozinha…»; «todo slug do catálogo citado está em TOOLS_DO_PRINCIPAL»; «entra no catálogo do turno»; integração: termo 1 (requisição não feita), a ferramenta fora do catálogo do turno, e termo 4 (`{"error":"tool_not_available"}` no lugar da recusa da CG) |
| M3 | `available_for?` da CG passar a exigir conexão `ready?` | 32 exemplos, **3 falharam** | «available_for? é verdadeiro com o módulo ligado e sem conexão AGGER»; «entra no catálogo do turno…»; e o exemplo pré-existente `insurance_general_conditions_spec` «is offered whenever the account has the insurance module on» |
| M4 | Na spec de integração, a CG abrir um `ToolRun` de `cotar_seguro` **e** chamar `quote_start` por dentro de um stub | 7 exemplos, **1 falhou** | «a execução continua running…» — parou no primeiro assert (`expected "running", got "superseded"`) |
| M4b | A mesma, só chamando `quote_start` (sem abrir `ToolRun`) — para isolar o espião do portal | 7 exemplos, **1 falhou** | «a execução continua running…» — `quote_start expected 0 times, received 1 time` |

M4 foi partido em dois porque o primeiro assert do exemplo interrompe os seguintes: M4 prova que a
asserção de estado pega, M4b prova que a asserção do portal pega.

### 6.1 Mutações da rodada de correção (12/09)

Mesma disciplina: aplicar, medir, desfazer com `git checkout --`, conferir o md5 de volta. Baseline
depois do commit `c65553865f` — `principal.md` `0ff28ce0e768fe500cb1ee3d6d123fc6`, `answerer.rb`
`d3598254e30c349bb90e9177970919cc`, `builder_instrucao_do_principal_promessas_spec.rb`
`a814891a3d940f858f2b2da34fd79beb`, `answerer_duvida_durante_cotacao_spec.rb`
`f064a9e95b86d6806407de6e2bbca290`, `registry.rb` `1d49e4eef618516a3c5578fab8070552`.

| # | Mutação | Resultado | Exemplos que caíram |
| --- | --- | --- | --- |
| MD | **Regra invertida na §7.1, mantendo as quatro âncoras**: acrescentar "Na dúvida, acione o especialista de novo e mande cotar outra vez." | 15 exemplos, **2 falharam** | «está no arquivo e é extraída inteira» e «mudou? revise PROMESSAS e assine aqui». Antes desta rodada a mesma mutação passava 35/35 |
| ME | Renumerar `## 8` para `## 9` | 15 exemplos, **0 falharam** — e está certo | A âncora é `(?=\n## \d)`: renumerar o capítulo seguinte não muda o bloco da §7.1, o md5 é o mesmo, e não há passagem em vão. Quem prova a âncora são ME2 e ME3 |
| ME2 | Rebaixar `## 8` para `### 8` (a âncora deixa de casar ali e o bloco engole o capítulo seguinte) | 15 exemplos, **2 falharam** | «está no arquivo e é extraída inteira», «mudou? revise PROMESSAS…» |
| ME3 | Apagar o **título** `### 7.1` (o corpo fica) — `secao` vira `nil` | 15 exemplos, **3 falharam** | as duas acima **e** «não introduz variável para substituir» — que é exatamente o exemplo que passava em vão com o `.to_s` da versão anterior |
| MW | Reativar `web_search` para o agente de cotação (`if @allow_web_search`) | 10 exemplos, **1 falhou** | «o turno da dúvida não tem web_search no catálogo…» |
| MW2 | Desligar `web_search` para **todo** agente (`if false`) | 10 exemplos, **1 falhou** | «um agente comum da mesma conta continua recebendo web_search» — o contraste não é decorativo |
| MP | A consulta às condições gerais abrindo um `ToolRun` de `cotar_seguro` **por dentro do turno** (no momento da chamada HTTP dublada) | 10 exemplos, **4 falharam** | «a execução running continua running…» (`got "superseded"`), **«a execução aceita e ainda não despachada continua pending»** (`got "superseded"`), «a execução viva continua sendo a que a mensagem anterior abriu», «a cotação segue correndo mesmo quando a dúvida não teve resposta» |
| MR | `Registry.for_agent` ignorar `native_tool_slugs` (oferecer tudo) | 15 exemplos, **1 falhou** | «agente já criado sem o slug em `native_tool_slugs` não recebe a ferramenta» |

## 7. Roteiro da prova real (a fazer, em conversa real)

A conversa real é feita por outra pessoa. Roteiro:

1. **Disparar a cotação.** Numa conversa de WhatsApp com o agente de cotação (conta com o módulo
   ligado e conexão AGGER `ready`), levar até o disparo — o agente responde a frase de aceite e a
   execução aparece em `autonomia_agent_tool_runs` como `running`.
2. **Anotar o estado ANTES**, ainda com a cotação correndo:
   ```sql
   SELECT id, slug, status, origin_message_id, handle->>'autonomia_pedido' AS pedido, updated_at
     FROM autonomia_agent_tool_runs
    WHERE conversation_id = <ID>
    ORDER BY id;
   ```
3. **Mandar a dúvida sozinha**, sem nenhum dado junto: *"a assistência 24h da Porto cobre guincho?"*
4. **Conferir a resposta ao cliente:** traz a cláusula, **nomeia a seguradora** (Porto Seguro), não
   promete cobertura genérica, e diz que a cotação continua. Não pode aparecer frase de aceite de
   cotação nova ("já estou consultando…").
5. **Conferir o banco DEPOIS**, com a mesma consulta: a tabela tem de estar **inalterada** —
   mesmo `id`, `status` ainda `running`, mesmo `origin_message_id`, nenhuma linha nova de
   `cotar_seguro`, nenhuma `superseded`.
6. **Conferir o portal do corretor:** nenhuma cotação nova aberta no minuto da dúvida.
7. **Conferir que os preços continuam chegando** depois da resposta da dúvida (a execução conclui
   normalmente e publica).
8. **Medir o tempo do turno** (risco anotado na issue): CG tem teto de 45 s e o turno, 120 s. Anotar
   a latência do turno da dúvida. Se a dúvida vier junto com dado (CG + especialista no mesmo turno),
   medir de novo — é o caso que pode encostar no teto, e turno morto descarta execução `pending`.
9. **Caso negativo:** perguntar algo que a base não cobre (ex.: cobertura inexistente) e conferir que
   o agente diz que vai confirmar com um especialista, sem inventar cláusula. **É este item que fecha
   os termos 1 e 4** (§4): com o modelo dublado, as specs provam o insumo, não a frase.
10. **Dúvida + dado na mesma mensagem** (o caso que a §7 já cobria): conferir que o turno chama a
    consulta **e** o especialista, e que aí a cotação é reaberta de propósito. É o contraponto da D2 —
    o invariante vale para quem executa só a consulta.
11. **Se a conversa tiver responsável** (escalada da §10): conferir que o preço chega como NOTA
    PRIVADA e que a Lia não prometeu ao cliente que os preços chegariam ali (§2.1, item 1).

## 8. Riscos e pendências

- **Teto de 120 s do turno** com CG (45 s) + especialista no mesmo turno: não medido aqui, só na
  prova real (item 8 acima). Nada nesta entrega mudou o caminho síncrono.
- **A §7.1 está assinada; o resto do `principal.md` não.** §5, §10 e os demais capítulos continuam
  sem md5 (a entrega 8 trabalha neles). Quando a entrega 8 fechar, avaliar assinar o arquivo inteiro
  e aposentar a assinatura de bloco.
- **Rollout do termo 3.** Agente antigo cuja `native_tool_slugs` não tem `consultar_condicoes_gerais`
  não recebe a ferramenta, e nada no código conserta isso — o agente 24 já tem; qualquer outro
  precisa de rollout (§4, termo 3).
- **A frase ao cliente não se prova por máquina.** As specs provam o que chega ao modelo e o que fica
  no banco; a conduta do modelo é a prova real.
- **A descrição da PR #398 está desatualizada** depois desta rodada (diz que o `principal.md` não foi
  assinado por md5 e não menciona a `web_search`). Atualizar junto com o push.
- Nenhum segredo, prompt completo ou dado de cliente foi registrado aqui.

## 9. Rodada de correção — verificador cego + Codex (12/09/2026)

Commit `c65553865f`. Nenhum achado foi adiado.

### 9.1 O que estava errado

| # | Achado | Por que era defeito | O que mudou |
| --- | --- | --- | --- |
| I1 | Faltava o caso `pending` | A cotação ACEITA e não despachada é o estado frágil: `ToolRun.open!` supersedia toda execução ativa, `pending` inclusive, e `pending` órfã nem conta como duplicada. Só o `running` estava provado | Exemplo novo na spec de integração (uma linha, `pending` no fim, nenhuma `superseded`, nenhum `quote_start`) |
| I2 | Guarda textual cega à regra invertida | Mantendo as quatro âncoras e acrescentando "Na dúvida, acione o especialista de novo e mande cotar outra vez", 35/35 passaram. E o exemplo da variável fazia `[regex].to_s`: com a seção ausente passava em vão | Assinatura md5 **do bloco da §7.1** (`197f319bce3a110da98823bb7d359dbf`) + presença do bloco afirmada em cada exemplo. Mutações MD, ME, ME2, ME3 |
| I3 | `web_search` no catálogo do principal | Terceira fonte para a mesma pergunta de cobertura, sem cláusula e sem seguradora — o termo 4 deixava de ser cumprível | `Answerer#web_search_permitida?` (§2.3) + dois exemplos (ausência no agente de cotação, presença num agente comum). Mutações MW e MW2 |
| m1 | «o turno da dúvida não aceita nenhuma execução» só olhava `Delivery#runs` | A mutação que abria `ToolRun` por fora do `Delivery` passava nele — o nome prometia banco e o exemplo lia memória | Renomeado para «o contexto de entrega do turno sai sem execução aceita — nada a despachar», com o comentário dizendo o que ele NÃO vigia |
| m3 | Termo 3 sem negativo | "Habilitada nos agentes que já existem" é premissa de rollout, não consequência do código | Exemplo «agente já criado sem o slug em `native_tool_slugs` não recebe a ferramenta» (mutação MR) + a frase do rollout na §4 e na §8 |
| m4 / Codex P2 | Termos 1 e 4 anunciados como provados | O modelo é dublado e responde "cobre reboque" mesmo com `insufficient_context`: o que a máquina vê é o retorno da FERRAMENTA | `describe`/`it` renomeados para "contrato ferramenta→modelo"; §4 marca 1 e 4 como **parcial** |
| Codex P3 / m7 | "Invariante" para `!CG.async? && COTACAO.async?` | O invariante cobre EXECUTAR só a consulta, não ESCOLHER só a consulta | D2 qualificada; `describe` da integração agora diz «executar só a consulta não toca na cotação em andamento»; comentário da promessa reescrito |
| m5 | §7.1 prometia "os preços chegam aqui assim que saírem" | Com responsável na conversa a entrega vira nota privada (`async_publisher.rb`) — a promessa fica falsa depois de escalar | Frase nova na §7.1 |
| m6 | §7.1 mandava "perguntar de qual das que estão sendo cotadas" | O principal não conhece essa lista, e o aceite proíbe nomear seguradora | Pede o nome **sem listar**; a lista do que a corretora atende vem de `consultar_produtos_cotacao` |
| m8 | "Você só volta ao especialista quando ela muda um dado" | Contradizia a §5, que manda voltar quando faltam dados | "**Enquanto a cotação corre**, você só volta…" |
| — | "linhas 152-165" na §2.1 | Intervalo desatualizado | §2.1 traz o intervalo real (152-167) |

### 9.2 O que NÃO foi feito, e por quê

- **Descrição da PR #398 e texto da issue #397 não foram alterados.** Esta rodada não tem push, e a
  issue não contém a palavra "invariante" (a afirmação estava na D2 desta auditoria, já corrigida).
  A PR precisa de dois ajustes no momento do push: a ressalva do md5 deixou de valer, e a
  `web_search` é mudança de produção que a descrição não menciona.
- **Nada foi provado sobre a conduta do modelo.** Continua tudo na §7 — e a §7 ganhou os itens 10 e
  11 por causa desta rodada.
