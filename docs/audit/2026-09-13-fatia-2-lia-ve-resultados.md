# Fatia 2 do #420: a Lia vê o resultado da cotação

Data: 13/09/2026 · Branch `feat/cotacao-lia-ve-resultados` · base `origin/main` (`5742de5fcd`).

## Objetivo

Quatro coisas, e só elas:

1. a cotação **guarda o resultado por seguradora** no handle da execução, em toda consulta, como união;
2. a Lia ganha uma **ferramenta assíncrona de exibição**, `ver_resultado_da_cotacao`, que lê esse resultado
   sem ir ao portal; com preço, o código publica os itens depois da fala dela; o motivo de quem não cotou
   só chega ao modelo quando a regra do motivo libera e o pedido nomeia a seguradora;
3. o **pedido repetido** conta também a execução com resultado guardado, por união com o contador;
4. a **confirmação do fechamento** (a segunda leitura igual) roda no primeiro intervalo da progressão, e não
   no intervalo da tentativa.

Fora, de propósito: parar os lotes de preço, sinal de vida depois de 2 min, rede de segurança da lista
quando o PDF falha (fatia 3). Nada novo no Super Admin. Nada no conector.

## O que mudou, por item

### 1. O resultado por seguradora no handle

- `Insurance::ResultadoPorSeguradora.unir(guardado, ofertas)` monta uma entrada por código:
  - com preço (`QuoteOffers.cotada?`: `quoted` com valor): `nome`, `desfecho: com_preco`, `premio` só com
    `amount`, `basis` e `installments` (os campos que `PremiumText#resumo`/`#detalhe` leem e que
    `QuoteOffers#quoted` usa para ordenar);
  - `declined`, `auth_required` e `error`: `desfecho: sem_proposta`; `motivo: { kind, text }` só quando
    `Insurance::MotivoDaRecusa.permitido` libera o texto e a oferta **não** é `auth_required`;
  - qualquer outro status, e `quoted` sem valor: `desfecho: aguardando`.
- A união fica com a entrada de desfecho maior (`com_preco` > `sem_proposta` > `aguardando`); no empate, a
  guardada. Código que a leitura não listou continua.
- `InsuranceQuote::Resultado#marcas_da_leitura` grava a chave `resultado_por_seguradora` junto com
  `seguradoras_acionadas` e `leitura_assentada`, na mesma escrita, em toda consulta (inclusive na passada
  que fecha a cotação). A chave é da ferramenta: não está em `AsyncRunJob::MARCAS`.
- **Tamanho medido** (JSON da chave, `rails runner` em ambiente de teste, dados sintéticos na forma real):

  | Caso | Bytes |
  |---|---|
  | 17 seguradoras: 11 com preço (com parcelamento) + 6 recusas com o motivo de risco mais longo do corpus do conector (134 caracteres) | **2.844** |
  | as mesmas 17, sem motivo liberado | 1.764 |
  | 17 com preço | 2.249 |
  | pior caso: 17 recusas com motivo no teto de 300 caracteres | 6.647 |

  `resultado_por_seguradora_spec` trava os dois primeiros limites (≤ 3.000 e ≤ 7.000).

### A regra do motivo

`Insurance::MotivoDaRecusa.permitido(reason)` devolve o texto aparado só quando `kind == 'risco'` e o texto
(sem acento, em minúsculas) não casa nenhum termo de conta nem valor em reais; senão, nil. Texto que não é
String, vazio ou acima de 300 caracteres (o teto do conector) também é nil. É aplicada na **gravação**
(`ResultadoPorSeguradora`) e de novo na **leitura** (`ResultadoDaCotacao#motivo`).

Padrões depois da rodada 2 (radicais, no texto sem acento): `login` (logar, logado, logou, logue, logon,
deslogado, relogar, "log in"), `senha`, `sessão`, `token`, `usuári-`, `acess-` (não casa "acessório"),
`permiss-` (não casa "permissionário"; "permitida" não começa assim), `corretor-`/`corretag-`, `credenci-`,
`autentic-`, `autoriz-`, `habilit-`, `produtor`, `SUSEP`, `cadastr-`, `comiss-`, `certificad-`, `bloquead-`,
`@` e link. Valores: `R$`, "reais", número seguido de "mil", centavos (`15,00`), milhar (`1.500`) e quatro
dígitos fora de colchete (o código "[2005]" passa). Ver as decisões 1 e 16.

