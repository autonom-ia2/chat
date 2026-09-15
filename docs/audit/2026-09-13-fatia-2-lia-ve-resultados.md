# Fatia 2 do #420: a Lia vê o resultado da cotação

Data: 13/09/2026 · Branch `feat/cotacao-lia-ve-resultados` · base `origin/main` (`5742de5fcd`).

**Desenho atual: o da rodada 8** (13/09/2026, decisão do coordenador): a ferramenta da Lia é síncrona, a lista de
preços vai como anexo do turno, escrita pelo código, e a categoria do motivo só sai por molde fechado. As seções das
rodadas 2 a 7 ficam como histórico do desenho assíncrono, que saiu; onde contradizem a rodada 8, vale a rodada 8.

## Objetivo

Quatro coisas, e só elas:

1. a cotação **guarda o resultado por seguradora** no handle da execução, em toda consulta, como união;
2. a Lia ganha uma **ferramenta síncrona**, `ver_resultado_da_cotacao`, que lê esse resultado no instante da pergunta,
   sem ir ao portal; com preço, o código escreve a lista e a anexa ao turno, e o `Responder` a entrega logo depois da
   fala dela, na mesma entrega (rodada 8; nas rodadas 1 a 7 ela era assíncrona); o motivo de quem não cotou só chega
   ao modelo como categoria escrita pelo código (do veículo ou da região, por molde fechado; rodadas 7 e 8), e só
   quando o pedido nomeia a seguradora;
3. o **pedido repetido** conta também a execução com resultado guardado, por união com o contador;
4. a **confirmação do fechamento** (a segunda leitura igual) roda no primeiro intervalo da progressão, e não
   no intervalo da tentativa.

Fora, de propósito: parar os lotes de preço, sinal de vida depois de 2 min, rede de segurança da lista
quando o PDF falha (fatia 3). Nada novo no Super Admin. Nada no conector. No motor assíncrono, só a gravação do
resultado (pedido repetido) e a confirmação curta: o resto voltou igual ao da `main` na rodada 8.

## O que mudou, por item

### 1. O resultado por seguradora no handle

- `Insurance::ResultadoPorSeguradora.unir(guardado, ofertas)` monta uma entrada por código:
  - com preço (`QuoteOffers.cotada?`: `quoted` com valor): `nome`, `desfecho: com_preco`, `premio` só com
    `amount`, `basis` e `installments` (os campos que `PremiumText#resumo`/`#detalhe` leem e que
    `QuoteOffers#quoted` usa para ordenar);
  - `declined`, `auth_required` e `error`: `desfecho: sem_proposta`; `motivo: 'veiculo'` ou `'regiao'` só quando
    `Insurance::MotivoDaRecusa.categoria` classifica o motivo e a oferta **não** é `auth_required` (rodada 7; até a
    rodada 6 guardava `{ kind, text }` com o texto liberado). O texto do portal nunca é guardado;
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
  | pior caso: 17 recusas com motivo no teto de 300 caracteres (medido com "x"; na rodada 4, com palavras do vocabulário e acento) | 6.647; 7.072 |
  | **rodada 7** (a categoria no lugar do texto; `rails runner` em ambiente de teste, dados de `DezesseteSeguradoras`): 11 com preço + 6 recusas com a categoria | **1.947** |
  | rodada 7: as mesmas 17, sem categoria | 1.833 |
  | rodada 7: 17 com preço ("Seguradora N", parcelamento) | 2.380 |
  | rodada 7, pior caso das recusas: 17 com a categoria | 1.258 |

  `resultado_por_seguradora_spec` trava os limites (≤ 3.000; desde a rodada 7, as 17 recusas com categoria ≤ 2.000).
- **Os códigos e a hora de emissão de cada lote de preço** (rodadas 4 e 5): `InsuranceQuote::Resultado::LOTES_KEY`
  (`codigos_por_lote_de_preco`), identidade da entrega do lote → `{ codigos, emitido_em }`, gravada na passada que
  emite o lote (`lote_de_preco`, chamado de `InsuranceQuote#entregues`). Chave da ferramenta, fora de
  `AsyncRunJob::MARCAS`; cresce cerca de 90 bytes por lote.

### A regra do motivo (rodada 8: categoria por molde fechado)

**Nenhum texto do portal vai ao modelo nem ao banco** (decisão do CEO de 13/09/2026 sobre as decisões 27 e 28, opção
b), e **a categoria só sai por molde fechado** (decisão do coordenador sobre o achado P3-1 da revisão da rodada 7).
`Insurance::MotivoDaRecusa.categoria(reason)` devolve `'veiculo'`, `'regiao'` ou nil (o genérico) quando, e só quando:

1. `kind == 'risco'` e o texto é String UTF-8 válida. Qualquer outro `kind` (`passageiro`, `credencial`, `outro`) é nil;
2. **toda palavra do texto**, sem acento e em minúsculas, contando palavras de função e números, está no conjunto da
   categoria (`MOLDES`). Uma palavra desconhecida manda para o genérico;
3. o texto nomeia o que foi recusado: no veículo, um atributo (idade, ano, modelo, tipo, categoria, tarifária,
   fabricação) **e** o veículo (veículo, carro, moto, motocicleta, automóvel, caminhão, ônibus, auto), porque "idade",
   "tipo" e "categoria" sozinhos também servem para a pessoa e para a cobertura; na região, CEP, localidade, região,
   circulação ou pernoite.

