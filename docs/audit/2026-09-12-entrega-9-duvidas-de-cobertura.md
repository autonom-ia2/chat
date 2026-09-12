# Entrega 9 — dúvidas de cobertura durante a cotação (#397, Part of #291)

Data: 2026-09-12
Branch: `feat/entrega-9-duvidas-de-cobertura` (de `origin/main` 1f49bba324)
Commit da entrega: `52dc223949`
Escopo: instrução do principal (§7.1) + duas specs de guarda. **Nenhuma mudança de comportamento em
código de produção** — a ferramenta já existia, já estava ligada e não foi tocada.

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
instrução nem provado por nenhuma spec. O que esta entrega acrescenta é **texto e prova**, não
capacidade.

## 2. O que mudou

### 2.1 `instrucoes/principal.md` — seção nova §7.1 (14 linhas)

Inserida ao fim da §7 ("Quando a mensagem traz várias coisas de uma vez"), linhas 152-165. Diz, em
três parágrafos:

1. **"Dúvida sozinha não é pedido de cotação."** Mensagem que é só pergunta de cobertura, com os
   preços correndo: `não acione o especialista e não mande cotar de novo` — consulta
   `consultar_condicoes_gerais`, responde com a cláusula, e diz que **a cotação continua correndo**.
2. Pedir de novo não adianta (mesmos dados); só volta ao especialista quando o cliente **muda um dado
   ou pede outra configuração**.
3. **"Se ela não disse de qual seguradora"**: usa a que o cliente citou; se não citou nenhuma,
   pergunta de qual das que estão sendo cotadas — a consulta é por seguradora.

§5 e §10 **não foram tocadas** (entrega 8 trabalha nelas em paralelo). Nenhuma variável `$…` nova.

### 2.2 Specs novas

| Arquivo | O que guarda |
| --- | --- |
| `spec/services/autonomia/insurance/quote_agent/builder_instrucao_do_principal_promessas_spec.rb` | instrução ↔ ferramenta do principal (12 exemplos) |
| `spec/services/autonomia/agents/answerer_duvida_durante_cotacao_spec.rb` | a cena real no `Answerer`, com a cotação `running` (7 exemplos) |

## 3. Decisões

**D1 — sem assinatura md5 de `principal.md`.** A spec do especialista (entrega 3) assina
`especialista_auto.md` por md5, para o texto não mudar sem revisão da tabela de promessas. Aqui
**não** se assinou: outra pessoa edita §5/§10 do mesmo arquivo nesta janela (entrega 8), e a
assinatura viraria uma falha cruzada sem relação com o conteúdo. A guarda é a tabela de
frases-âncora; recomendação: quando a entrega 8 fechar, avaliar assinar o arquivo numa entrega
posterior.

**D2 — "a cotação continua correndo" é sustentada por `async?` falso, não por conduta do modelo.**
Só ferramenta assíncrona abre execução (`Bound#accept_async` → `ToolRun.abrir_ou_repetida`), e é a
abertura que supersedia a execução viva da conversa. Uma ferramenta síncrona não escreve em
`autonomia_agent_tool_runs`. A frase da instrução, portanto, descreve o que o código já garante — e
a guarda amarra a frase a esse invariante (`!CG.async? && Cotacao.async?`).

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

| # | Termo | Guarda |
| --- | --- | --- |
| 1 | Dúvida respondida com a cláusula, dizendo de qual seguradora é | `answerer_duvida_durante_cotacao_spec` «consulta as condições gerais e devolve ao modelo o trecho e a seguradora» (requisição feita com `insurer_name` = o que o cliente citou; saída contém `Porto Seguro` + o trecho) |
| 2 | A cotação em andamento não é interrompida | mesmo spec, «a execução continua running, sem linha nova, sem superseded e sem chamar o portal» + «a cotação segue correndo mesmo quando a dúvida não teve resposta» |
| 3 | Habilitada nos agentes que já existem | `builder_instrucao_do_principal_promessas_spec` §"a ferramenta chega ao agente sem conexão com o portal": `available_for?` true sem conexão (contraste: `InsuranceQuote.available_for?` false), entra em `Bound.for_agent`, nenhum especialista a reserva, sai do prompt com o módulo desligado |
| 4 | Sem cláusula, o agente diz que não encontrou | mesmo spec de integração, «não repassa a prosa plausível e manda confirmar com um especialista» (`insufficient_context`/`grounded: false`) |
| 5 | A resposta não duplica nem reinicia a cotação | integração: `runs.count == 1`, `where(slug: 'cotar_seguro').count == 1`, zero `superseded`, `quote_start` não recebido, `delivery.runs` vazio, e a execução viva continua sendo a da mensagem 77 |
| — | A instrução não promete o que o código não tem | tabela `PROMESSAS` da §7.1 (4 frases-âncora) + «proíbe as duas coisas» + «todo slug do catálogo citado está em `TOOLS_DO_PRINCIPAL`» |

## 5. Comandos e resultados

Banco de teste próprio: `chatwoot_test_e9` (criado com `db:create db:schema:load`, exit 0).

| Comando | Resultado |
| --- | --- |
| `rspec builder_instrucao_do_principal_promessas_spec.rb` | 12 exemplos, 0 falhas |
| `rspec answerer_duvida_durante_cotacao_spec.rb` | 7 exemplos, 0 falhas |
| `rspec <as duas novas> spec/services/autonomia/insurance/quote_agent spec/services/autonomia/agents` | **720 exemplos, 0 falhas, 0 erros fora de exemplos**, exit 0, 22,0 s |
| `rubocop <as duas specs novas>` | **0 ofensas** (2 arquivos) |

Todos com `POSTGRES_DATABASE=chatwoot_test_e9`, saída JSON lida pelo `summary_line` +
`errors_outside_of_examples_count`.

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
   o agente diz que vai confirmar com um especialista, sem inventar cláusula.

## 8. Riscos e pendências

- **Teto de 120 s do turno** com CG (45 s) + especialista no mesmo turno: não medido aqui, só na
  prova real (item 8 acima). Nada nesta entrega mudou o caminho síncrono.
- **`principal.md` sem assinatura md5** (D1): o texto pode mudar sem que a tabela de promessas seja
  revista, desde que as 4 frases-âncora fiquem. Reavaliar depois da entrega 8.
- **A frase ao cliente não se prova por máquina.** As specs provam o que chega ao modelo e o que fica
  no banco; a conduta do modelo é a prova real.
- Nenhum segredo, prompt completo ou dado de cliente foi registrado aqui.