### 2. A ferramenta da Lia, `ver_resultado_da_cotacao`

`Native::InsuranceQuoteResult`, assíncrona, com um parâmetro: `seguradora`, `type: [string, null]`, em
`required`, sem `anyOf` (`openai_schema_spec`, `insurance_quote_result_spec`).

Lê `Insurance::ResultadoDaCotacao.da_conversa`: a execução de `cotar_seguro` mais nova da conversa com status
fora de `superseded`, `discarded`, `blocked` e `pending`. Não chama o conector nem exige conexão.

| Estado | O que acontece |
|---|---|
| sem cotação na conversa | `precheck` devolve `SEM_COTACAO` ao modelo; nenhuma execução |
| cotação encerrada sem número do portal (recusada no `start`) | `NAO_CHEGOU` (rodada 2) |
| cotação encerrada sem a chave (anterior a esta versão) | `SEM_RESULTADO` |
| cotação correndo sem preço (inclusive a em voo no deploy, sem a chave) | `SEM_PRECO_AINDA` |
| cotação encerrada sem preço | `SEM_PRECO` |
| `seguradora` nomeia quem não fez proposta | nome + "não fez proposta" + o motivo liberado, ou `SEM_MOTIVO` |
| `seguradora` nomeia quem ainda corre | "ainda não respondeu" (enquanto a cotação corre; depois, "não fez proposta") |
| `seguradora` não casa ninguém | `NAO_ENCONTRADA` / `NAO_ENCONTRADA_AINDA` |
| há preço a publicar (resultado inteiro, ou `seguradora` nomeia quem cotou) | `precheck` nil, a execução abre com a cotação lida e os códigos com preço no handle (`handle_de_abertura`, rodada 2), o modelo recebe `aceite`; a 1ª passada do motor (`start`) devolve o que a abertura gravou; a 2ª (`poll`) publica os itens de `QuoteOffers.item` desses códigos, na ordem de `QuoteOffers#quoted` |

- Os textos da ferramenta ao modelo não trazem o valor do prêmio. O resultado inteiro não leva nome nem
  motivo: diz que a lista sai depois da fala, se a cotação ainda corre, se há quem não fez proposta e se a
  cotação foi sem bônus. O texto do portal só entra quando a regra do motivo o libera, e ela recusa valor
  escrito como número.
- `poll` só publica se a cotação gravada na abertura ainda for a mais nova. A publicação reconfere de novo, na
  entrada do publicador e sob o lock da conversa: `Native::Base.publicacao_vale?`, chamado por
  `Tools::AutorizacaoDaExecucao#autorizacao`, recusa com `resultado_superado`. A retomada de envio pendente
  (`RetomadaDeEnvio`) faz a mesma pergunta e abandona a mensagem da lista quando surge cotação nova.
- Os cinco textos de classe (`waiting_message`, `failure_message`, `uncertain_message`, `partial_message`,
  `closing_message`) são `''`. O publicador devolve `skipped` para texto vazio, sem criar mensagem.
- `Native::Base#aceite` (instância, nil por padrão) e `Bound#aceite_native`: o texto do aceite passa a
  poder depender do pedido. As outras ferramentas continuam com o `accepted_message` da classe.
- A resposta dada no turno é registrada pelo `Bound` como conferência, com o motivo novo
  `resultado_respondido_no_turno` (`Tools::Recusa::MOTIVOS`).

**Como ela chega ao agente 24 sem escrita em produção.** `QuoteAgent::Builder.ferramentas_mantidas(agent)`
devolve `TODAS_AS_TOOLS` para `agent_type == 'insurance_quote'`, e `Agent#ferramentas_nativas` lê daí
(senão, `native_tool_slugs`); `Tools::Registry.for_agent` lê `ferramentas_nativas`. A reserva do especialista
segue o mesmo molde: `Builder.ferramentas_mantidas_do_especialista` → `Specialist#ferramentas_do_sistema`,
lida por `Specialist#tools` e por `Answerer#enabled_agent_tools`. `ver_resultado_da_cotacao` está em
`TOOLS_DO_PRINCIPAL`.

**`principal.md`**: "Você tem quatro." e a subseção `### ver_resultado_da_cotacao`, antes de
`### Os especialistas de ramo` (o md5 desse bloco e o da §7.1 não mudaram). A subseção nova é assinada por
md5 (`b1758bb74c1a6ca87e9e7151d996ef7c`) com sete promessas, cada uma exercitada.