Os conjuntos, inteiros (`motivo_da_recusa.rb`): as palavras de função e de recusa das duas categorias (`COMUNS`: artigos,
preposições e contrações, demonstrativos, "não", "sem", aceito/aceita/aceitação, permitido/permitida, possui,
restrito/restrita, recusado/recusada, fora, acima, atendido/atendida, política, informado/informada, seguradora); no
veículo, os atributos, os nomes do veículo e a abertura de recusa que o portal escreve ("cotação não será realizada por
motivos técnicos", "cobertura"); na região, os atributos e "local". Nenhum conjunto tem palavra de conta da corretora, da
pessoa ou de critério interno, e o `motivo_da_recusa_spec` trava isso com as palavras que as revisões usaram. As listas
de termos da rodada 7 (`TERMOS_DE_CONTA`, `TERMOS_DA_PESSOA`, `TERMOS_DE_DUVIDA`) saíram: com o molde fechado, qualquer
termo delas já é palavra desconhecida. A letra que a transliteração não sabe escrever vira `#`, e a palavra com ela é
desconhecida.

Na dúvida, nil: o erro aceitável é a Lia dizer só que a seguradora não fez proposta. A categoria é gravada no handle
(`ResultadoPorSeguradora#sem_proposta`), a leitura só devolve o que é categoria (`ResultadoDaCotacao#motivo`), e o
modelo lê uma de duas falas fechadas (`InsuranceQuoteResult::MOTIVOS`) ou `SEM_MOTIVO`, cada uma com a categoria
escrita (`Categoria do motivo: veiculo`, `regiao` ou `nenhuma`).

**O corpus do conector** (`autonomia-adapters`, `test/fixtures/agger/motivos-de-recusa.sanitized.json`, 39 mensagens;
tabela inteira na seção da rodada 8): 4 das 13 `risco` saem `veiculo`, nenhuma sai `regiao`, e as 35 outras saem
genéricas. **Custo em motivos reais:** as mensagens 31, 32 e 33, que a rodada 7 dava como do veículo, caem no genérico.
**Custo nos 23 motivos plausíveis da rodada 7:** a categoria sai em 5 (eram 10). **Os textos das revisões** (os 28 de
conta da quinta revisão, os 6 de dado pessoal, os 25 das revisões anteriores e os 31 da revisão da rodada 7, em
`SondasDoMotivo::REVISAO_7`, que com os padrões da rodada 7 saíam todos com categoria): todos nil, incluindo "Tipo de
veículo sem aceitação para o seu código." e "Negativado: CEP sem aceitação.".

### 2. A ferramenta da Lia, `ver_resultado_da_cotacao` (rodada 8: síncrona, lista como anexo do turno)

`Native::InsuranceQuoteResult`, **síncrona**, com um parâmetro: `seguradora`, `type: [string, null]`, em `required`, sem
`anyOf` (`openai_schema_spec`, `insurance_quote_result_spec`). Nas rodadas 1 a 7 ela era assíncrona; a troca e o motivo
estão na seção "Rodada 8".

Lê, **no instante da pergunta**, `Insurance::ResultadoDaCotacao.da_conversa`: a execução de `cotar_seguro` mais nova da
conversa com status fora de `superseded`, `discarded`, `blocked` e `pending`. Não chama o conector nem exige conexão.
Não abre execução, não guarda nada entre turnos e não sabe de lista de outro turno: a mesma pergunta feita duas vezes
recebe a lista duas vezes.

| Estado | O que o modelo recebe | O que é anexado ao turno |
|---|---|---|
| sem contexto de entrega (Testar, Copiloto, playground) | `{"error":"lista_indisponivel_nesta_superficie"}`, com a linha do registro de recusa | nada |
| sem cotação na conversa | `SEM_COTACAO` | nada |
| cotação encerrada com envio incerto (intenção anotada, número ausente) | `ENVIO_INCERTO` | nada |
| cotação encerrada sem número do portal (recusada no `start`) | `NAO_CHEGOU` | nada |
| cotação encerrada sem a chave (anterior a esta versão) | `SEM_RESULTADO` | nada |
| cotação correndo sem preço (inclusive a em voo no deploy, sem a chave) | `SEM_PRECO_AINDA` | nada |
| cotação encerrada sem preço | `SEM_PRECO` | nada |
| todo preço está num lote que a cotação ainda está enviando (`a_caminho`) | quantas cotaram + `PRECOS_A_CAMINHO` | nada |
| há preço a mostrar, resultado inteiro | quantas cotaram (número, sem nome) + `LISTA_ANEXADA` + `PARTE_A_CAMINHO`, `AINDA_CORRENDO`, `HA_SEM_PROPOSTA` e `SEM_BONUS` quando valem | os itens de `QuoteOffers.item` dos códigos com preço fora do lote a caminho, na ordem de `QuoteOffers#quoted` |
| `seguradora` nomeia quem cotou | quantas cotaram + `LISTA_ANEXADA` + "X fez proposta: o preço dela vai na lista anexada" (ou "está na fila de envio e chega numa mensagem do sistema", sem `LISTA_ANEXADA` quando nenhuma nomeada tem preço fora do lote a caminho) | os itens das nomeadas com preço fora do lote a caminho |
| `seguradora` nomeia quem não fez proposta | quantas cotaram + "X não fez proposta nesta cotação." + a fala da categoria (`MOTIVOS`) ou `SEM_MOTIVO` | nada |
| `seguradora` nomeia quem ainda corre | quantas cotaram + "X ainda não respondeu" (enquanto a cotação corre; depois, "não fez proposta") | nada |
| `seguradora` não casa ninguém | `NAO_ENCONTRADA` / `NAO_ENCONTRADA_AINDA` | nada |

- **O modelo nunca recebe valor em reais nem texto do portal.** O que ele recebe é estado; o valor está só no anexo, que
  ele não vê.
- **O anexo do turno** (`Tools::Delivery#anexar(chave, texto, dados:)`) é um por chave. A ferramenta chamada duas vezes no
  mesmo turno troca o próprio anexo, no mesmo lugar, pela lista com os códigos das duas chamadas (`dados` guarda os
  códigos já anexados). O cliente recebe uma lista por turno. Só o `Responder` cria o `Delivery`.
- **A entrega, no `Operate::Responder`**, logo depois da resposta, nos três caminhos:
  - **clássico** (`classic_deliver`): a resposta e depois cada anexo, dentro do mesmo lock e da mesma transação
    (`post_reply_and_anexos!`), com a idempotência de `already_replied?`: os anexos levam o mesmo
    `autonomia_reply_to_message_id` da resposta, e o retry do `ReplyJob` não posta nada de novo;
  - **humanizado** (`deliver_humanized`): os anexos entram no fim do array de `chunks`, cada um como um pedaço inteiro
    (sem o `ReplyChunker`), com a pausa mínima de um pedaço, na mesma cadeia do `ChunkedDeliveryJob`; `@expected_chunks`
    conta os anexos, porque as entregas assíncronas do mesmo turno esperam o último pedaço. Quando o quebrador não
    produz pedaço, o caminho é o clássico, com os anexos, e `@expected_chunks` fica zero, como na `main`;
  - **voz** (`deliver_voice`): o áudio e depois os anexos como texto, no mesmo lock; com a síntese falhando, a resposta
    em texto e depois os anexos.
- **Turno mudo** (`no_usable_reply?`: sinal de silêncio, falha de IA, resposta vazia): o anexo sai sozinho, pelo caminho
  clássico (sob o lock, com `still_eligible?` e `already_replied?`), sem evento `replied`, e o turno continua `silenced`
  (decisão 19, aceita pelo CEO). A gravação é best-effort: a falha vai ao log, e a execução assíncrona aceita no mesmo
  turno é despachada como seria sem o anexo (decisão 39).
- **O preço que a própria cotação ainda está enviando não entra na lista (rodadas 4 a 6, mantido).**
  `ResultadoDaCotacao#a_caminho`: os códigos, pelo `LOTES_KEY`, dos lotes de preço (`PRECOS_KEY`) cuja mensagem existe
  com pendência de envio (com aceite ou sem) mais nova que a janela do varredor (`ReapStaleRunsJob::ENVIO_PENDENTE_JANELA`,
  2 dias), ou que o publicador aceitou (`EntregaAceita::CHAVE`), não têm mensagem e foram emitidos há menos de
  `JANELA_DO_LOTE` (10 min); lote a caminho sem os códigos gravados (emitido antes desta versão) segura todos. Sem isso,
  o lote adiado pela fala do turno da cotação e a lista da Lia pedida nesse intervalo levariam o mesmo preço duas vezes.

**Como ela chega ao agente 24 sem escrita em produção.** `QuoteAgent::Builder.ferramentas_mantidas(agent)`
devolve `TODAS_AS_TOOLS` para `agent_type == 'insurance_quote'`, e `Agent#ferramentas_nativas` lê daí
(senão, `native_tool_slugs`); `Tools::Registry.for_agent` lê `ferramentas_nativas`. A reserva do especialista
segue o mesmo molde: `Builder.ferramentas_mantidas_do_especialista` → `Specialist#ferramentas_do_sistema`,
lida por `Specialist#tools` e por `Answerer#enabled_agent_tools`. `ver_resultado_da_cotacao` está em
`TOOLS_DO_PRINCIPAL`.

**`principal.md`**: "Você tem quatro." e a subseção `### ver_resultado_da_cotacao`, antes de `### Os especialistas de
ramo` (o md5 desse bloco e o da §7.1 não mudaram). Rodada 8: "a lista vai anexada à sua resposta e chega logo depois da
sua mensagem" e "Cada consulta mostra o que a cotação tem naquele momento"; sem frase pronta e sem travessão. md5
`429fbe18230433e92c3e07bf14cd4f5f`, dez promessas, cada uma exercitada (a do "naquele momento" troca o resultado
guardado entre duas consultas e confere que nenhuma execução abriu).

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

**Rodada 8.** A troca de desenho supera as decisões presas à ferramenta assíncrona: **5, 6, 7, 8, 13, 17, 22, 23, 25,
26, 30, 31, 32 e 33** ficam como histórico (a execução, o aceite e a lista levada, descontada e publicada pelo motor
saíram), e **1 e 16** (as listas de termos e de liberação do motivo) deram lugar ao molde fechado. Continuam valendo
2, 3, 4, 9, 10, 11, 12, 14, 15, 18, 20, 21, 24, 27, 28, 29 e 34; a 19 continua, com o anexo entregue pelo `Responder`.
As decisões da rodada 8 são as de 35 em diante.

1. **A regra do motivo recusa mais do que a lista da issue.** As formas verbais de login, `autenticação` e
   `@` entram porque a revisão do conector achou texto de credencial fora das palavras da lista (e-mail no
   meio da frase, P2-3) e porque recusar a mais só custa o motivo (a Lia diz que a seguradora não fez
   proposta); liberar a mais custa credencial na fala. Desde a rodada 7 os termos não liberam texto nenhum: eles
   tiram a categoria de um texto que nomeia o veículo ou a região junto com a conta, a pessoa ou um critério interno.
   Cada termo tem exemplo, e um exemplo que só ele casa.
2. **A regra roda na gravação e na leitura.** Na gravação só a categoria vai ao banco; na leitura, só o que é
   categoria vira fala (um motivo guardado em outra forma, como o `{ kind, text }` das rodadas 1 a 6, não passa).
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
   e sem a lista. No caso "a cotação deixou de ser a mais nova", o turno que abriu a cotação nova fala. A
   terceira revisão mediu que, com uma lista anterior adiada, **uma falha só** na publicação da lista nova basta
   para as duas não saírem (a anterior é barrada pela nova despachada, decisão 23), e não "falha até o prazo":
   texto recusado pelo publicador não reagenda a passada. **Decidido pelo CEO em 13/09/2026 e implementado na
   rodada 7:** a lista anterior só conta como levada depois de a nova ser aceita; a falha passageira (banco ou
   publicador) tenta de novo pelas tentativas do motor, com o encerramento como última tentativa; a cotação lida
   substituída por uma mais nova cala, e é o certo. Os resíduos, com o cenário de cada um, estão na seção da rodada 7
   ("Os resíduos da decisão 7"). **A revisão da rodada 7 achou a decisão ainda não cumprida inteira** (P2-1, estado
   mudo novo; P2-3, a falha na publicação adiada): consertos abertos, para decisão.
8. **Reconferir na publicação, e não só no `poll`.** A publicação da lista pode ser adiada pela entrega da
   fala do turno; se o cliente escreve no meio, a cadeia é abortada e o adiamento dura até o teto (~3 a 4 min).
   Nesse intervalo uma cotação nova pode começar. O gancho `publicacao_vale?` fica em `AutorizacaoDaExecucao`,
   que o publicador já consulta na entrada e sob o lock.
9. **A lista mantida substitui a gravada, não soma.** Molde de `instrucao_mantida`. Efeito em outros agentes
   de cotação criados antes de `consultar_placa`: passam a ter a placa (reservada ao especialista) e a
   ferramenta nova. O agente 24 tinha em produção os mesmos quatro slugs de `TODAS_AS_TOOLS` (auditoria da
   entrega 2, 11/09/2026); só a ferramenta nova é acrescentada. **Verificado em produção pelo coordenador em
   13/09/2026:** o único agente de cotação é o 24 (Lia, conta 16), com `consultar_produtos_cotacao`,
   `consultar_condicoes_gerais`, `cotar_seguro` e `consultar_placa`; não há outro agente que a lista mantida alcance. A reserva do especialista também passou a ser
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
16. **A regra do motivo é uma lista de liberação por palavra** (rodada 4; na rodada 2 era lista de radicais de
    conta, com a decisão para o CEO; na rodada 3, radicais mais objeto do risco e nenhum dígito). Cada revisão
    achou texto de conta com palavra que a lista de conta não tinha: a segunda, 22 que saem `risco` do
    classificador real ("Entre novamente no portal da seguradora", "Descredenciado", "Faça logoff") e 7 de valor
    sem `R$`; a terceira, a conta **colada a uma linha de risco** ("Risco fora das políticas de aceitação Licença
    do multicálculo vencida."), palavra de risco com outro sentido ("Uso indevido do multicálculo"), inglês,
    dado pessoal ("operador joao.silva"), número por extenso e dígito de outro alfabeto. Lista de conta não
    fecha por construção. O desenho da rodada 4 vai pelo outro lado: **toda palavra do texto tem de estar num
    vocabulário** (ligação, recusa e aceitação, objeto do risco), só letras latinas e pontuação, e o texto tem de
    nomear o objeto do risco. **A quarta revisão mostrou que ele também não fecha**: 16 textos de conta escritos só
    com palavras do vocabulário, todos `risco` no classificador real, passavam ("Limite máximo de cotação de seguro
    auto nesta seguradora.", "Veículo sem aceitação: sua tabela não é mais aceita."). A rodada 5 tirou do
    vocabulário a segunda pessoa (o portal fala com a corretora logada) e as palavras que serviam para falar da
    conta (produto, limite, máximo, mínimo, tabela, classe, histórico, local, área, estado, atividade, indisponível,
    restrito), o que recusa 15 dos 16, e ainda passa "Seguro auto não permitido nesta seguradora.". Medido no corpus
    do conector: das 13 entradas `risco`, 12 passam; nenhuma das 26 de outro `kind` passaria como `risco`. O custo:
    em 68 motivos de risco sintéticos plausíveis da revisão, a regra perde 46 (a Lia diz só que a seguradora não fez
    proposta); os mais comuns no spec, "o custo, declarado". **Para o CEO decidir** (ver decisão 27): manter o
    texto do portal com esta regra, ou trocá-lo por um motivo escrito pelo código por categoria. **Substituída na
    rodada 7** pela categoria escrita pelo código (decisão 27, opção b, decidida pelo CEO): o vocabulário saiu.
17. **O que a Lia leu é o que sai** (rodada 2) **e a lista anterior sem mensagem entra na do pedido novo, uma
    vez** (rodada 3). O `start` relia a cotação: uma seguradora que cotasse entre a fala e a primeira passada
    entrava na lista que a fala dizia não ter chegado. A abertura grava a cotação e os códigos lidos no turno
    (`Native::Base#handle_de_abertura` → `Bound#abrir` → `ToolRun.open!(handle_inicial:)`, sem as marcas do
    motor), e o `start` os devolve. Na rodada 2 a abertura também unia os códigos da execução anterior viva e
    sem entrega; a terceira revisão mostrou que isso **publicava a mesma lista duas vezes** quando a anterior
    estava adiada pela fala do turno (ela fecha `done` com `delivered_count` 1 e a mensagem ainda não existe), e
    que a união fora do lock perdia a primeira lista com dois turnos simultâneos. Rodada 3: a união saiu da
    abertura e foi para o `poll`, sob o lock da conversa, pela `sequence` (a mensagem), e `publicacao_vale?`
    recusa a lista sem mensagem de uma execução quando outra mais nova sobre a mesma cotação já foi despachada.
    Rodada 4: "mensagem" passou a ser "mensagem entregue" (sem pendência de envio, decisão 26), e a supersedida
    só entra se foi despachada ou é do mesmo turno (decisão 25). Rodada 7: a composição grava a lista inteira
    (`lista`: códigos, levadas e identidade), desconta a anterior entregue depois da abertura e leva também a que falhou
    (decisão 31).
18. **Cotação mais nova encerrada sem número do portal** (recusada no `start`) passou a ter texto próprio,
    `NAO_CHEGOU`. Antes caía em "não ficou guardado, ofereça um atendente", que é falso ali. A seleção da mais
    nova continua a da issue (fora de `superseded`, `discarded`, `blocked` e `pending`): a cotação anterior com
    preço não é mostrada.
19. **Turno mudo com a ferramenta aceita** (sinal de silêncio da instrução, ou IA falhando na segunda chamada):
    a lista sai sem fala, porque o `Responder` despacha a execução mesmo calado. Mantido: sem isso, na falha de
    IA o cliente que pediu os preços não recebe nada. **Aceito como está pelo CEO em 13/09/2026.** Desde a rodada 7
    a lista do turno mudo também sai no encerramento (prazo, tentativas, varredor), sem frase, se não saiu antes.
20. **A API continua aceitando `config.native_tool_slugs` do Agente de Cotação, sem efeito** (a lista é a do
    deploy). O front não expõe o campo. Mudei os cabeçalhos de `Native::Base` e `Tools::Registry`, que diziam
    que a config liga a ferramenta; não mudei a API.
21. **Cotação encerrada com envio incerto tem texto próprio** (rodada 3, `ENVIO_INCERTO`). O cliente já ouviu
    que não se confirmou se a cotação foi aberta e que um atendente vai conferir; `NAO_CHEGOU` o contradizia
    sobre uma cotação que pode existir no portal. A que ainda corre continua "ainda sem preço".
22. **A execução mais nova `pending` não barra a lista anterior** (rodada 3). Uma `pending` pode ser descartada
    com o turno; se barrasse, a lista anterior se perderia junto. O custo era o residual 1 de "O que NÃO foi
    verificado"; desde a rodada 7 a lista anterior que sai nesse intervalo é descontada da nova (resíduo R4 da
    rodada 7: sai antes da fala nova, e não repete).
23. **A lista anterior só é barrada pela mais nova que a levou e já teve a lista aceita** (rodada 7, decisão do CEO).
    Rodadas 3 a 6: barrada pela mais nova que a levou ou, sem mensagem, pela mais nova despachada, mesmo que a mais
    nova depois falhasse, e aí as duas listas ficavam sem sair. A barreira "mais nova despachada" existia porque a
    quinta revisão reproduziu a lista adiada saindo entre o despacho e o `poll` da nova, e as duas listas saindo com os
    mesmos códigos; na rodada 7 esse caso é resolvido pelo desconto (a nova tira da lista os códigos da anterior que
    virou mensagem depois de ela abrir), sem barrar antes do aceite. O terceiro valor no gancho do publicador, sugerido
    na rodada 3, não foi preciso: a anterior continua valendo até o aceite da nova, e a nova não aceita sai de novo.
24. **O preço que a própria cotação ainda está enviando não entra na lista da Lia** (rodada 4). A terceira revisão
    reproduziu, pelo caminho real, a mesma seguradora em duas listas sem o cliente pedir duas vezes: o lote de
    preços da cotação adiado pela fala do turno (até 3 a 4 min com a cadeia abortada) e o cliente perguntando
    "quanto deu?" nesse intervalo. A lista da Lia saía, e depois o lote. A cotação passou a gravar os códigos de
    cada lote (`LOTES_KEY`), e a Lia tira da lista os códigos dos lotes aceitos e ainda não entregues
    (`a_caminho`), dizendo ao modelo que o preço está na fila de envio. Lote a caminho sem os códigos gravados
    (emitido antes desta versão) segura todos os preços. A quarta revisão mostrou dois furos, fechados na rodada 5:
    o lote publicado na hora com a fila fora fica com pendência de envio **sem aceite** (o publicador devolve
    `blocked`) e não contava; e o lote aceito cuja publicação adiada morre ficava "a caminho" para sempre, com a Lia
    prometendo o envio a cada pergunta. Agora a mensagem com pendência de envio conta com aceite ou sem, e o lote
    aceito sem mensagem só conta até `JANELA_DO_LOTE` (10 min) depois da emissão; passado isso, a lista da Lia volta a
    levar o preço.
25. **A supersedida só entra na lista da mais nova se foi despachada ou é do mesmo turno** (rodada 4). A terceira
    revisão reproduziu: turno 2 aceita a ferramenta e morre sem despachar (a execução fica `pending`); a lista do
    turno 1 sai no teto; o turno 3 supersede a do turno 2 e levava os códigos dela, repetindo a lista do turno 1.
    A do turno que não despachou não é promessa: o turno não falou. O custo: com dois turnos da conversa vivos ao
    mesmo tempo, a lista prometida pelo turno cuja execução foi supersedida antes do despacho não sai.
26. **A lista com pendência de envio não é lista entregue** (rodada 4). A revisão reproduziu: a fila recusa o
    envio da lista A (a mensagem fica marcada), o cliente pede de novo, a lista B sai inteira, e o varredor
    reenvia A. Agora a lista de A entra na de B, e a retomada do envio de A é barrada por `publicacao_vale?`
    (a mensagem de A fica no banco, sem envio). A quarta revisão mostrou que o varredor podia abandonar A antes de
    B levá-la (B despachada, ainda sem `poll`), e A não saía em lugar nenhum. Rodada 5: quem barra A é a execução que
    gravou, sob o lock da conversa, que a levou (`listas_absorvidas`); antes disso a retomada de A vale. A quinta
    revisão mostrou que, abandonada a pendência de A depois de B levá-la, A parece entregue, e C (que leva B) não a
    levava: a Porto prometida no turno de A não saía. Rodada 6: C leva também as que B já tinha levado. Rodada 7: a
    retomada de A só é barrada depois de a lista de B ser aceita, e C leva os códigos da lista inteira de B.
27. **O motivo do portal ao modelo não fecha por lista de palavras. Para o CEO decidir.** Cinco rodadas: lista de
    termos de conta (furada por vocabulário novo), objeto do risco (furada por conta colada a risco), vocabulário
    de liberação (furado por conta escrita com palavras do vocabulário). A quarta revisão sugeriu a causa raiz:
    **não passar o texto do portal ao modelo**, e sim uma categoria escrita pelo código a partir do objeto do risco
    que o texto nomeia ("a seguradora recusou por causa do veículo", "da região", "do condutor"). A quinta revisão
    mediu a regra da rodada 5 com 134 textos sintéticos, todos `risco` no classificador real: **25 de 28 textos de
    conta e permissão passam** reescritos sem as palavras retiradas ("Risco sem aceitação: cotação não é mais
    permitida nesta seguradora.", "Veículo sem aceitação: cotação está restrita nesta seguradora."), **6 de 6 de
    dado pessoal passam** ("Condutor principal com restrição."), e a retirada de palavras da rodada 5 custou 31 de 32
    motivos plausíveis que só usavam uma delas ("Tabela FIPE", "Classe de bônus", "Local de pernoite", "Histórico de
    sinistros"). Opções: (a) manter o texto com a regra atual (12 de 13 motivos reais do corpus liberados; passa
    conta e dado pessoal escritos com palavras comuns; perde a maior parte dos motivos plausíveis); (b) categoria
    escrita pelo código (fecha o vazamento por construção e deixa o custo independente do vocabulário; a Lia explica
    menos: "por causa do veículo" em vez de "o veículo está acima da idade aceita"); (c) não contar motivo nenhum (só
    "não fez proposta"). Recomendo (b). **Decidido pelo CEO em 13/09/2026: opção (b), implementada na rodada 7**, com
    duas categorias só (`veiculo` e `regiao`), o perfil do segurado e do condutor fora de categoria, e na dúvida o
    genérico. Ver "A regra do motivo".
28. **"Segurado com restrição. Declinando cálculo." passa pela regra do motivo. Para o CEO decidir.** É igual em
    forma a "Restrição técnica para o Segurado", que está no corpus. Pode ser restrição de crédito de um segurado
    que não é quem conversa. Tirar "segurado" do vocabulário recusa também a entrada do corpus. A quinta revisão
    achou a mesma forma com o condutor ("Condutor principal com restrição.", 6 de 6 de dado pessoal passam); a
    opção (b) da decisão 27 cobre os dois. **Decidido com a 27 (rodada 7):** segurado, condutor e os outros termos da
    pessoa levam ao genérico, inclusive "400 - Restrição técnica para o Segurado", do corpus.
29. **A regravação do handle pela passada seguinte (classe da #418) também apaga `LOTES_KEY` e `PRECOS_KEY`.** A
    quarta revisão reproduziu, com duas passadas sobre o mesmo handle, uma lista da Lia a mais além das duplicatas
    da própria #418. Declarado, sem conserto: é a mesma escrita do `record_attempt!` que a #418 trata.
30. **A lista que sai de novo segue a progressão das tentativas; só a primeira emissão pede o intervalo curto**
    (rodada 7). A consulta seguinte à emissão confere o aceite, e a primeira pede o intervalo curto
    (`confirmar_logo`, 3 s na progressão padrão) para a execução não ficar viva à toa. Se a lista não foi aceita, a
    falha está no banco ou no publicador, e repetir a cada 3 s gastaria as 60 tentativas em cerca de 3 min, antes do
    prazo de 7 min; na progressão, a nova tentativa vai até o prazo, como qualquer passada do motor.
31. **A anterior que falhou (`failed`) entra na lista da mais nova** (rodada 7). Até a rodada 6 só a `done` entrava.
    A que falhou depois de a fala prometer a lista é o estado da decisão 7: a promessa foi feita, e o pedido seguinte
    a cumpre. A `blocked` (freio do operador) e a `discarded` continuam fora.
32. **`publicacao_vale?` pergunta só pela lista levada** (rodada 7). A exceção "a lista já entregue vale" existia para
    a barreira da mais nova despachada, que saiu (decisão 23). Com ela fora, recusar a republicação de uma lista que
    já é mensagem não muda nada ao cliente (a mensagem já está lá), e a exceção deixou de ter efeito.
33. **O encerramento publica a lista** (rodada 7). `closing_deliveries` devolve a lista que ainda vale e não foi aceita,
    no prazo, nas tentativas e no varredor (este com `trabalho_novo: false`: a lista não chama o portal). Até a rodada 6
    devolvia `[]`, e a lista que não saiu até o prazo não saía mais. Sem frase: os textos de classe continuam vazios.
34. **As duas falas da categoria ao modelo** (`MOTIVOS`, rodada 7) dizem de onde é o motivo e que não se sabe mais
    que isso, e mandam contar com as palavras da Lia sem acrescentar detalhe. Não são frase ao cliente: são texto ao
    modelo, como `SEM_MOTIVO`.
35. **Um anexo por chave, por turno** (`Tools::Delivery#anexar`, rodada 8). A rodada de ferramentas do modelo pode chamar
    a ferramenta duas vezes no mesmo turno; a segunda troca o anexo, no lugar dele, pela lista com os códigos das duas
    (`dados` guarda os já anexados), e o cliente recebe uma lista só. Em turnos diferentes, cada pergunta recebe a sua.
36. **A resposta e os anexos na mesma transação, nas entregas clássica e em voz** (`post_reply_and_anexos!` dentro do
    `with_lock`, rodada 8). Saem todos ou nenhum, e o `already_replied?` do retry vê todos (o anexo leva o mesmo
    `autonomia_reply_to_message_id`). O custo: a gravação da lista que falha desfaz a fala, e o turno cai em
    `falha_no_turno` (silêncio, e as execuções assíncronas aceitas no turno descartadas), como a gravação da fala que
    falha na `main`; o turno com anexo faz uma escrita a mais nessa transação (N3).
37. **Na entrega humanizada, cada anexo é um pedaço inteiro no fim da cadeia** (rodada 8), com a pausa mínima de um
    pedaço (`HUMANIZE[:min_chunk_delay_ms]`, 900 ms): o texto é do sistema e não há digitação a imitar.
    `@expected_chunks` conta os anexos. Resposta que o quebrador não quebra vai pelo caminho clássico, com os anexos, e
    `@expected_chunks` fica zero, como na `main`.
38. **Na voz, os anexos saem como texto depois do áudio** (rodada 8), no mesmo lock; com a síntese falhando, a fala em
    texto e depois os anexos.
39. **No turno mudo, a gravação do anexo não derruba o despacho** (rodada 8). O anexo sai sozinho, pelo caminho clássico,
    sob o lock, com `still_eligible?` e `already_replied?`, sem evento `replied`. A primeira versão da rodada deixava a
    falha subir até `falha_no_turno`, que descarta a execução assíncrona aceita no mesmo turno, e a sonda da rodada
    mostrou a execução `discarded` onde o mesmo turno sem anexo a despacha. A gravação passou a ser best-effort: a falha
    vai ao log (só a classe) e o despacho segue.
40. **Sem contexto de entrega, erro nomeado** (`lista_indisponivel_nesta_superficie`, pelo registro de recusa, rodada 8).
    A ferramenta continua no catálogo do Testar, do Copiloto e do playground, como toda nativa: sumir faria o Testar
    mentir sobre o agente de produção.
41. **O que o modelo recebe é estado** (rodada 8): quantas seguradoras fizeram proposta (número, sem nome), se a lista vai
    anexada e os avisos (`PARTE_A_CAMINHO`, `AINDA_CORRENDO`, `HA_SEM_PROPOSTA`, `SEM_BONUS`). Com `seguradora`: o nome
    de cada nomeada, o desfecho e a categoria escrita. Nunca valor, nunca texto do portal, nunca travessão.
42. **O molde do veículo exige o nome do veículo** (rodada 8). "Categoria tarifária não aceita." cai no genérico:
    "categoria", "tipo" e "idade" também servem para a pessoa e para a cobertura.
43. **Texto que não é String UTF-8 válida vai ao genérico antes da transliteração** (rodada 8). A revisão da rodada 7 mostrou
    `transliterate` levantando com UTF-16 e ASCII-8BIT, que o `JSON.parse` do conector não produz.
44. **`a_caminho` fica** (decisão 24, rodada 8): sem ele, o lote adiado pela fala do turno da cotação e a lista da Lia
    pedida nesse intervalo levariam o mesmo preço duas vezes.
45. **P2-3 fora desta PR** (decisão do coordenador, rodada 8): a publicação adiada que falha uma vez e não tenta de novo é
    da `main` e muda o motor de todas as entregas adiadas. Issue **#425**.

## Riscos de regressão verificados, e como

| Risco | Como |
|---|---|
| Coluna "Com preço" do Super Admin | `medida_spec`: com a chave nova e 12 preços guardados, `seguradoras_com_preco` continua 11 (`entregues`); a ferramenta da Lia não abre execução (rodada 8) |
| Encerramento e fecho iguais | `Fecho`, `Comparativo#fechar`, `Encerramento` e o `closing_deliveries` da cotação sem alteração (o da ferramenta da Lia saiu com o desenho assíncrono, na rodada 8); as suítes da fatia 1 (`*_fecha_sem_esperar_o_portal_spec`, `async_run_job_encerramento_parcial_spec`, `encerramento_spec`, `nenhum_estado_mudo`) passam |
| Ferramenta nova com o especialista desligado | `answerer_resultado_da_cotacao_spec` |
| Schema strict | `openai_schema_spec` (laço do catálogo + exemplo nomeado: uma propriedade, `required == ['seguradora']`, sem `anyOf`) |
| Humano na conversa | `answerer_resultado_da_cotacao_spec`: com responsável humano a Lia não responde e a ferramenta não roda; `responder_anexos_spec`: humano que assume durante a chamada ao modelo não recebe fala nem lista. Humano que assume no meio da cadeia humanizada: a cadeia para e a lista não sai, nem em nota privada (N2 da rodada 8) |
| Execuções em voo no deploy | cotação correndo sem a chave ganha o resultado na consulta seguinte (`insurance_quote_resultado_spec`); a ferramenta lê essa linha como "ainda sem preço" e a encerrada sem a chave como "não guardado" (`insurance_quote_result_spec`); pedido repetido da linha sem a chave conta pelo contador (exemplos da entrega 10, inalterados) |
| `nenhum_estado_mudo` | estendido: confirmação curta + `done` com fecho; a ferramenta da Lia anexa os itens ao turno sem frase pronta, é síncrona e não abre execução (rodada 8); texto ao modelo presente em todo estado sem preço |
| Pedido repetido não mente | `bound_pedido_repetido_spec`: sem entrega e com preço guardado não diz "0 resultados"; com entrega diz o número; só recusas é tentativa nova; janela de 24 h vale igual |
| Catálogo de outros agentes | `registry_spec` (tipo `custom` lê a config), `answerer_resultado_da_cotacao_spec` |
| Registro de recusa | `recusa_registro_spec` com o gatilho `insurance_quote_result.rb#call#1` (`lista_indisponivel_nesta_superficie`, rodada 8) |
| Contrato de nível | `base_contrato_de_nivel_spec` com `resultado_guardado?` (`aceite`, `handle_de_abertura` e `publicacao_vale?` saíram na rodada 8) |
| Nenhum texto do portal ao modelo nem ao banco (rodada 7) | `insurance_quote_result_spec`: as 39 mensagens do corpus, no `kind` e no status do conector, e os 59 textos das revisões numa cotação só, perguntadas uma a uma: o modelo lê só `SEM_MOTIVO` ou as falas de `MOTIVOS`, nenhum texto aparece, e conta e pessoa saem no genérico; `resultado_por_seguradora_spec`: nenhum desses textos no JSON guardado |
| Palavra ao cliente em todo estado (rodada 8) | `responder_anexos_spec` e `answerer_resultado_da_cotacao_spec`: a fala e a lista nos três caminhos, o turno mudo (a lista sozinha; com assíncrona aceita e a gravação da lista falhando, o despacho segue), o retry e o humano; sem anexo, os specs do `Responder` que já existiam passam sem mudança. Os casos em que a lista prometida não chega: N1 a N5 da seção da rodada 8 |
| Motor assíncrono igual ao da `main` (rodada 8) | `git diff 5742de5fcd --stat` sobre o motor: 5 arquivos, só a gravação do resultado (pedido repetido) e a confirmação curta; `async_publisher_spec` e `tool_run_spec` iguais aos da `main`, passando |

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
- Rodada 4, nos specs novos desta PR: `resultado_por_seguradora_spec` monta o motivo do teto com palavras do
  vocabulário (o de "x" deixou de ser guardado) e passa a exigir que ele seja guardado, com o limite em 8.000
  bytes; a promessa "Nunca fale de login, senha ou permissão" do `builder_instrucao_do_principal_promessas_spec`
  passou a exigir também que a regra recuse os três termos num texto de risco.
- Rodada 7, nos specs novos desta PR: `motivo_da_recusa_spec` reescrito para a categoria (o do vocabulário, com 264
  exemplos, deu lugar a 195), com os textos em `spec/support/textos_do_motivo.rb`; `resultado_por_seguradora_spec`
  guarda a categoria e não o texto, com os limites de tamanho refeitos; `insurance_quote_result_spec` e
  `answerer_resultado_da_cotacao_spec` com a categoria, a lista que sai até ser aceita, o desconto e a última
  tentativa; as passadas de publicação ganharam a terceira (a que confere o aceite); "o turno mudo e o prazo
  esgotado" passou a esperar a lista, sem frase; "a lista adiada que chega ao teto antes da leitura do pedido novo"
  passou a sair, com a nova sem repetir os códigos dela; `builder_instrucao_do_principal_promessas_spec` com o
  parágrafo novo do motivo; `insurance_quote_nenhum_estado_mudo_spec` com a terceira passada e o exemplo da lista no
  encerramento.
- Rodada 8 (a troca de desenho): `insurance_quote_result_spec` e `answerer_resultado_da_cotacao_spec` reescritos para a
  ferramenta síncrona e o anexo; `answerer_resultado_da_cotacao_lotes_spec` e `insurance_quote_nenhum_estado_mudo_spec`
  adaptados (a Lia anexa em vez de abrir execução); `motivo_da_recusa_spec` reescrito para o molde fechado, com as 31
  sondas da revisão da rodada 7 em `SondasDoMotivo::REVISAO_7` (`spec/support/textos_do_motivo.rb`, onde as mensagens
  31, 32 e 33 do corpus passaram a genérico); `builder_instrucao_do_principal_promessas_spec` com o parágrafo novo e dez
  promessas; `recusa_registro_spec` com o gatilho `insurance_quote_result.rb#call#1`; `base_contrato_de_nivel_spec` só
  com `resultado_guardado?`; `async_publisher_spec` e `tool_run_spec` voltaram aos da `main`; `medida_spec` perdeu o
  exemplo da execução da Lia. Novos: `responder_anexos_spec` (16 exemplos) e `delivery_spec` (4).

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
| CI da PR #424 em `f727ce1844` (run 34776202500) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Depois da revisão (rodada 3) | o recorte da linha de base | 1935 exemplos, 0 falhas; md5 de `app/` igual antes e depois | 0 |
| Depois da revisão (rodada 3), fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `cc4587e32e` (run 34779930764) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Depois da revisão (rodada 4) | o recorte da linha de base | 1963 exemplos, 0 falhas; md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois | 0 |
| Depois da revisão (rodada 4), fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `a12b1e0ca3` (run 34783889357) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Depois da revisão (rodada 5) | o recorte da linha de base | 1989 exemplos, 0 falhas; md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois | 0 |
| Depois da revisão (rodada 5), fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `311f674562` (run 34786462640) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Depois da revisão (rodada 6) | o recorte da linha de base | 1992 exemplos, 0 falhas; md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois | 0 |
| Depois da revisão (rodada 6), fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `260be4f385` (run 34789119201) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Rodada 7, os specs afetados (antes dos ajustes de formatação pedidos pelo RuboCop; o recorte abaixo roda depois deles) | os 12 arquivos da ferramenta da Lia, do motivo, do resultado guardado, das promessas, da integração, dos lotes, do `nenhum_estado_mudo`, da Medida, do registro de recusa, do schema e do `builder_spec` | 595 exemplos, 0 falhas | 0 |
| Rodada 7 | o recorte da linha de base | 1941 exemplos, 0 falhas (51 a menos que a rodada 6: o spec do vocabulário do motivo, 264 exemplos, deu lugar ao da categoria, 195, e entraram 18 exemplos novos); md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois (`51c17d78782abab21005184915b5d2eb`) | 0 |
| Rodada 7, fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |
| CI da PR #424 em `05450ad1ce` (run 34792789781) | suíte inteira do projeto (8 shards), RuboCop, Vitest, ESLint, Brakeman | 12 jobs `success` | — |
| Rodada 8, os specs alterados ou novos desde `5742de5fcd` (os 19 `_spec.rb` da lista do RuboCop) | 19 arquivos | 601 exemplos, 0 falhas | 0 |
| Rodada 8 | o recorte da linha de base | 1885 exemplos, 0 falhas; md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois (`350e3b378f75b0034035ffa4b2511a1a`) | 0 |
| Rodada 8, fora do recorte | os mesmos 118 de antes | 118 exemplos, 0 falhas | 0 |

- `RAILS_ENV=test bundle exec rails zeitwerk:check`: "All is good!", exit 0 (em `9c0bdcb8be`, `f727ce1844` e
  depois da rodada 3).
- RuboCop com lista explícita: 20 arquivos de `app/` (exit 0), 17 specs (exit 0), 4 arquivos do refactor
  (exit 0), 0 ofensas. Rodadas 2 e 3: os 38 `.rb` alterados desde `5742de5fcd`, 0 ofensas, exit 0. Rodada 4: os
  40 `.rb` alterados ou novos desde `5742de5fcd`, 0 ofensas, exit 0. Rodada 7: os 41 `.rb` alterados ou novos desde
  `5742de5fcd`, 0 ofensas (`--format json`, `offense_count` 0), exit 0; `zeitwerk:check` "All is good!", exit 0.
  Rodada 8: os 40 `.rb` alterados ou novos desde `5742de5fcd` (20 de `app/`, 19 specs e o suporte do motivo), 0 ofensas
  (`--format json`, `offense_count` 0, `inspected_file_count` 40), exit 0; `zeitwerk:check` "All is good!", exit 0.

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
| Duas chamadas na mesma rodada: a segunda abertura supersedia a primeira, e só a segunda lista saía; a decisão 13 afirmava o contrário | P2 | `handle_de_abertura` une os códigos da execução anterior sem entrega (decisão 17; a união foi para o `poll` na rodada 3); decisão 13 corrigida |
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

## Rodada 3: a revisão de verificação de `f727ce1844`

Revisor independente (agente com contexto próprio, só leitura), com sondas pelo caminho real guardadas fora do
repositório. Confirmou corrigidos o P1 da rodada 2 para os textos apontados, os dois P2 e o P3.1, pelas mesmas
sondas. Achou 1 P1 condicional, 1 P2 e 5 P3 novos. Os specs que ele rodou: 292 exemplos, 0 falhas (os seis da
rodada 2) e 467, 0 falhas (24 de motor, publicador, bound, encerramento e cotação), exit 0.

| Achado | Severidade | O que mudou |
|---|---|---|
| A regra do motivo ainda liberava conta e valor: 22 textos de conta que saem `risco` do classificador real ("Descredenciado", "Desabilitado", "Recadastramento" derrubados pelo `\b` dos radicais; "Conta suspensa", "Entre novamente no portal", "Faça logoff", "Licença do multicálculo vencida") e 7 de valor sem `R$` ("Prêmio mínimo de 800", "1,5 milhão", "trezentos mil") | P1 (condicional: nenhum está no corpus) | A regra passou a exigir o objeto do risco e nenhum dígito depois do código do começo (decisão 16); os radicais sem `\b` onde há prefixo; os 29 textos recusados; os 14 do corpus liberados |
| Com a lista adiada pela fala do turno, o pedido novo publicava a mesma lista duas vezes (reproduzido pelo caminho real); a decisão 17 dizia cobrir | P2 (existia desde `2a348f4804`) | União no `poll`, pela `sequence`, e `publicacao_vale?` barrando a lista sem mensagem quando outra mais nova já foi despachada (decisão 17); três exemplos de integração |
| A lista duplicada quando o processo morre entre a mensagem e o `record_delivery!` | P3 | Coberto pela `sequence`, gravada com a mensagem; exemplo de integração |
| `NAO_CHEGOU` contradizia a frase de envio incerto | P3 | `ENVIO_INCERTO` (decisão 21) |
| A união calculada fora do lock consultivo perdia a primeira lista com dois turnos simultâneos | P3 (só leitura) | A união saiu da abertura |
| A marca `<REDACTED>` do conector passava | P3 | Padrão `redigido`, e o item 4 da regra |
| O custo da regra (motivos de risco recusados) não estava declarado | P3 | Declarado no spec ("o custo, declarado") e na decisão 16 |

Onde o revisor olhou e não achou defeito: as outras ferramentas com o handle de abertura (herdam `{}`), o índice
único por conversa e ferramenta, o `run:` no caminho de produção do motor, a coerência de `publicacao_vale?` com
cotação nova `pending` e `running`, o custo das expressões (0,10 ms no pior caso de 300 caracteres), as chamadas
da mesma rodada em sequência e a regressão de `cotar_seguro`.

### Mutações da rodada 3

| # | Mutação | Resultado |
|---|---|---|
| T01 | motivo sem exigir objeto do risco | 10 falhas |
| T02 | o código do portal não sai do texto | 8 falhas |
| T03 | código do portal sem exigir hífen | 4 falhas |
| T04 | sem o padrão de dígito | 11 falhas |
| T05 | credencial volta a exigir fronteira ("descredenciado" passa) | 1 falha |
| T06 | habilitação volta a exigir o "h" ("desabilitado" passa) | 2 falhas |
| T07 | bloqueio volta a só "bloqueado" | 1 falha |
| T08 | "conta" casando "por conta de" | 1 falha |
| T09 | "segurado" casando "seguradora" | 2 falhas |
| T10 | sem o padrão de portal | 2 falhas |
| T11 | sem a marca de redação do conector | 2 falhas |
| T12 | lista sem os códigos das anteriores | 5 falhas |
| T13 | leitura das anteriores sem parar na que virou mensagem | 2 falhas |
| T14 | lista levando anterior sobre outra cotação | 1 falha |
| T15 | lista levando anterior falhada, descartada ou barrada | 1 falha |
| T16 | `publicacao_vale?` sem barrar a anterior sem mensagem | 3 falhas |
| T17 | `publicacao_vale?` barrando pela mais nova ainda `pending` | 1 falha |
| T18 | `publicacao_vale?` barrando a lista que já virou mensagem | 1 falha |
| T19 | `publicacao_vale?` barrando pela mais nova sobre outra cotação | 1 falha |
| T20 | envio incerto volta a "não chegou" | 2 falhas |
| T21 | leitura das anteriores fora do lock da conversa | **sobrevive** (esperado; ver "O que NÃO foi verificado") |

**20 de 21 reprovadas**; a sobrevivente é a do lock, declarada. md5 de `app/` igual antes e depois.

## Rodada 4: a revisão de verificação de `cc4587e32e`

Revisor independente (agente com contexto próprio, só leitura), com sondas pelo caminho real, a cadeia humanizada
real (`ChunkedDeliveryJob`) e o classificador real do conector sobre 146 textos e o corpus inteiro. Achou 2 P2 (um
condicional) e 6 P3. Os specs que ele rodou: 304 exemplos da rodada e 1029 de regressão (38 arquivos), 0 falhas,
exit 0.

| Achado | Severidade | O que mudou |
|---|---|---|
| A mesma seguradora em duas listas sem o cliente pedir duas vezes: o lote de preços da cotação adiado pela fala do turno e a lista da Lia pedida nesse intervalo (reproduzido, pelo resultado inteiro e por uma seguradora) | P2 | `LOTES_KEY` e `ResultadoDaCotacao#a_caminho` (decisão 24); spec de integração novo `answerer_resultado_da_cotacao_lotes_spec` e exemplo em `nenhum_estado_mudo` |
| A regra do motivo julgava por palavra: conta colada a uma linha de risco passava, e uma entrada real do corpus (risco colado a erro de sistema) era liberada inteira; o spec guardava essa entrada truncada | P2 (condicional) | Lista de liberação por palavra, só letras latinas (decisão 16); o corpus do spec passou a ser o do conector, entrada por entrada, com as 26 de outro `kind` |
| "por conta" liberava qualquer frase | P3 | Coberto pelo vocabulário ("conta" não está nele) |
| Dígito fora do ASCII chegava ao modelo; o código do começo aceitava letras sem teto | P3 | `CARACTERES` (só letras latinas e pontuação) e até três letras no código |
| Número por extenso, conta em inglês e dado pessoal liberados | P3 | Coberto pelo vocabulário; padrões de guarda para dezena, unidade, bilhão, milhar, moeda, inglês, operador, CPF |
| A execução `pending` de um turno morto tornava o residual 1 de minutos, não de segundos | P3 | A supersedida só entra se foi despachada ou é do mesmo turno (decisão 25) |
| Uma falha só na publicação da lista nova perde as duas listas | P3 | Declarado (decisões 7 e 23); o conserto sugerido muda o gancho do motor de todas as ferramentas |
| Lista com pendência de envio saía duas vezes | P3 (classe anterior) | `lista_entregue?` (decisão 26) |

Onde o revisor olhou e não achou defeito: a premissa da `sequence` (só o publicador grava o token e avança, na
mesma transação e sob o lock; a reconciliação preserva os dois), a cadeia humanizada real com uma e com três listas,
o varredor com lista adiada, a ordem dos locks, os 39 textos do corpus contra o classificador real, e a regressão
fora da ferramenta da Lia e da regra do motivo.

### Mutações da rodada 4

| # | Mutação | Resultado |
|---|---|---|
| U01 | motivo sem o vocabulário | 13 falhas |
| U02 | motivo sem a conferência dos caracteres | 4 falhas |
| U03 | o código do portal não sai do texto | 7 falhas |
| U04 | código do portal com letras sem teto | 2 falhas |
| U05 | motivo sem exigir objeto do risco | 3 falhas |
| U06 | vocabulário com palavra de conta ("senha") | 1 falha |
| U07 | vocabulário com número por extenso ("noventa") | 1 falha |
| U08 | motivo sem os termos de conta e de valor na conferência | **sobrevive** (esperado: o vocabulário já recusa essas palavras, e U06 e U07 guardam o vocabulário) |
| U09 | lista leva a supersedida de outro turno nunca despachada | 1 falha |
| U10 | lista sem a supersedida do mesmo turno | 2 falhas |
| U11 | lista entregue ignorando a pendência de envio | 1 falha |
| U12 | lista sem os códigos das anteriores | 7 falhas |
| U13 | leitura das anteriores sem parar na entregue | 2 falhas |
| U14 | `publicacao_vale?` sem barrar a anterior não entregue | 4 falhas |
| U15 | `publicacao_vale?` barrando pela mais nova `pending` | 1 falha |
| U16 | `publicacao_vale?` barrando pela mais nova sobre outra cotação | 1 falha |
| U17 | resultado inteiro leva o preço a caminho | 9 falhas |
| U18 | pedido por seguradora leva o preço a caminho | 2 falhas |
| U19 | lote com pendência de envio conta como entregue | 1 falha |
| U20 | lote a caminho sem os códigos gravados não segura nada | 1 falha |
| U21 | lote não aceito conta como a caminho | 1 falha |
| U22 | a cotação não grava os códigos do lote | 1 falha |
| U23 | envio incerto volta a "não chegou" | 2 falhas |
| U24 | leitura das anteriores fora do lock da conversa | **sobrevive** (esperado; ver "O que NÃO foi verificado") |

**22 de 24 reprovadas**; as duas sobreviventes são as declaradas. md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes
e depois.

## Rodada 5: a revisão de verificação de `a12b1e0ca3`

Revisor independente (agente com contexto próprio, só leitura), com sondas pelo caminho real (motor, `Responder`,
publicador, `AsyncPublishJob`, varredor e `RetomadaDeEnvio`; a fila recusando o `SendReplyJob` pelo
`FilaDeEnvioHelper`) e o classificador real do conector. Achou 3 P2 (um condicional) e 6 P3. Os specs que ele rodou:
307 exemplos da rodada e 1170 de regressão (44 arquivos), 0 falhas, exit 0.

| Achado | Severidade | O que mudou |
|---|---|---|
| Lote publicado na hora com a fila de envio fora: pendência de envio sem aceite, a lista da Lia saía e o varredor reenviava o lote (preço duas vezes, reproduzido) | P2 | A mensagem do lote com pendência conta como a caminho com aceite ou sem (decisão 24); exemplo de integração |
| Lote aceito cuja publicação adiada morre ficava "a caminho" para sempre, e a Lia prometia o envio a cada pergunta (reproduzido) | P2 | `JANELA_DO_LOTE` com a hora de emissão em `LOTES_KEY` (decisão 24); exemplo de integração com o relógio adiantado |
| Conta escrita só com palavras do vocabulário passava (16 de 16 sintéticos) | P2 (condicional) | Tiradas do vocabulário a segunda pessoa e as palavras de conta (15 de 16 recusados); a causa raiz vai para o CEO (decisão 27) |
| Letra latina que não se translitera virava separador e sumia da conferência | P3 | Transliteração com `#` |
| A regravação da #418 também apaga `LOTES_KEY` e `PRECOS_KEY` | P3 | Declarado (decisão 29) |
| O varredor abandonava a lista pendente anterior antes de a nova levá-la | P3 | `listas_absorvidas` (decisão 26) |
| "Agora" era quase sempre falso no texto do preço a caminho | P3 | "na fila de envio" |
| Lote sem os códigos gravados faz a Lia dizer "na fila" também para preço já entregue | P3 | Declarado: transitório (em voo no deploy, ou processo morto antes do `record_attempt!`) |
| "Segurado com restrição" passa | P3 | Para o CEO (decisão 28) |

Onde o revisor olhou e não achou defeito: lote aceito e adiado, e o que só depois ganhou pendência; vários lotes com
parte a caminho; a identidade do lote igual à do publicador; humano assumindo (nota privada conta como entregue);
cotação nova; em voo no deploy; a decisão 25; quem regrava `LOTES_KEY`; a regressão de `cotar_seguro` (fecho,
comparativo, encerramento, pedido repetido, Medida e Super Admin).

### Mutações da rodada 5

| # | Mutação | Resultado |
|---|---|---|
| V01 | lote com pendência de envio e sem aceite não conta como a caminho | 2 falhas |
| V02 | lote aceito sem mensagem a caminho para sempre (sem janela) | 3 falhas |
| V03 | lote sem hora de emissão sempre recente | 1 falha |
| V04 | a cotação não grava a hora de emissão do lote | 1 falha |
| V05 | a lista não grava quais anteriores levou | 4 falhas |
| V06 | `publicacao_vale?` barrando por qualquer mais nova, levada ou não | 3 falhas |
| V07 | lista sem os códigos das anteriores | 7 falhas |
| V08 | leitura das anteriores sem parar na entregue | 2 falhas |
| V09 | a transliteração volta a trocar o desconhecido por "?" | 4 falhas |
| V10 | o vocabulário volta a ter "seu" | 1 falha |

**10 de 10 reprovadas**, md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois.

## Rodada 6: a revisão de verificação de `311f674562`

Revisor independente (agente com contexto próprio, só leitura, banco de teste próprio apagado no fim), com sondas
pelo caminho real e o classificador real do conector sobre 134 textos. Confirmou corrigidos os três achados da
rodada anterior (F1, F2, F6). Achou 1 P2 condicional e 5 P3. Os specs que ele rodou: 1246 exemplos em três grupos
(rodada, motor e publicador, cotação e Super Admin), 0 falhas, exit 0; CI de `311f674562` com 12 checks `SUCCESS`.

| Achado | Severidade | O que mudou |
|---|---|---|
| A regra do motivo deixa passar conta, permissão e dado pessoal escritos com palavras do vocabulário (25 de 28 e 6 de 6) | P2 (condicional) | Números na decisão 27, para o CEO |
| A absorção não era transitiva, e a pendência abandonada pelo varredor fazia a lista parecer entregue: a Porto prometida não saía (reproduzido) | P3 | A lista leva também as que as anteriores já tinham levado (decisão 26); exemplo na ferramenta |
| A lista adiada que chega ao teto entre o despacho e o `poll` do pedido novo saía, e a nova também (reproduzido) | P3 | Lista sem mensagem é barrada também pela mais nova despachada (decisão 23); exemplo de integração |
| Lote retomado depois de `JANELA_DO_LOTE` num incidente de fila sai junto com a lista da Lia (reproduzido com relógio) | P3 (condicional) | Declarado em "O que NÃO foi verificado" |
| Lote com pendência de envio mais velha que a janela do varredor ficava "na fila" para sempre (reproduzido) | P3 (baixa probabilidade) | A pendência só conta dentro de `ReapStaleRunsJob::ENVIO_PENDENTE_JANELA`; exemplo na ferramenta |
| O custo da retirada de palavras da rodada 5 não estava declarado (31 de 32 motivos plausíveis) | P3 | Declarado na decisão 27 |

Onde o revisor olhou e não achou defeito: os achados F1, F2 e F6 da rodada anterior, rodados de novo; a falha
silenciosa de `merge_handle!` (só com a execução fora de `running`, e aí a publicação é recusada ou a passada é a
mesma); `listas_absorvidas` sobrevivendo ao `record_attempt!`, ao `finish!` e ao `reforcar_aceites!`; a ordem dos
locks (conversa e depois a linha da execução, sem inversão); o lote abandonado pelo varredor; o texto ao modelo nos
estados novos; a transliteração com `#` e a retirada do código do portal.

### Mutações da rodada 6

| # | Mutação | Resultado |
|---|---|---|
| W01 | lista sem levar as que as anteriores já tinham levado | 1 falha |
| W02 | lista sem mensagem não barrada pela mais nova despachada | 2 falhas |
| W03 | lista com mensagem pendente também barrada pela mais nova despachada | 1 falha |
| W04 | mais nova `pending` barra a lista sem mensagem | 1 falha |
| W05 | lote com pendência de envio a caminho mesmo depois da janela do varredor | 1 falha |

**5 de 5 reprovadas**, md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois. **A rodada 6 não teve revisão
independente**: os consertos dela foram cobertos por exemplo, mutação e suíte, não por um revisor.

## Rodada 7: as decisões do CEO sobre a PR #424 (13/09/2026)

Os quatro pontos que a rodada 6 deixou para o CEO, decididos por ele e implementados na mesma branch. Esta rodada não
partiu de uma revisão adversarial nova.

| Ponto | Decisão | O que mudou |
|---|---|---|
| Agentes de cotação em produção | fato verificado pelo coordenador em 13/09/2026: só o agente 24 (Lia, conta 16), com as quatro ferramentas | decisão 9; saiu de "O que NÃO foi verificado" |
| Decisões 27 e 28 (o motivo) | opção (b): o código classifica o motivo em `veiculo` ou `regiao`, o modelo recebe só a categoria; perfil da pessoa, conta da corretora e tudo que não for `risco` vão ao genérico; na dúvida, genérico | `MotivoDaRecusa.categoria` (o vocabulário e as regras de liberação saíram), `ResultadoPorSeguradora` guarda a categoria, `ResultadoDaCotacao#motivo` só lê categoria, `InsuranceQuoteResult::MOTIVOS`, `principal.md` |
| Decisão 7 (falha depois do aceite) | a anterior só conta como levada depois do aceite da nova; falha passageira tenta de novo pelas tentativas do motor; cotação nova cala; resíduos declarados | `Listas` (`lista`, `lista_aceita?`, `lista_levada?`, desconto), `poll` em `running` até o aceite, `closing_deliveries` |
| Decisão 19 (turno mudo) | aceita como está | declarada na decisão 19 |

### O corpus do conector, pela categoria

As 39 mensagens de `test/fixtures/agger/motivos-de-recusa.sanitized.json` (`autonomia-adapters`), conferidas uma a uma
contra o arquivo (texto, `kind` e status iguais), com a categoria que `MotivoDaRecusa.categoria` devolveu:

| # | `textoLimpo` | `kind` do conector | status | categoria |
|---|---|---|---|---|
| 1 | Risco sem aceitação para este cenário nesta seguradora. | `risco` | `declined` | genérico |
| 2 | Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro? | `risco` | `declined` | genérico |
| 3 | Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida | `risco` | `declined` | `veiculo` |
| 4 | Aceitacao Restrita, cobertura auto nao permitida para este modelo. | `risco` | `declined` | `veiculo` |
| 5 | O veículo não possui aceitação para a categoria tarifária informada. | `risco` | `declined` | `veiculo` |
| 6 | Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o risco deste orçamento. | `risco` | `declined` | genérico |
| 7 | O sistema de cálculo está indisponível, tente novamente em alguns instantes. | `passageiro` | `declined` | genérico |
| 8 | Serviço indisponível, tente novamente mais tarde | `passageiro` | `declined` | genérico |
| 9 | Houve uma instabilidade ao realizar o cálculo nesta seguradora, tente novamente em breve. | `passageiro` | `declined` | genérico |
| 10 | Usuário não possui acesso a funcionalidade. Por favor, verifique suas permissões no site da seguradora. | `credencial` | `auth_required` | genérico |
| 11 | Login ou senha incorreta. Confira suas credenciais de acesso. | `credencial` | `auth_required` | genérico |
| 12 | Erro ao processar o cálculo do prêmio | `outro` | `declined` | genérico |
| 13 | Desmoronamento - Para contratação desta cobertura é necessário enviar para Análise Técnica. | `outro` | `declined` | genérico |
| 14 | O Nome informado não corresponde ao CPF cadastrado. Por favor, verifique e tente novamente. | `outro` | `declined` | genérico |
| 15 | 400 - Restrição técnica para o Segurado | `risco` | `declined` | genérico |
| 16 | O valor informado de R$ 10.000,00 para a cobertura Roubo Residencial Condominos, Cobertura é invalido. O mínimo aceito | `outro` | `declined` | genérico |
| 17 | Corretor não encontrado. Por favor, selecione um corretor válido no cadastro da seguradora. | `credencial` | `declined` | genérico |
| 18 | Necessário contratar primeiro uma das coberturas: '000510026 - Responsabilidade Civil Operacoes', '000510304 - Resp Civ | `outro` | `declined` | genérico |
| 19 | [165456] - Contratação da Cobertura Desmoronamento para o GRUPO ESCRITORIOS ATIVIDADE DEMAIS ESCRITÓRIOS está fora da p | `outro` | `declined` | genérico |
| 20 | Para a Cobertura Responsabilidade Civil Empregador, Obrigat ria a contrata o da Cobertura Responsabilidade Civil Est | `outro` | `declined` | genérico |
| 21 | A cobertura de INCENDIO / QUEDA DE RAIO / EXPLOSAO / IMPLOSAO ACIDENTAL / FUMACA / QUEDA DE AERONAVES não pode ser cont | `outro` | `declined` | genérico |
| 22 | LMI COB RC OBRIGATORIA PARA DANO MORAL | `outro` | `declined` | genérico |
| 23 | Houve um erro ao realizar este cálculo. | `outro` | `declined` | genérico |
| 24 | Não foi possível recuperar o valor dessa cotação. Por favor, tente novamente mais tarde. | `passageiro` | `declined` | genérico |
| 25 | O valor do capital segurado deve ser entre R$100,00 e R$1.000,00, limitado a 250 vezes o capital segurado da cobertura | `outro` | `declined` | genérico |
| 26 | Profissão deve ser especificada corretamente para que o cálculo prossiga. | `outro` | `declined` | genérico |
| 27 | Ocorreu uma divergencia entre a comissao informada e a comissao permitida. | `credencial` | `declined` | genérico |
| 28 | Tipo de veículo não aceito. | `risco` | `declined` | `veiculo` |
| 29 | Nenhum produto com seguro disponível para exibição. | `outro` | `declined` | genérico |
| 30 | Só é permitida a contratação de [Faróis, Lanternas e Retrovisor] para veículos até 20 anos. | `outro` | `declined` | genérico |
| 31 | [2005] - -Contratação não permitida - Ano Modelo do Veículo | `risco` | `declined` | `veiculo` |
| 32 | Moto de ano/modelo sem aceitação - RP | `risco` | `declined` | `veiculo` |
| 33 | [2159] - -Contratação não permitida - Categoria do Veículo | `risco` | `declined` | `veiculo` |
| 34 | UC00 - Risco fora das políticas de aceitação As Necessidades do Cliente, não foram salvas com sucesso, selecione nov | `risco` | `declined` | genérico |
| 35 | Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP | `risco` | `declined` | genérico |
| 36 | A cobertura "Impacto Veículos" não está disponível para esta cotação. | `outro` | `declined` | genérico |
| 37 | Ocorreu um erro ao calcular. Revise o formulario de calculo e tente novamente. | `outro` | `declined` | genérico |
| 38 | Origem da viagem deve ser especificada corretamente | `outro` | `declined` | genérico |
| 39 | Cálculo sem prêmio. | `outro` | `declined` | genérico |

`risco`: 13, com categoria 7 (todas `veiculo`). `passageiro`: 4, `credencial`: 4, `outro`: 18, nenhuma com categoria.
Os 59 textos das revisões (os 28 de conta da quinta revisão, os 6 de dado pessoal, "Senha expirou. Declinando
cálculo.", "Usuário fulano@corretora.com.br bloqueado." e os outros 23) saem todos genéricos, com `kind` `risco`. O
`motivo_da_recusa_spec` tem um exemplo por mensagem do corpus e por texto das revisões; o `insurance_quote_result_spec`
põe todos numa cotação e pergunta por cada seguradora: o modelo lê só `SEM_MOTIVO` ou uma das duas falas de `MOTIVOS`,
e nenhum texto aparece. **Isso prova que nenhum texto chega ao modelo, e não que conta e pessoa nunca viram
categoria:** 58 dos 59 não casam padrão de categoria nenhum (sonda S6 da revisão da rodada 7), e 31 textos escritos
para casar um atributo sem termo das listas saem com categoria (achado P3-1, em "O que NÃO foi verificado").

### A lista que sai até ser aceita

1. A passada que publica compõe a lista sob o lock da conversa (leva, desconta, para: ver o item 2 da ferramenta),
   grava em `lista` os códigos, as levadas e a identidade da entrega, e devolve `running` com a lista.
2. O motor publica e registra o aceite (`AsyncRunJob#deliver`). Recusada (erro de banco, publicador), nada é
   registrado.
3. A passada seguinte (`lista_vale?`): lista aceita ou já mensagem, `done`; outra mais nova já aceita a levou, `done`;
   a cotação lida deixou de ser a mais nova, `done` sem nada; senão, compõe e publica de novo. A primeira emissão pede
   o intervalo curto; a nova tentativa segue a progressão (decisão 30).
4. O prazo, as tentativas e o varredor passam por `closing_deliveries`, que publica a lista que ainda vale (decisão 33).
5. A anterior só é barrada (`publicacao_vale?`, `RetomadaDeEnvio`) pela mais nova que a levou e cuja lista já foi
   aceita ou já é mensagem. Até lá, a publicação adiada dela e a retomada do envio dela valem; se ela sair nesse
   intervalo, a nova a desconta na tentativa seguinte.

### Os resíduos da decisão 7

Cada um é um caso em que a regra "nunca duas vezes, e uma falha nunca perde as duas" não se cumpre inteira. **A
versão commitada em `05450ad1ce` dizia que nenhum deles deixava de levar palavra que a rodada 6 levava: a revisão da
rodada 7 mostrou que é falso** (R6, achado P2-1), e que R2 e R4 estavam descritos para menos (P2-3 e P2-2). As
correções abaixo são dessa revisão; os consertos estão abertos (ver "A revisão da rodada 7").

- **R1. A anterior que sai nos milissegundos entre a composição da nova e o aceite dela.** Turno 1 com a lista adiada
  pela fala; o cliente pede de novo; a passada da nova compõe (leva a anterior) e solta o lock; antes de o motor
  registrar o aceite da nova, o `AsyncPublishJob` da anterior (no teto, ou com a cadeia fechada) publica. A nova sai
  com os mesmos códigos: a mesma seguradora duas vezes. A janela vai da saída do lock da composição ao
  `EntregaAceita.registrar` da nova. Sem teste: precisa de duas conexões concorrentes.
- **R2. A publicação adiada, já aceita, que falha uma vez.** A lista é aceita adiada (o caso normal com a entrega
  humanizada ligada) e o `AsyncPublishJob` falha ao publicar: **uma falha basta**. O publicador transforma a exceção em
  `blocked` (`AsyncPublisher#publish`) e o job só reagenda `deferred` (`AsyncPublishJob#perform`), então não há
  retentativa, nem do Sidekiq. A lista não sai; se ela tinha levado uma anterior, as duas ficam sem sair. A versão
  commitada dizia "banco fora por mais tempo que as retentativas do Sidekiq": errado (achado P2-3, reproduzido nos dois
  SHAs, `260be4f385` e `05450ad1ce`). É a lacuna de toda entrega adiada do motor, também dos lotes de preço e do PDF
  (`AsyncRunJob#deliver`: "O job adiado ainda pode recusá-la depois (autorização caída, erro de banco), e nada aqui
  fica sabendo"). Autorização caída depois do aceite (agente desligado, conversa fora da allowlist) cala por desenho.
- **R3. A nova recusada em todas as tentativas e no encerramento.** O publicador recusa a lista nova até o prazo (7 min)
  ou as 60 tentativas, e de novo no encerramento. A nova não sai; a anterior, que a nova não chegou a levar, sai
  (teste "a falha até o prazo e no encerramento"). O que só a nova prometeu fica sem sair até um pedido seguinte, que a
  leva (decisão 31). É o estado da decisão 7, agora só depois de todas as tentativas.
- **R4. A anterior que sai antes da fala nova.** A lista anterior adiada vira mensagem depois de a execução nova abrir
  e antes de a fala nova ser postada. A nova a desconta; sem código sobrando, não publica nada, e a fala nova ("sai na
  lista depois da minha mensagem") vem depois da lista. **E com um pedido seguinte o preço sai de novo** (achado P2-2):
  a nova que descontou tudo fecha sem gravar `lista`, e a mais nova seguinte a leva pelos códigos do pedido dela
  (`codigos_da_lista` cai nos códigos do pedido quando `lista` não existe). Na rodada 6 a mais nova despachada barrava
  a anterior, e isso não acontecia.
- **R5. A anterior com envio pendente retomada antes de a nova compor.** A mensagem da anterior está no banco com
  pendência de envio, o cliente pede de novo, e a retomada (motor ou varredor) a reenvia antes da composição da nova.
  A mensagem foi criada antes de a nova abrir, e a nova não a desconta: os códigos pedidos de novo saem duas vezes.
  Mesma classe das "mensagens cruzadas" de "O que NÃO foi verificado".
- **R6. A anterior ainda `running` quando o pedido novo abre.** A abertura nova (`ToolRun.open!`) supersede a execução
  viva; a publicação adiada da anterior é recusada por estar morta (regra do publicador para toda execução
  supersedida), e só a nova a leva. Se a nova cair em R3, ou se o turno dela morrer antes do despacho (a `pending` é
  descartada e não leva nada), a lista da anterior não sai, até um pedido seguinte que a leve. **É estado mudo novo**
  (achado P2-1, reproduzido pelo caminho real: em `260be4f385` a lista sai, em `05450ad1ce` não): na rodada 6 a
  anterior já estava `done` depois da passada que publicava, e a janela ia só do despacho a essa passada; na rodada 7
  ela vai até a passada que confere o aceite. Cada espera de 3 s custa de 5,5 a 8 s de relógio (`AsyncConfig`, o poller
  de agendados do Sidekiq).

O silêncio com a cotação lida substituída por uma mais nova não é resíduo: é a decisão do CEO, com teste (nenhuma das
duas listas sai e nenhuma frase sai).

### Mutações da rodada 7

Executor `scratchpad/f2-mutacoes-r7.rb`: uma ou mais trocas exatas por mutação, cada trecho casando uma vez, e os
arquivos restaurados com md5 conferido. md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois das duas execuções.
X04 e X11 rodaram de novo (`f2-mutacoes-r7b.rb`): na primeira execução a troca cortava o nome qualificado da constante
e as falhas eram `NoMethodError`, não comportamento; os números abaixo são os da segunda, sem erro de carga.

| # | Mutação | Resultado |
|---|---|---|
| X01 | o perfil do segurado e do condutor vira categoria (sem os termos da pessoa) | 14 falhas |
| X02 | termo de conta libera a categoria (sem os termos de conta) | 57 falhas |
| X03 | o texto do portal guardado no lugar da categoria | 33 falhas |
| X04 | o texto do portal chega ao modelo (guardado, lido sem a guarda da leitura e escrito na fala) | 36 falhas |
| X05 | sem exigir `kind` risco | 6 falhas |
| X06 | texto com as duas categorias sai com a primeira | 1 falha |
| X07 | letra ilegível não leva ao genérico | 1 falha |
| X08 | sem os termos de dúvida | 4 falhas |
| X09 | o nome do veículo sozinho vira categoria (atributo não nomeado) | 15 falhas |
| X10 | `auth_required` guarda a categoria | 2 falhas |
| X11 | a leitura aceita motivo guardado fora das categorias | 1 falha |
| X12 | a fala ignora a categoria (sempre o genérico) | 6 falhas |
| Y01 | a anterior conta como levada antes de a nova ser aceita | 5 falhas |
| Y02 | aceite só pelo registro, sem a mensagem | 2 falhas |
| Y03 | aceite só pela mensagem (a adiada não conta) | 7 falhas |
| Y04 | a lista encerra na emissão, sem nova tentativa | 7 falhas |
| Y05 | a lista que sai de novo pede o intervalo curto | 1 falha |
| Y06 | a primeira emissão sem o intervalo curto | 1 falha |
| Y07 | sem descontar a anterior entregue depois da abertura | 2 falhas |
| Y08 | desconta também a anterior entregue antes da abertura | 3 falhas |
| Y09 | a cotação nova não cala a lista | 1 falha |
| Y10 | encerramento sem a última tentativa | 4 falhas |
| Y11 | encerramento emite sem conferir se a lista ainda vale | 1 falha |
| Y12 | a passada emite de novo depois do aceite | 13 falhas |
| Y13 | a anterior que falhou não entra | 1 falha |
| Y14 | leva só os códigos do pedido da anterior, sem o que ela já levava | 1 falha |
| Y15 | `publicacao_vale?` sem conferir a lista levada | 6 falhas |
| Y16 | composição fora do lock da conversa | **sobrevive** (esperado; ver "O que NÃO foi verificado") |

**27 de 28 reprovadas**; a sobrevivente é a do lock, declarada desde a rodada 3. Specs de cada grupo: X, os do motivo,
do resultado guardado, da ferramenta, das promessas e da integração (351 exemplos); Y, os da ferramenta, da integração
e do `nenhum_estado_mudo` (187 exemplos).

### A revisão da rodada 7 (sobre `05450ad1ce`), e a parada

CI de `05450ad1ce` (run 34792789781): 12 jobs `success`. Revisor independente (agente com contexto próprio, só leitura,
banco de teste próprio `chatwoot_test_rev7f2` e extração `git archive` de `260be4f385` na pasta de rascunho, os dois
removidos no fim), com sondas pelo caminho real (`Responder`, motor, publicador, `AsyncPublishJob`, varredor), cada uma
rodada nos dois SHAs, e o classificador real do conector (`origin/main` `ad4372a`) sobre 31 textos novos. **Nenhum P1,
três P2, quatro P3.** O texto do portal não chega ao modelo nem ao banco em nenhum caminho que ele achou. Linha de base
dele na HEAD: os 7 specs da rodada, 259 exemplos, 0 falhas, exit 0.

| Achado | Sev. | Cenário | Evidência | Conserto sugerido | Estado |
|---|---|---|---|---|---|
| P2-1. A lista aceita morre quando o pedido seguinte abre antes da passada que confere o aceite, e o turno dele cai antes do despacho | P2 (estado mudo novo) | R6 acima | sonda S2 e S2b: em `05450ad1ce` 6 exemplos, 5 falhas, exit 1 (as mensagens ficam só com a fala; a anterior `superseded`, a nova `discarded`); em `260be4f385` S2, S2b e o controle passam | encerrar `done` na mesma passada quando o publicador aceitou a lista, e o motor reagendar só a lista recusada, como já faz com arquivo (`AsyncRunJob#apply`, `arquivo_recusado?`); some a passada de confirmação | aberto |
| P2-2. A execução que descontou a lista toda volta, no pedido seguinte, com os códigos do pedido dela | P2 (duplicata nova) | R4 acima, com um terceiro pedido | sonda S5: em `05450ad1ce` 1 exemplo, 1 falha, exit 1 (a lista inteira sai duas vezes); em `260be4f385` 1 exemplo, 0 falhas, exit 0 | gravar `lista` também com a composição vazia (`codigos: []`), e `codigos_da_lista` respeitar a chave presente | aberto |
| P2-3. A publicação adiada, já aceita, que falha uma vez não tenta de novo; com uma anterior levada, perde as duas | P2 (anterior à rodada; a auditoria o dava por resolvido) | R2 acima | sonda S3a e S3b: falham nos dois SHAs; nenhum job novo enfileirado | o `AsyncPublishJob` reagendar o `blocked` que veio de exceção, com teto; o `Result` do publicador distinguir erro de recusa de autorização. Muda o motor de todas as entregas adiadas (lotes de preço e PDF em produção) | aberto, para decisão |
| P3-1. Conta e pessoa com categoria | P3 | 31 textos `risco` no conector real que casam um atributo sem termo das listas | sonda S1: 33 exemplos, 32 falhas, exit 1 (os 31 com categoria; a 32ª é `transliterate` com UTF-16 ou ASCII-8BIT, que o `JSON.parse` do conector não produz) | aceitar só moldes fechados de "atributo + recusa" (toda palavra do texto num conjunto pequeno), o que dispensa as listas de termos e deixa mais motivos no genérico | aberto, para decisão |
| P3-2. Os 59 textos das revisões não provam o filtro de termos | P3 | 58 dos 59 não casam padrão de categoria | sonda S6: exit 0 | afirmação corrigida acima; a prova do filtro é o exemplo por termo | auditoria corrigida |
| P3-3. A lista anterior que sai durante a chamada ao modelo do pedido novo é repetida | P3 (anterior à rodada) | o cliente escreve "cadê?" logo depois da fala, e a lista anterior sai com o histórico do turno novo já montado | sonda S4: falha nos dois SHAs (a mesma seguradora 2 vezes) | cortar o desconto pela mensagem do cliente que abriu o turno, e não pela abertura da execução | aberto |
| P3-4. A recusa permanente de autorização gasta todas as tentativas; e a fala da região convida a detalhe | P3 | `vinculo_mudou` (a conversa trocou de caixa) | sonda S7: em `05450ad1ce` 61 passadas até `prazo_esgotado` (em produção o prazo de 420 s limita a cerca de 25); em `260be4f385`, 2 | encerrar quando a recusa é de autorização (a mesma distinção do P2-3); tirar "(CEP, circulação ou pernoite)" de `MOTIVOS` | aberto |

Onde o revisor olhou e não achou defeito: o único consumidor de `reason` é `ResultadoPorSeguradora#sem_proposta`; a
leitura só aceita chave de `CATEGORIAS`; o `{kind, text}` antigo, `auth_required`, letra que não se translitera,
fullwidth e caractere invisível caem no genérico; nada vai a log; o `record_attempt!` não apaga `lista`; o
`merge_handle!` só deixa de gravar em execução morta, que não publica; o encerramento depois do aceite não republica;
a cotação nova cala a lista; os laços são limitados por tentativas e prazo; a falha passageira na publicação imediata
tenta de novo; a seção nova do `principal.md` não tem travessão.

**Parada.** A decisão do CEO para esta rodada foi "se alguma correção deixar um estado mudo, pare e me avise". O P2-1 é
exatamente isso: a lista que sai até ser aceita manteve a execução viva por uma passada a mais, e a abertura de um
pedido novo nessa passada mata a publicação adiada dela. Nenhum código novo depois de `05450ad1ce`; esta atualização é
só da auditoria. O conserto do P2-1 e o do P2-3 mexem no motor (`AsyncRunJob#apply` e `AsyncPublishJob`), e o do P3-1
muda o desenho da classificação: ficam para a decisão do coordenador.

**Rodada 8:** P2-1, P2-2, P3-3 e P3-4 saíram com o desenho assíncrono; P3-1 foi fechado pelo molde fechado; P2-3 foi
para a issue #425.

## Rodada 8: a troca de desenho (13/09/2026)

### Por que

Decisão do coordenador depois da revisão da rodada 7, registrada com o motivo que ele deu: foram sete rodadas em que a
ferramenta assíncrona `ver_resultado_da_cotacao` gerou corrida nova a cada correção (estado mudo, duplicata, absorção de
lista, execução substituída, publicação adiada). A causa está no desenho: uma ferramenta assíncrona que junta e desconta
listas entre pedidos feitos em execuções diferentes. Enquanto esse desenho existir, esse tipo de defeito continua
aparecendo, e o que sai é o desenho. P2-1, P2-2 e a decisão 7 não foram corrigidos dentro dele.

### O desenho novo

1. **A ferramenta é síncrona**, e a lista de preços vai como **anexo do turno**, escrita pelo código e entregue logo
   depois da fala da Lia, na mesma entrega (`Tools::Delivery#anexar`, `Operate::Responder`).
2. **Sem contexto de entrega** (Testar, Copiloto, playground), a ferramenta devolve o erro nomeado
   `lista_indisponivel_nesta_superficie`, pelo registro de recusa, e não anexa nada.
3. **O `Responder` entrega os anexos depois da resposta** nos três caminhos: humanizado (fim da cadeia do
   `ChunkedDeliveryJob`, cada anexo um pedaço inteiro, sem o `ReplyChunker`), clássico (a resposta e os anexos no mesmo
   lock, com a idempotência de `already_replied?`) e voz (o áudio e os anexos como texto). `@expected_chunks` conta os
   anexos. **No turno mudo, o anexo sai sozinho** (decisão 19, aceita).
4. **O modelo nunca recebe valor em reais**: recebe quantas seguradoras fizeram proposta, se a lista vai anexada e,
   quando o cliente perguntou por uma seguradora, o nome, o desfecho e a categoria (`veiculo`, `regiao` ou `nenhuma`).
   Nem travessão, nem frase pronta, nem texto do portal.
5. **Nada de `ToolRun`, fila ou absorção.** Cada pergunta mostra o que está guardado naquele instante; perguntou duas
   vezes, recebe duas vezes. A ferramenta lê a execução mais nova de `cotar_seguro` da conversa no instante da pergunta.

### O que saiu

- A ferramenta assíncrona de exibição: `Native::InsuranceQuoteResult` como execução do motor (`async?`, `precheck`,
  `aceite`, `handle_de_abertura`, `start`, `poll`, `closing_deliveries`, os cinco textos de classe vazios) e
  `insurance_quote_result/listas.rb` inteiro (a lista levada, descontada e aceita). O arquivo
  `insurance_quote_result.rb` continua, com a ferramenta síncrona.
- Os ganchos que ela criou fora dela: `Native::Base.publicacao_vale?`, `Native::Base#aceite` e `#handle_de_abertura`;
  `Tools::AutorizacaoDaExecucao#publicacao_vale?` e a recusa `resultado_superado`; `Bound#aceite_native` e
  `#abertura_native`; `ToolRun.open!(handle_inicial:)` e `ToolRun.handle_de_abertura`; o motivo
  `resultado_respondido_no_turno` do registro de recusa.
- As listas de termos do motivo (`TERMOS_DE_CONTA`, `TERMOS_DA_PESSOA`, `TERMOS_DE_DUVIDA`) e os padrões por expressão
  regular das categorias: o molde fechado os substitui.
- Nos specs: os exemplos de `publicacao_vale?` do `async_publisher_spec` e o de `handle_inicial` do `tool_run_spec` (os
  dois arquivos voltaram aos da `main`), os níveis de `aceite`, `handle_de_abertura` e `publicacao_vale?` do
  `base_contrato_de_nivel_spec`, o exemplo da execução da Lia da `medida_spec`, e os exemplos de passadas, lista levada e
  encerramento da ferramenta da Lia.

Nenhum nome da lista acima aparece mais em `app/` (conferido nome a nome contra `fd5ac3d07f`).

### O que continua

- `resultado_por_seguradora` no handle da cotação (`InsuranceQuote::Resultado`) e os códigos por lote de preço
  (`LOTES_KEY`), que a ferramenta usa para não repetir o preço que a cotação ainda está enviando (`a_caminho`).
- A união no pedido repetido (`ToolRun#conta_como_pedido?`, `#resultado_obtido?`, `Native::Base.resultado_guardado?`,
  `PedidoRepetido#resultados`).
- A confirmação curta de 3 s (`QuoteOffers#confirma_na_proxima?`, `Progress.running(confirmar_logo:)`,
  `AsyncRunJob#reschedule(curto:)`).
- O `principal.md`, ajustado ao anexo, com o md5 novo `429fbe18230433e92c3e07bf14cd4f5f` e dez promessas.

### O motor assíncrono voltou ao da `main`

`git diff 5742de5fcd --stat` sobre o motor inteiro (`app/jobs/autonomia/agents/tools`, `AsyncPublisher` e
`async_publisher/`, `Encerramento`, `EntregaAceita`, `EntregaPublicada`, `EntregaDeArquivo`, `EntregaEncadeada`,
`ArquivoGravado`, `AutorizacaoDaExecucao`, `RetomadaDeEnvio`, `PendenciaDeEnvio`, `VigiaDeEnvio`, `Progress`,
`AsyncConfig`, `AsyncDispatcher`, `Bound`, `PedidoRepetido`, `Native::Base`, `ToolRun` e `tool_run/`): **5 arquivos,
42 linhas a mais e 11 a menos**, só nos dois pontos.

| Arquivo | Diferença | Ponto |
|---|---|---|
| `async_run_job.rb` | `reschedule(run, attempt, curto:)` e o `apply` que passa `progress.confirmar_logo?` | confirmação curta |
| `progress.rb` | `Progress.running(confirmar_logo:)` e `#confirmar_logo?` | confirmação curta |
| `tool_run.rb` | `conta_como_pedido?` por união com `resultado_obtido?`, e o comentário do pedido repetido | gravação do resultado (pedido repetido) |
| `native/base.rb` | `resultado_guardado?` de classe, e o cabeçalho que diz que a lista do Agente de Cotação é a do deploy | gravação do resultado (pedido repetido) |
| `pedido_repetido.rb` | "resultado guardado e nenhuma entrega encaminhada para publicação" com o contador em zero | gravação do resultado (pedido repetido) |

`AsyncPublisher`, `AsyncPublishJob`, `Encerramento`, `AutorizacaoDaExecucao`, `RetomadaDeEnvio`, `ReapStaleRunsJob`,
`Bound` e os demais estão idênticos aos da `main`. Fora do motor, e por causa do desenho novo: `Tools::Delivery` (os
anexos), `Operate::Responder` (a entrega deles) e `Tools::Recusa` (o código `lista_indisponivel_nesta_superficie`).

### Um estado mudo achado nesta rodada, e fechado

Ao conferir os estados mudos antes do commit, uma sonda mostrou um caso que a primeira versão desta rodada deixava
mudo: **turno mudo com uma ferramenta assíncrona aceita no mesmo turno e a gravação da lista falhando.** A exceção subia
até `falha_no_turno`, que descarta as execuções aceitas no turno. Pelo `Responder` real, com uma assíncrona de teste
(`scratchpad/r8-sonda-mudo/sonda_turno_mudo_spec.rb`, 4 exemplos, exit 0): sem anexo, a execução fica `running` com 1
`AsyncRunJob` enfileirado (é o que a `main` faz no turno mudo); com o anexo e a primeira gravação falhando, a execução
ficava `discarded`, sem job e sem mensagem, nas entregas clássica e humanizada. **Conserto:** a gravação do anexo no turno
mudo é best-effort (`postar_anexos_do_turno_mudo`: a falha vai ao log, só a classe, e o despacho segue), no molde do
`handoff_if_signaled`. Exemplo novo em `responder_anexos_spec` (clássica e humanizada) e mutação Z23. Os números abaixo são
os de depois do conserto; a suíte, o RuboCop, o `zeitwerk:check` e as mutações rodaram de novo.

### A ordem no canal (achado desta rodada, para decisão)

A ordem fala e depois lista está provada no Chatwoot, nos três caminhos. Até o cliente, lido no código e sem teste: cada
mensagem sai para o canal pelo seu `SendReplyJob` (`Message#send_reply`, no `after_create_commit`, fila `high`, Sidekiq
com `SIDEKIQ_CONCURRENCY` 10 por padrão), sem ordem por conversa.

- **Humanizada** (ligada por padrão: `AI_HUMANIZE_DELIVERY` e `config['humanize_delivery']`): a lista entra na fila pelo
  menos 900 ms depois do último pedaço da fala, a mesma folga que separa os pedaços da fala na `main`.
- **Clássica** (humanizada desligada, ou resposta que o quebrador não quebra): a fala e a lista entram na fila no mesmo
  commit, e duas threads podem enviá-las ao mesmo tempo; a ordem de chegada não é garantida.
- **Voz** (desligada por padrão: `AI_AGENT_VOICE_REPLY` e `config['voice_reply']`, e só no turno com áudio do cliente): a
  mensagem com anexo sai com `wait: 2.seconds` e a lista em texto sem espera, então a lista tende a chegar antes do
  áudio.

A configuração do agente 24 em produção não foi lida. Pôr a lista da clássica e da voz na ordem até o cliente muda o
mecanismo que a rodada 8 definiu para esses caminhos (o anexo no mesmo lock); um caminho possível é entregar o anexo pela
cadeia do `ChunkedDeliveryJob`, com uma pausa depois da resposta, herdando N1 e N2. Fica para decisão.

### O anexo nos três caminhos, e o que prova cada ponto

| Ponto | Exemplo que cai sem ele | Mutação |
|---|---|---|
| clássico: a fala e depois a lista, na mesma transação, com o `autonomia_reply_to_message_id` da resposta | `responder_anexos_spec` "a fala sai primeiro e a lista depois"; `answerer_resultado_da_cotacao_spec` "a fala da Lia sai primeiro" | Z01, Z12 |
| humanizado: a lista no fim da cadeia, inteira, sem o quebrador; a cadeia posta a fala e depois a lista | `responder_anexos_spec` "a lista entra no fim da cadeia como um pedaço inteiro", "a cadeia posta a fala e depois a lista"; `answerer_resultado_da_cotacao_spec` "com a entrega humanizada" | Z02, Z10 |
| `@expected_chunks` conta a lista | `responder_anexos_spec` "expected_chunks conta os pedaços da fala e a lista" (com uma assíncrona aceita no mesmo turno) | Z08 |
| voz: o áudio e depois a lista como texto; com a síntese falhando, a fala em texto e a lista | `responder_anexos_spec` "o áudio sai primeiro e a lista depois", "com a síntese falhando" | Z03, Z11 |
| turno mudo: a lista sai sozinha, uma vez, sem evento `replied`, com a entrega clássica e com a humanizada ligada | `responder_anexos_spec` "turno mudo"; `answerer_resultado_da_cotacao_spec` "o turno mudo" | Z09 |
| turno mudo com assíncrona aceita e a gravação da lista falhando: o despacho segue | `responder_anexos_spec` "a assíncrona é despachada e o turno continua mudo" | Z23 |
| idempotência no retry do `ReplyJob` | `responder_anexos_spec` "o retry do ReplyJob não repete" (clássico, mudo e humanizado); `answerer_resultado_da_cotacao_spec` "o retry do ReplyJob" | Z04, Z05 |
| o modelo sem valor | `insurance_quote_result_spec` "nenhum texto ao modelo tem valor ou travessão, em nenhum estado; o valor está só no anexo"; `answerer_resultado_da_cotacao_spec` "com preço a mostrar" | Z06 |
| sem contexto de entrega, o erro nomeado | `insurance_quote_result_spec` "sem contexto de entrega"; `recusa_registro_spec` `insurance_quote_result.rb#call#1` | Z13 |
| uma lista por turno com duas chamadas; duas perguntas, duas listas | `insurance_quote_result_spec` "mais de uma chamada"; `answerer_resultado_da_cotacao_spec` "duas chamadas", "pede os preços de novo" | Z14 |
| o molde fechado | `motivo_da_recusa_spec` e o `insurance_quote_result_spec` "o modelo nunca recebe texto do portal" | Z07, Z17 a Z22 |

### O corpus do conector com o molde fechado (P3-1)

As 39 mensagens de `test/fixtures/agger/motivos-de-recusa.sanitized.json` (`autonomia-adapters`), com o texto, o `kind`
e o status conferidos contra o arquivo na rodada 7, classificadas pela regra desta rodada (`scratchpad/f2-r8-classifica.rb`,
o `motivo_da_recusa.rb` da árvore carregado com ActiveSupport, sem Rails). Mudam só as linhas 31, 32 e 33.

| # | `textoLimpo` | `kind` do conector | status | categoria |
|---|---|---|---|---|
| 1 | Risco sem aceitação para este cenário nesta seguradora. | `risco` | `declined` | genérico |
| 2 | Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro? | `risco` | `declined` | genérico |
| 3 | Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida | `risco` | `declined` | `veiculo` |
| 4 | Aceitacao Restrita, cobertura auto nao permitida para este modelo. | `risco` | `declined` | `veiculo` |
| 5 | O veículo não possui aceitação para a categoria tarifária informada. | `risco` | `declined` | `veiculo` |
| 6 | Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o risco deste orçamento. | `risco` | `declined` | genérico |
| 7 | O sistema de cálculo está indisponível, tente novamente em alguns instantes. | `passageiro` | `declined` | genérico |
| 8 | Serviço indisponível, tente novamente mais tarde | `passageiro` | `declined` | genérico |
| 9 | Houve uma instabilidade ao realizar o cálculo nesta seguradora, tente novamente em breve. | `passageiro` | `declined` | genérico |
| 10 | Usuário não possui acesso a funcionalidade. Por favor, verifique suas permissões no site da seguradora. | `credencial` | `auth_required` | genérico |
| 11 | Login ou senha incorreta. Confira suas credenciais de acesso. | `credencial` | `auth_required` | genérico |
| 12 | Erro ao processar o cálculo do prêmio | `outro` | `declined` | genérico |
| 13 | Desmoronamento - Para contratação desta cobertura é necessário enviar para Análise Técnica. | `outro` | `declined` | genérico |
| 14 | O Nome informado não corresponde ao CPF cadastrado. Por favor, verifique e tente novamente. | `outro` | `declined` | genérico |
| 15 | 400 - Restrição técnica para o Segurado | `risco` | `declined` | genérico |
| 16 | O valor informado de R$ 10.000,00 para a cobertura Roubo Residencial Condominos, Cobertura é invalido. O mínimo aceito | `outro` | `declined` | genérico |
| 17 | Corretor não encontrado. Por favor, selecione um corretor válido no cadastro da seguradora. | `credencial` | `declined` | genérico |
| 18 | Necessário contratar primeiro uma das coberturas: '000510026 - Responsabilidade Civil Operacoes', '000510304 - Resp Civ | `outro` | `declined` | genérico |
| 19 | [165456] - Contratação da Cobertura Desmoronamento para o GRUPO ESCRITORIOS ATIVIDADE DEMAIS ESCRITÓRIOS está fora da p | `outro` | `declined` | genérico |
| 20 | Para a Cobertura Responsabilidade Civil Empregador, Obrigat ria a contrata o da Cobertura Responsabilidade Civil Est | `outro` | `declined` | genérico |
| 21 | A cobertura de INCENDIO / QUEDA DE RAIO / EXPLOSAO / IMPLOSAO ACIDENTAL / FUMACA / QUEDA DE AERONAVES não pode ser cont | `outro` | `declined` | genérico |
| 22 | LMI COB RC OBRIGATORIA PARA DANO MORAL | `outro` | `declined` | genérico |
| 23 | Houve um erro ao realizar este cálculo. | `outro` | `declined` | genérico |
| 24 | Não foi possível recuperar o valor dessa cotação. Por favor, tente novamente mais tarde. | `passageiro` | `declined` | genérico |
| 25 | O valor do capital segurado deve ser entre R$100,00 e R$1.000,00, limitado a 250 vezes o capital segurado da cobertura | `outro` | `declined` | genérico |
| 26 | Profissão deve ser especificada corretamente para que o cálculo prossiga. | `outro` | `declined` | genérico |
| 27 | Ocorreu uma divergencia entre a comissao informada e a comissao permitida. | `credencial` | `declined` | genérico |
| 28 | Tipo de veículo não aceito. | `risco` | `declined` | `veiculo` |
| 29 | Nenhum produto com seguro disponível para exibição. | `outro` | `declined` | genérico |
| 30 | Só é permitida a contratação de [Faróis, Lanternas e Retrovisor] para veículos até 20 anos. | `outro` | `declined` | genérico |
| 31 | [2005] - -Contratação não permitida - Ano Modelo do Veículo | `risco` | `declined` | genérico |
| 32 | Moto de ano/modelo sem aceitação - RP | `risco` | `declined` | genérico |
| 33 | [2159] - -Contratação não permitida - Categoria do Veículo | `risco` | `declined` | genérico |
| 34 | UC00 - Risco fora das políticas de aceitação As Necessidades do Cliente, não foram salvas com sucesso, selecione nov | `risco` | `declined` | genérico |
| 35 | Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP | `risco` | `declined` | genérico |
| 36 | A cobertura "Impacto Veículos" não está disponível para esta cotação. | `outro` | `declined` | genérico |
| 37 | Ocorreu um erro ao calcular. Revise o formulario de calculo e tente novamente. | `outro` | `declined` | genérico |
| 38 | Origem da viagem deve ser especificada corretamente | `outro` | `declined` | genérico |
| 39 | Cálculo sem prêmio. | `outro` | `declined` | genérico |

`risco`: 13, com categoria **4** (todas `veiculo`; eram 7). `passageiro`: 4, `credencial`: 4, `outro`: 18, nenhuma com
categoria.

**Custo em motivos reais:** as mensagens 31, 32 e 33 caem no genérico. Nas 31 e 33, o número do código do portal
("2005", "2159") e "contratação" são palavras fora do molde; na 32, "RP". A Lia passa a dizer só que a seguradora não
fez proposta onde antes diria que ela não aceitou o veículo.

**Custo nos 23 motivos plausíveis da rodada 7** (`scratchpad/f2-r7-custo.rb`, rodado com a regra da rodada 7, tirada de
`fd5ac3d07f`, e com a desta): a categoria sai em **5 (eram 10)**. Caem no genérico "Rastreador obrigatório para este
modelo." ("rastreador", "obrigatório"), "Categoria tarifária não aceita." (não nomeia o veículo), "Localidade sem
aceitação para este produto." ("produto"), "Região de risco sem aceitação." ("risco") e "Pernoite em via pública sem
aceitação." ("via", "pública").

**As sondas:** os 31 textos da revisão da rodada 7, que saíam todos com categoria, saem todos genéricos, e os dois
controles saem com a categoria certa ("Tipo de veículo não aceito." `veiculo`, "CEP sem aceitação." `regiao`). Os 59
textos das revisões anteriores continuam genéricos.

### P2-3: fora desta PR

A publicação adiada que falha uma vez e não tenta de novo é da `main` e muda o motor de todas as entregas adiadas: issue
**#425** (`autonom-ia2/chat`), com o cenário, a sonda e o conserto proposto, no Project com prioridade P2. A sonda,
reescrita sobre o motor genérico (sem a ferramenta da Lia), reproduz na árvore desta rodada: nenhuma mensagem do bot e
nenhum `AsyncPublishJob` novo depois de uma falha (`scratchpad/p2-3/publicacao_adiada_uma_falha_spec.rb`, 1 exemplo,
exit 0). Com a ferramenta síncrona, a lista da Lia não passa mais por esse caminho; os lotes de preço e o comparativo
continuam passando, como na `main`.

P3-3 (a lista anterior repetida durante a chamada ao modelo) e P3-4 (a recusa permanente gastando tentativas) eram do
desenho assíncrono e saíram com ele. P3-2 era da auditoria e foi corrigido na rodada 7.

### Mutações da rodada 8

Executor `scratchpad/f2-mutacoes-r8b.rb`: uma ou mais trocas exatas por mutação, cada trecho casando uma vez, arquivos
restaurados com md5 conferido; md5 de `app/` (`.rb`, `.md` e `.txt`) igual antes e depois (`350e3b378f75b0034035ffa4b2511a1a`). Specs por grupo:
entrega, `responder_anexos_spec` e `answerer_resultado_da_cotacao_spec`; ferramenta, os da ferramenta, da integração,
das promessas, do `nenhum_estado_mudo` e dos lotes; categoria, os do motivo, do resultado guardado, da ferramenta e das
promessas. Z13 e Z21 caem por exceção, e é o comportamento que elas testam: a guarda que tiram é a que evita a exceção
(conversa nula; transliteração de texto que não é UTF-8).

| # | Mutação | Specs | Resultado |
|---|---|---|---|
| Z01 | anexo antes da fala, na entrega clássica | 34 exemplos | 8 falhas |
| Z02 | anexo antes da fala, na entrega humanizada | 34 exemplos | 3 falhas |
| Z03 | anexo antes do áudio, na entrega em voz | 34 exemplos | 1 falha |
| Z04 | anexo duplicado no retry, na entrega clássica | 34 exemplos | 2 falhas |
| Z05 | anexo duplicado no retry, no turno mudo | 34 exemplos | 2 falhas |
| Z06 | valor chegando ao modelo (o anexo junto do texto da ferramenta) | 199 exemplos | 5 falhas |
| Z07 | palavra desconhecida liberando categoria | 262 exemplos | 39 falhas |
| Z08 | `@expected_chunks` sem contar os anexos | 34 exemplos | 1 falha |
| Z09 | turno mudo sem o anexo | 34 exemplos | 4 falhas |
| Z10 | anexo passando pelo quebrador | 34 exemplos | 4 falhas |
| Z11 | entrega em voz sem o anexo | 34 exemplos | 1 falha |
| Z12 | entrega clássica sem o anexo | 34 exemplos | 9 falhas |
| Z13 | sem contexto de entrega, sem o erro nomeado | 199 exemplos | 1 falha (exceção) |
| Z14 | duas chamadas no mesmo turno: a segunda troca a lista sem somar | 199 exemplos | 2 falhas |
| Z15 | o preço a caminho entra na lista | 199 exemplos | 10 falhas |
| Z16 | o modelo não recebe quantas cotaram | 199 exemplos | 4 falhas |
| Z17 | motivo sem exigir `kind` risco | 262 exemplos | 6 falhas |
| Z18 | molde do veículo sem exigir o nome do veículo | 262 exemplos | 1 falha |
| Z19 | molde da região sem exigir o atributo | 262 exemplos | 1 falha |
| Z20 | molde com palavra de conta ("seu", "código") | 262 exemplos | 5 falhas |
| Z21 | texto que não é UTF-8 válido chega à transliteração | 262 exemplos | 1 falha (exceção) |
| Z22 | a leitura aceita motivo guardado fora das categorias | 262 exemplos | 1 falha |
| Z23 | turno mudo: a falha ao gravar o anexo derruba o despacho da assíncrona | 34 exemplos | 2 falhas |

**23 de 23 reprovadas.**

### Os estados em que a lista prometida não chega

Nenhum estado que hoje leva palavra ao cliente deixa de levar: a `main` não tem a ferramenta; sem anexo, o `Responder`
entrega como a `main` (os specs do `Responder` que já existiam passam sem mudança); e o turno mudo com assíncrona aceita
continua despachando (conserto acima). Os casos em que a Lia diz que a lista vem e ela não vem, com o cenário de cada um:

- **N1. O cliente escreve no meio da cadeia humanizada, antes do pedaço da lista.** O `ChunkedDeliveryJob` aborta o resto
  da cadeia (regra da `main` para a fala), e a lista vai junto. O turno novo responde à mensagem nova; a lista só sai se
  a Lia consultar de novo. No desenho assíncrono ela saía pelo motor, no teto de adiamentos.
- **N2. Um humano assume a conversa durante a cadeia humanizada.** A cadeia para (regra da `main`), e a lista não sai.
  No desenho assíncrono ela saía como nota privada.
- **N3. A gravação da lista falha na entrega clássica ou em voz.** A transação desfaz a fala junto, e o turno cai em
  `falha_no_turno` (silêncio, e as execuções assíncronas aceitas no turno descartadas), o mesmo estado da `main` quando a
  gravação da fala falha; o turno com anexo faz uma escrita a mais nessa transação. Na cadeia humanizada, o pedaço que
  falha levanta, e o job tenta de novo sem duplicar (token do pedaço).
- **N4. Retry do `ReplyJob` antes do primeiro pedaço, com o modelo escrevendo outra fala.** A segunda cadeia para no
  primeiro pedaço que a primeira já postou (regra da `main`); se a segunda correr na frente, a lista que sai é a dela.
- **N5. O lote de preço a caminho** (`JANELA_DO_LOTE`, 10 min) continua com os resíduos das rodadas 4 a 6 (em "O que
  NÃO foi verificado").

Por desenho, e não resíduo: a pergunta feita duas vezes recebe a lista duas vezes; a cotação trocada entre a pergunta e
a entrega sai com a lista da cotação lida na pergunta; no turno mudo com assíncrona aceita, a lista sai pelo caminho
clássico e a assíncrona é despachada com `expected_chunks` zero.

## O que NÃO foi verificado

- **Conversa real com o modelo.** Que a Lia chame a ferramenta quando o cliente pergunta, não escreva valor,
  não liste seguradoras e não conte motivo sem pergunta é conduta do modelo; aqui o modelo é dublado. Rodada 8: que a
  fala dela apresente a lista anexada sem repetir os itens também é conduta do modelo.
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
- **As listas em cadeia saíram com o desenho assíncrono (rodada 8).** Os dois casos da mesma seguradora em duas listas
  (rodada 3), o lock da composição da lista (mutações T21, U24 e Y16, que sobreviviam) e os três ou mais pedidos com
  listas levadas não existem mais: não há lista levada, descontada nem composta sob lock. Perguntar duas vezes recebe
  duas listas, por desenho.
- **O lote de preço aceito cuja publicação adiada morre** fica "a caminho" para a Lia por até `JANELA_DO_LOTE`
  (10 min) depois da emissão (decisão 24). A janela é maior que o teto de adiamentos medido (6 a 8 min), não
  medida com a fila real. **E o contrário**: num incidente que pare a fila por mais de 7 a 10 min no meio do
  adiamento de um lote, o cliente que pergunta depois da janela recebe a lista da Lia, e o lote ainda sai quando a
  fila volta: o preço duas vezes (reproduzido pela quinta revisão com o relógio adiantado). Sem conserto: a
  publicação do lote não sabe que a Lia já mostrou aqueles preços.
- **Lote de preço com a mensagem criada e a pendência de envio gravada logo depois**: entre as duas escritas
  (milissegundos, com o Redis fora) a Lia veria o lote como entregue. Sem teste.
- **A categoria do motivo contra texto real depois do #60**: medida no corpus sanitizado do conector (rodada 8: 4 das 13
  mensagens `risco` com categoria, todas `veiculo`; nenhuma `regiao` no corpus, e a categoria da região só foi
  exercitada com texto sintético). Motivo real que nomeia o atributo com palavra fora dos padrões cai no genérico
  sem aviso; não há registro de quantos.
- **A confirmação curta encurta a janela entre as duas leituras** de 13 a 21 s para 3 a 8 s. A guarda das duas
  leituras depende de o portal já ter listado todas as seguradoras quando a lista se repete; nos brutos de
  13/09/2026 todas estavam listadas na primeira leitura, e o contrário não foi observado. Não medido com a
  janela nova.
- **Texto de conta ou da pessoa escrito só com as palavras do molde** (rodada 8). Os 31 textos da revisão da rodada 7
  (achado P3-1) saem genéricos. Um texto de conta ou da pessoa escrito só com as palavras de um conjunto, e nomeando o
  atributo e o veículo (ou o atributo da região), ainda sairia com categoria. Os conjuntos não têm palavra de conta nem
  da pessoa, e não se conhece texto assim; não há prova de que não exista.
- **A ordem de chegada no WhatsApp** (rodada 8). Lida no código, não medida com o canal real: ver "A ordem no canal"
  na seção da rodada 8 (na clássica a ordem não é garantida; na voz a lista tende a chegar antes do áudio).
- **N1 a N4 da rodada 8 com o Sidekiq e o canal reais.** Exercitados com os jobs da cadeia rodados à mão no spec.
- **O schema contra a API da OpenAI.** Validado pela forma (`openai_schema_spec`), não por chamada real.
- **Custo por turno**: a ferramenta nova acrescenta uma função ao prompt do agente de cotação, e cada chamada lê o
  banco dentro do turno (a execução mais nova e as mensagens dos lotes de preço). Não medido.
- **Rollback executado.**

## Deploy e rollback

- Sem migration, sem variável de ambiente nova, sem escrita em banco. Deploy normal do chat2you.
- Depois do deploy, o agente 24 passa a oferecer `ver_resultado_da_cotacao` no turno seguinte, e o
  `principal.md` novo vale na montagem seguinte do prompt. O `Responder` de todos os agentes passa a entregar os anexos
  do turno; sem ferramenta que anexe (todos os outros agentes), a entrega é a da `main`.
- **Rollback**: voltar à imagem de `5742de5fcd`. Efeitos conhecidos:
  - a coluna `native_tool_slugs` do agente 24 volta a mandar (os quatro slugs de antes): a ferramenta some do
    turno;
  - a ferramenta não abre execução nem deixa estado fora do turno: não há execução dela em voo nem publicação adiada a
    descartar (rodada 8);
  - o handle das cotações mantém as chaves `resultado_por_seguradora` e `codigos_por_lote_de_preco`, que a versão
    antiga ignora;
  - o pedido repetido volta a contar só pelo contador.