### 3. Pedido repetido

`ToolRun#conta_como_pedido?`: `%w[done failed]` e `(delivered_count.positive? || resultado_obtido?)` e dentro
de 24 h. `ToolRun#resultado_obtido?` pergunta à ferramenta do slug (`Native::Base.resultado_guardado?`,
falso por padrão); a cotação responde verdade quando a chave tem ao menos uma seguradora **com preço**.
`PedidoRepetido#resultados`, com contador zero e resultado guardado, diz "resultado guardado e nenhuma entrega
encaminhada para publicação".

### 4. A confirmação no intervalo curto

`QuoteOffers#confirma_na_proxima?(ja_acionadas)`: a leitura está assentada e lista todo código já acionado.
É chamado só na passada em que `todas_com_desfecho?` respondeu falso (`Resultado#em_andamento`), e aí quer
dizer que a próxima leitura igual fecha a cotação. `Progress.running(confirmar_logo:)` leva o pedido ao
motor, e `AsyncRunJob#reschedule(curto: true)` agenda com `AsyncConfig.interval_for(agent, 0)` — 3 s na
progressão padrão, e o primeiro valor da progressão do agente quando ela é configurada. A tentativa conta
igual. `todas_com_desfecho?` não mudou.

Ganho, pelo motor e com o relógio parado (`async_run_job_confirmacao_curta_spec`): numa tentativa tardia
(21 s), da leitura que vê todas com desfecho até a execução em `done` passam **3 s**; antes, 21 s.

## Decisões onde o desenho não fechou sozinho

1. **A regra do motivo recusa mais do que a lista da issue.** As formas verbais de login, `autenticação` e
   `@` entram porque a revisão do conector achou texto de credencial fora das palavras da lista (e-mail no
   meio da frase, P2-3) e porque recusar a mais só custa o motivo (a Lia diz que a seguradora não fez
   proposta); liberar a mais custa credencial na fala. `R$` entra porque o texto vai ao modelo, e valor em
   reais ao cliente é do código. Cada termo tem exemplo, e um exemplo exige que toda chave da tabela tenha
   exemplo.
2. **A regra roda na gravação e na leitura.** Na gravação, o texto recusado nunca vai ao banco; na leitura,
   um motivo guardado por uma versão com regra mais frouxa não passa.
3. **`auth_required` vira "não fez proposta", com o nome.** A decisão do CEO permite dizer que a seguradora
   não fez proposta, sem motivo. O que distingue credencial (o status, o `kind`, o texto) não é guardado.
4. **Precedência da união.** Um desfecho não volta para `aguardando`. `sem_proposta` que depois cota vira
   `com_preco`, porque o lote entrega esse preço ao cliente. `com_preco` não muda, nem de valor nem para
   recusa: é o preço do primeiro lote que o cliente recebeu.
5. **O que chega ao modelo, e por qual canal.** Sem preço a publicar, pela conferência (`precheck`), sem abrir
   execução. Com preço, pelo aceite de instância, porque o pedido "Sancor e Porto" precisa levar o motivo de
   uma e anunciar o item da outra no mesmo texto; o `accepted_message` de classe é fixo. O resultado inteiro
   não leva nome nem motivo, para o modelo não listar seguradoras nem contar motivo sem pergunta.
6. **O registro da resposta no turno é uma linha de recusa com motivo próprio.** O `Bound` registra toda
   conferência; sem motivo próprio, a linha diria "a conferência recusou o pedido".
7. **Sem frase pronta: a falha depois do aceite não publica palavra da ferramenta.** Os textos de classe
   vazios cumprem "não podem publicar frase pronta do Base". A consequência, declarada: quando a execução da
   Lia falha depois de ela ter dito que a lista vem (prazo esgotado, falha de banco até o prazo, agente
   desligado, freio do operador, ou a cotação lida deixou de ser a mais nova), o cliente fica com a fala dela
   e sem a lista. No caso "a cotação deixou de ser a mais nova", o turno que abriu a cotação nova fala. **Para
   o CEO decidir:** aceitar, ou definir quem fala nesse estado (não há frase do especialista para ele).
8. **Reconferir na publicação, e não só no `poll`.** A publicação da lista pode ser adiada pela entrega da
   fala do turno; se o cliente escreve no meio, a cadeia é abortada e o adiamento dura até o teto (~3 a 4 min).
   Nesse intervalo uma cotação nova pode começar. O gancho `publicacao_vale?` fica em `AutorizacaoDaExecucao`,
   que o publicador já consulta na entrada e sob o lock.
9. **A lista mantida substitui a gravada, não soma.** Molde de `instrucao_mantida`. Efeito em outros agentes
   de cotação criados antes de `consultar_placa`: passam a ter a placa (reservada ao especialista) e a
   ferramenta nova. O agente 24 tinha em produção os mesmos quatro slugs de `TODAS_AS_TOOLS` (auditoria da
   entrega 2, 11/09/2026); só a ferramenta nova é acrescentada. A reserva do especialista também passou a ser
   a do deploy: com só a lista do agente mantida, uma ferramenta nova do especialista apareceria para a Lia.
   O exemplo «agente já criado sem o slug em native_tool_slugs não recebe a ferramenta» foi invertido.
10. **Procura por nome.** Sem acento, em minúsculas, sem palavras vazias (seguro, seguradora, de, e…). Nomeia
    quem tem todas as palavras do nome na consulta; entre duas, sai a de nome contido na outra ("Bp
    Assinatura" tira "Bp"); palavra que sobra nomeia quem a tem no nome ("liberty" → "Liberty Site"). Não
    cobre erro de digitação nem apelido ("Portto", "a azulzinha"): responde "não está nesta cotação".
11. **Resultado guardado para o pedido repetido é preço.** Só recusas guardadas não contam, e a cotação em que
    ninguém cotou continua sendo tentativa nova, como antes.
12. **Intervalo curto = primeiro intervalo da progressão do agente**, e não `MIN_INTERVAL_SECONDS`: respeita a
    configuração por agente (spec com `[7, 30]` agenda 7 s).
13. ~~A segunda chamada da ferramenta no mesmo turno é recusada.~~ **Era falso** (achado P2 da revisão):
    `ToolRun.opened_for_turn?` não conta `pending`, então a segunda abertura do mesmo turno supersedia a
    primeira e a lista anunciada pela primeira nunca saía. Corrigido na rodada 2 (ver lá): a abertura nova
    une os códigos da execução anterior sem entrega. A descrição da ferramenta e o `principal.md` continuam
    pedindo os nomes num campo só.
14. **Com o especialista desligado**, a Lia recebe `cotar_seguro` e `consultar_placa` (já acontecia) e a
    ferramenta nova continua respondendo, venha a cotação do especialista ou dela.
15. **`available_for?` é o módulo de seguros ligado**, sem exigir conexão pronta: a ferramenta lê o banco.
16. **A regra do motivo virou lista de radicais, e não lista de liberação** (rodada 2). A revisão sugeriu, como
    preferível, liberar só texto que case um gatilho de risco conhecido e não tenha dígito. Não adotei: o
    conector só marca `risco` quando um gatilho casa ("declinando", "aceitação"…), e os textos de conta da
    revisão têm o gatilho ("... Declinando cálculo."), então exigir o gatilho de novo não os barra; e "sem
    dígito" recusaria 4 dos 14 textos reais de risco do corpus ("[2005] - -Contratação não permitida…",
    "400 - Restrição técnica…", "UC00 - Risco fora…"). O que continua passando é conta escrita com palavra
    que a lista não conhece. **Para o CEO:** aceitar esse limite, ou trocar por lista de liberação e perder
    parte dos motivos reais.
17. **O que a Lia leu é o que sai, e o pedido anterior sem entrega entra na lista do novo** (rodada 2). O
    `start` relia a cotação: uma seguradora que cotasse entre a fala e a primeira passada entrava na lista que a
    fala dizia não ter chegado. Agora a abertura grava a cotação e os códigos lidos no turno
    (`Native::Base#handle_de_abertura` → `Bound#abrir` → `ToolRun.open!(handle_inicial:)`, sem as marcas do
    motor), e o `start` os devolve. A mesma abertura une os códigos da execução desta ferramenta ainda viva,
    sem entrega e sobre a mesma cotação, que ela vai superseder: duas chamadas na mesma rodada e o pedido do
    turno seguinte antes de a lista anterior sair publicam as duas listas numa só.
18. **Cotação mais nova encerrada sem número do portal** (recusada no `start`) passou a ter texto próprio,
    `NAO_CHEGOU`. Antes caía em "não ficou guardado, ofereça um atendente", que é falso ali. A seleção da mais
    nova continua a da issue (fora de `superseded`, `discarded`, `blocked` e `pending`): a cotação anterior com
    preço não é mostrada.
19. **Turno mudo com a ferramenta aceita** (sinal de silêncio da instrução, ou IA falhando na segunda chamada):
    a lista sai sem fala, porque o `Responder` despacha a execução mesmo calado. Mantido: sem isso, na falha de
    IA o cliente que pediu os preços não recebe nada. **Para o CEO:** descartar a lista quando o turno cala.
20. **A API continua aceitando `config.native_tool_slugs` do Agente de Cotação, sem efeito** (a lista é a do
    deploy). O front não expõe o campo. Mudei os cabeçalhos de `Native::Base` e `Tools::Registry`, que diziam
    que a config liga a ferramenta; não mudei a API.

## Riscos de regressão verificados, e como

| Risco | Como |
|---|---|
| Coluna "Com preço" do Super Admin | `medida_spec`: com a chave nova e 12 preços guardados, `seguradoras_com_preco` continua 11 (`entregues`); a execução da ferramenta da Lia não conta como cotação |
| Encerramento e fecho iguais | `Fecho`, `Comparativo#fechar`, `Encerramento`, `closing_deliveries` sem alteração; as suítes da fatia 1 (`*_fecha_sem_esperar_o_portal_spec`, `async_run_job_encerramento_parcial_spec`, `encerramento_spec`, `nenhum_estado_mudo`) passam |
| Ferramenta nova com o especialista desligado | `answerer_resultado_da_cotacao_spec` |
| Schema strict | `openai_schema_spec` (laço do catálogo + exemplo nomeado: uma propriedade, `required == ['seguradora']`, sem `anyOf`) |
| Nota privada | `answerer_resultado_da_cotacao_spec`: com responsável humano o `Responder` cala antes do modelo e nenhuma execução abre; humano que assume entre a fala e a publicação recebe os itens em nota privada |
| Execuções em voo no deploy | cotação correndo sem a chave ganha o resultado na consulta seguinte (`insurance_quote_resultado_spec`); a ferramenta lê essa linha como "ainda sem preço" e a encerrada sem a chave como "não guardado" (`insurance_quote_result_spec`); pedido repetido da linha sem a chave conta pelo contador (exemplos da entrega 10, inalterados) |
| `nenhum_estado_mudo` | estendido: confirmação curta + `done` com fecho, e itens da Lia sem frase pronta, sob as quatro formas de o especialista não escrever; texto ao modelo presente em todo estado sem preço |
| Pedido repetido não mente | `bound_pedido_repetido_spec`: sem entrega e com preço guardado não diz "0 resultados"; com entrega diz o número; só recusas é tentativa nova; janela de 24 h vale igual |
| Catálogo de outros agentes | `registry_spec` (tipo `custom` lê a config), `answerer_resultado_da_cotacao_spec` |
| Registro de recusa | `recusa_registro_spec` com o gatilho da saída nova |
| Contrato de nível | `base_contrato_de_nivel_spec` com `aceite`, `resultado_guardado?`, `publicacao_vale?` |

## Specs existentes alterados, e por quê

- `builder_instrucao_do_principal_promessas_spec`: exemplo do termo 3 invertido (decisão 9); o bloco da
  ferramenta nova assinado e com promessas (módulo `ManualDoPrincipalResultado`, para não passar do teto de
  linhas do `ManualDoPrincipal`); "ferramenta citada" inclui a nova.
- `recusa_registro_spec`: gatilho da saída `insurance_quote_result.rb#precheck#1`.
- `base_contrato_de_nivel_spec`: listas de nível com os três métodos novos e o padrão conservador de cada um.
- `openai_schema_spec`, `registry_spec`, `builder_spec`, `progress_spec`, `async_publisher_spec`,
  `bound_pedido_repetido_spec`, `medida_spec`, `insurance_quote_nenhum_estado_mudo_spec`, `tool_run_spec`
  (rodada 2: `open!` com `handle_inicial`): exemplos acrescentados; nenhum exemplo existente mudou de
  expectativa.

## Testes

Todos com `PATH="$HOME/.rbenv/shims:$PATH"`, exit code gravado em arquivo e contagem lida do `--out` do rspec.

| Rodada | Arquivos | Resultado | Exit |
|---|---|---|---|
| Linha de base, `5742de5fcd` | `spec/services/autonomia/agents`, `spec/jobs/autonomia/agents`, `spec/models/autonomia/agents`, `spec/services/autonomia/insurance`, `spec/requests/api/v1/accounts/autonomia`, `insurance_measurements_controller_spec` | 1552 exemplos, 0 falhas | 0 |
| Código novo, specs antigos | mesmos | 1559 exemplos, 3 falhas (as três previstas: gatilho de recusa, motivo no catálogo, termo 3) | 1 |
| `9c0bdcb8be` | mesmos | 1727 exemplos, 0 falhas; md5 de `app/` igual antes e depois | 0 |
| Fora do recorte | `super_admin`, `jobs/autonomia/insurance`, `listeners/autonomia`, `models/autonomia/insurance`, `services/autonomia/copilot`, `services/autonomia/journeys`, dois de `crm/ai`, `validators/autonomia` | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `2a348f4804` | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | todos `pass` | — |
| Depois da revisão (rodada 2) | o recorte da linha de base | 1797 exemplos, 0 falhas; md5 de `app/` igual antes e depois | 0 |

- `RAILS_ENV=test bundle exec rails zeitwerk:check`: "All is good!", exit 0.
- RuboCop com lista explícita: 20 arquivos de `app/` (exit 0), 17 specs (exit 0), 4 arquivos do refactor
  (exit 0), 0 ofensas.

### Mutações

Executor em Ruby puro (`scratchpad/f2-mutacoes.rb`): troca exata de um trecho que casa uma vez, specs
escolhidos, restauração do arquivo com md5 conferido. md5 de `app/` igual antes e depois da rodada.

| # | Mutação | Resultado |
|---|---|---|
| M01 | regra do motivo sem exigir `kind` risco | 5 falhas |
| M02 | regra do motivo sem termo de conta | 30 falhas |
| M03 | sem o termo senha | 3 falhas |
| M04 | sem barrar `R$` | 1 falha |
| M05 | "acesso" casando "acessório" | 1 falha |
| M06 | `auth_required` guardando motivo | 3 falhas |
| M07 | motivo gravado cru, sem a regra | 2 falhas |
| M08 | leitura sem reaplicar a regra | 1 falha |
| M09 | foto da leitura no lugar da união | 4 falhas |
| M10 | leitura nova sempre vence (desfecho volta a aguardando) | 2 falhas |
| M11 | a consulta não grava o resultado | 4 falhas |
| M12 | pedido repetido por troca (só resultado guardado) | 2 falhas |
| M13 | pedido repetido sem a união (só contador) | 1 falha |
| M14 | texto volta a "0 resultados" | 1 falha |
| M15 | resultado guardado conta só recusas | 3 falhas |
| M16 | Lia lê a mais nova sem excluir os quatro status | 5 falhas |
| M17 | Lia lê a mais antiga | 3 falhas |
| M18 | Lia lê cotação de outra conversa | 1 falha |
| M19 | `poll` publica a lida no `start` sem reconferir | 1 falha |
| M20 | `publicacao_vale?` sempre verdade | 2 falhas |
| M21 | publicador sem perguntar `publicacao_vale?` | 3 falhas |
| M22 | `precheck` sempre nil | 14 falhas |
| M23 | resultado inteiro com as falas por seguradora (motivo sem pergunta) | 3 falhas |
| M24 | `waiting_message` herdando a frase do `Base` | 6 falhas |
| M25 | `failure_message` herdando a frase do `Base` | 3 falhas |
| M26 | procura sem tirar o nome contido | 1 falha |
| M27 | procura aceitando entrada sem nome | 3 falhas |
| M28 | `Bound` ignorando o aceite da instância | 1 falha |
| M29 | `reschedule` ignorando o pedido curto | 7 falhas |
| M30 | intervalo curto sem exigir leitura assentada | 2 falhas |
| M31 | intervalo curto sem conferir as já acionadas | 4 falhas |
| M32 | pedido curto em toda passada `running` | 6 falhas |
| M33 | guarda das duas leituras: fecha na primeira | 5 falhas |
| M34 | agente de cotação lendo `native_tool_slugs` | 3 falhas |
| M35 | especialista lendo `tool_slugs` | 1 falha |
| M36 | `Answerer` reservando pela coluna | 1 falha |
| M37 | ferramenta nova reservada ao especialista | 14 falhas |
| M38 | ferramenta nova fora do catálogo | 41 falhas |
| M39 | `seguradora` obrigatória, sem null | 2 falhas |

**39 de 39 reprovadas.** Na primeira rodada, duas sobreviveram, e o código e os specs mudaram por causa delas
(`2a348f4804`):

- a antiga M30 tirava a cláusula "leitura diferente da anterior" de `confirma_na_proxima?` e era **mutante
  equivalente**: o método só roda com `todas_com_desfecho?` falso, e com a leitura igual à anterior isso só
  acontece quando falta seguradora já acionada, que a outra cláusula já recusa. A cláusula saiu; a M30 da
  tabela é a mutação do código novo;
- a M31 sobreviveu por falta de exemplo com leitura assentada, nova e sem uma seguradora já acionada. O
  exemplo entrou na ferramenta e no motor.

## Rodada 2: a revisão adversarial de `2a348f4804`

Revisor independente (agente com contexto próprio, só leitura), com sondas pelo caminho real guardadas fora
do repositório. 1 P1, 2 P2, 6 P3.

| Achado | Severidade | O que mudou |
|---|---|---|
| A regra do motivo liberava dez textos que o classificador real do conector marca `risco` e que falam da conta da corretora com outras palavras ("Produtor não credenciado", "Credenciamento pendente", "Não autorizado a calcular", "Código SUSEP inválido", "Sistema deslogado", "relogar", "Corretagem acima do limite", "Faça o log in") ou de valor sem `R$` ("Prêmio mínimo de 1.500,00") | P1 (condicional: nenhum está no corpus medido) | Radicais e valores em `MotivoDaRecusa` (decisão 16); os dezenove textos das duas revisões recusados; os catorze textos reais de risco do corpus liberados; cada padrão com um exemplo que só ele recusa |
| Duas chamadas na mesma rodada: a segunda abertura supersedia a primeira, e só a segunda lista saía; a decisão 13 afirmava o contrário | P2 | `handle_de_abertura` une os códigos da execução anterior sem entrega (decisão 17); decisão 13 corrigida |
| O `start` relia a cotação, e a lista podia trazer seguradora que a fala disse não ter respondido; a reconferência comparava a cotação lida no `start`, não a que a Lia leu | P2 | A abertura grava a leitura do turno, e o `start` a devolve (decisão 17) |
| Cotação mais nova recusada no `start` escondia a anterior e o modelo ouvia "ofereça um atendente" | P3 | `NAO_CHEGOU` (decisão 18) |
| A regravação velha entre o `record_attempt!` da passada que fecha e o `finish!` é permanente, e não "até a consulta seguinte" | P3 | Declarada em "O que NÃO foi verificado" e no comentário de `PRECEDENCIA`; classe da #418, sem conserto nesta fatia |
| Lista sem fala no turno mudo | P3 | Decisão 19, para o CEO |
| Config de ferramentas do Agente de Cotação aceita e ignorada; cabeçalhos dizendo o contrário | P3 | Decisão 20: cabeçalhos corrigidos |
| Comentário de `publicacao_vale?` sem a entrada do publicador e a retomada de envio | P3 | Comentário corrigido |
| Auditoria fora do branch | P3 | Commitada |

Onde o revisor olhou e não achou defeito: silêncio sem frase (texto vazio vira `skipped` também encadeado),
coluna "Com preço", `Fecho`/`Comparativo`/`Encerramento` sem mudança de lógica, catálogo de outros tipos de
agente, intervalo curto (prazo e contagem de tentativas iguais; a janela entre as duas leituras cai de 13 a
21 s para 3 a 8 s — risco não medido, ver abaixo), schema, `principal.md`.

### Mutações da rodada 2

| # | Mutação | Resultado |
|---|---|---|
| R01 | credencial volta a palavra inteira ("credenciado" passa) | 3 falhas |
| R02 | login sem des-/re- nem "log in" | 6 falhas |
| R03 | sem o padrão de autorização | 5 falhas |
| R04 | sem SUSEP | 3 falhas |
| R05 | sem o padrão de centavos | 2 falhas |
| R06 | quatro dígitos casando o código entre colchetes | 2 falhas |
| R07 | valores fora da conferência | 9 falhas |
| R08 | abertura sem unir a execução anterior sem entrega | 3 falhas |
| R09 | união aceitando execução que já entregou | 1 falha |
| R10 | união aceitando execução sobre outra cotação | 1 falha |
| R11 | `start` relendo a cotação em vez de usar a abertura | 4 falhas |
| R12 | `Bound` sem entregar o handle de abertura | 3 falhas |
| R13 | `open!` gravando marca do motor vinda da abertura | 1 falha |
| R14 | cotação encerrada sem número do portal volta a "não guardado" | 3 falhas |

**14 de 14 reprovadas**, md5 de `app/` igual antes e depois.

## O que NÃO foi verificado

- **Conversa real com o modelo.** Que a Lia chame a ferramenta quando o cliente pergunta, não escreva valor,
  não liste seguradoras e não conte motivo sem pergunta é conduta do modelo; aqui o modelo é dublado.
- **`quote/result` real com o `reason` do conector #60.** O resultado guardado foi exercitado com fixtures
  sintéticas na forma do corpus sanitizado do conector, não com uma leitura real depois do #60. Lido no
  conector (`src/platforms/agger/http/quote.ts`, `toOffer`, `origin/main` `ad4372a`): só a oferta que sai de
  `calc.erros` (`declined` ou `auth_required`) traz `reason`; a `error` sai sem `reason`, e aqui ela vira sem
  proposta sem motivo.
- **Duas passadas sobre a mesma execução gravando a chave nova.** O `record_attempt!` do fim da passada regrava
  a chave com a cópia da passada; uma passada com leitura mais velha pode regravar uma entrada `com_preco` como
  `aguardando`. Quando isso cai entre o `record_attempt!` da passada que fecha e o `finish!`, fica assim para
  sempre (sonda do revisor): a Lia diria que a seguradora não fez proposta, e o pedido repetido não contaria o
  resultado. Mesma classe da #418; sem conserto e sem teste nesta fatia. A fonte conhecida de duas passadas é a
  corrente de jobs duplicada (`perform_later` que levanta depois de o Redis gravar).
- **Lista duplicada na janela de milissegundos** entre a mensagem da lista criada e o `record_delivery!` da
  execução anterior: a abertura de um pedido novo nesse instante uniria os códigos dela de novo. Sem teste.
- **A confirmação curta encurta a janela entre as duas leituras** de 13 a 21 s para 3 a 8 s. A guarda das duas
  leituras depende de o portal já ter listado todas as seguradoras quando a lista se repete; nos brutos de
  13/09/2026 todas estavam listadas na primeira leitura, e o contrário não foi observado. Não medido com a
  janela nova.
- **Conta da corretora escrita com palavra fora da lista** continua passando pela regra do motivo (decisão 16).
- **Ordem da lista depois da fala com a entrega humanizada ligada**, especificamente para a ferramenta nova. O
  adiamento pela cadeia do turno é o mecanismo geral (`async_publisher_spec`, "humanized chain deferral"); o
  spec de integração desta fatia usa a entrega clássica.
- **Resposta em áudio** (`deliver_voice`) seguida da lista.
- **Outros agentes de cotação em produção além do 24**: não consultei o banco de produção. O efeito da lista
  mantida neles está na decisão 9.
- **O schema contra a API da OpenAI.** Validado pela forma (`openai_schema_spec`), não por chamada real.
- **Custo por turno**: a ferramenta nova acrescenta uma função ao prompt do agente de cotação; e uma consulta
  por publicação da lista (`publicacao_vale?`). Não medido.
- **Rollback executado.**

## Deploy e rollback

- Sem migration, sem variável de ambiente nova, sem escrita em banco. Deploy normal do chat2you.
- Depois do deploy, o agente 24 passa a oferecer `ver_resultado_da_cotacao` no turno seguinte, e o
  `principal.md` novo vale na montagem seguinte do prompt.
- **Rollback**: voltar à imagem de `5742de5fcd`. Efeitos conhecidos:
  - a coluna `native_tool_slugs` do agente 24 volta a mandar (os quatro slugs de antes): a ferramenta some do
    turno;
  - execução da ferramenta nova em voo: `Registry.find` não a acha, e o motor a fecha com
    `ferramenta_indisponivel`, sem mensagem;
  - `AsyncPublishJob` da lista já adiado publica sem a reconferência (o publicador antigo não tem o gancho);
  - o handle das cotações mantém a chave `resultado_por_seguradora`, que a versão antiga ignora;
  - o pedido repetido volta a contar só pelo contador.
