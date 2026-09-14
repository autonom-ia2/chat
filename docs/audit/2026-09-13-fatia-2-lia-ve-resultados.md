# Fatia 2 do #420: a Lia vê o resultado da cotação

Data: 13/09/2026 · Branch `feat/cotacao-lia-ve-resultados` · base `origin/main` (`5742de5fcd`).

## Objetivo

Quatro coisas, e só elas:

1. a cotação **guarda o resultado por seguradora** no handle da execução, em toda consulta, como união;
2. a Lia ganha uma **ferramenta assíncrona de exibição**, `ver_resultado_da_cotacao`, que lê esse resultado
   sem ir ao portal; com preço, o código publica os itens depois da fala dela; o motivo de quem não cotou
   só chega ao modelo como categoria escrita pelo código (do veículo ou da região; rodada 7, decisão do CEO), e só
   quando o pedido nomeia a seguradora;
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

### A regra do motivo (rodada 7: categoria escrita pelo código)

**Nenhum texto do portal vai ao modelo nem ao banco** (decisão do CEO de 13/09/2026 sobre as decisões 27 e 28, opção
b). `Insurance::MotivoDaRecusa.categoria(reason)` lê o texto e devolve `'veiculo'`, `'regiao'` ou nil (o genérico)
quando, e só quando:

1. `kind == 'risco'` e o texto é String. Qualquer outro `kind` (`passageiro`, `credencial`, `outro`) é nil;
2. o texto, transliterado e em minúsculas, não tem letra que a transliteração não sabe escrever (vira `#`);
3. não casa nenhum termo de conta da corretora (`TERMOS_DE_CONTA`: login, senha, sessão, token, usuário, acesso,
   permissão, corretor, credencial, SUSEP, cadastro, comissão, bloqueio, conta, portal, operador, perfil, parceiro,
   comercial, contrato, e-mail, link, a marca `<REDACTED>` e outros), nenhum termo da pessoa (`TERMOS_DA_PESSOA`:
   segurado, condutor, motorista, proprietário, cliente, pessoa, CPF/CNPJ/CNH, crédito, financeiro, sinistro, bônus,
   profissão) nem termo de dúvida (`TERMOS_DE_DUVIDA`: interno, critério, análise);
4. casa os padrões de **uma categoria só** (`CATEGORIAS`), que nomeiam o atributo recusado: `veiculo` (idade do
   veículo, ano modelo, este modelo ou modelo do veículo, tipo de veículo, categoria tarifária ou do veículo) e
   `regiao` (CEP, localidade, região, circulação, pernoite). As duas, ou nenhuma: nil.

Na dúvida, nil: o erro aceitável é a Lia dizer só que a seguradora não fez proposta. O perfil do segurado e do condutor
("Segurado com restrição", "Condutor principal com restrição") não vira categoria. A categoria é gravada no handle
(`ResultadoPorSeguradora#sem_proposta`), a leitura só devolve o que é categoria (`ResultadoDaCotacao#motivo`), e o
modelo lê uma de duas falas fechadas (`InsuranceQuoteResult::MOTIVOS`) ou `SEM_MOTIVO`. O vocabulário de liberação da
rodada 5 (`motivo_da_recusa_vocabulario.txt`), o código do portal, os caracteres e os valores por extenso saíram: sem
texto ao modelo, não têm mais uso.

**O corpus do conector** (`autonomia-adapters`, `test/fixtures/agger/motivos-de-recusa.sanitized.json`, 39 mensagens):
7 das 13 `risco` saem `veiculo`, nenhuma sai `regiao`, e as 26 de outro `kind` saem nil. As 6 `risco` que saem nil: duas
não nomeiam atributo ("Risco sem aceitação para este cenário nesta seguradora.", "Não temos um seguro disponível para
este veículo..."), uma tem termo de dúvida ("Após análise dos dados do veículo, região de circulação e critérios
internos..."), duas têm termo da pessoa ("400 - Restrição técnica para o Segurado", "UC00 - Risco fora das políticas
de aceitação As Necessidades do Cliente...") e uma só diz "Veículo sem aceitação" ("Carga(s) transportada(s) (
Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP"). A tabela inteira está na seção da rodada 7.
**Os textos das revisões** (os 28 de conta da quinta revisão, os 6 de dado pessoal, "Senha expirou. Declinando
cálculo.", "Usuário fulano@corretora.com.br bloqueado." e os outros 23 das revisões anteriores): todos nil.

**O custo, medido** (23 motivos sintéticos plausíveis, todos de veículo ou de região, `scratchpad/f2-r7-custo.rb`): 10
saem com categoria ("Idade do veículo fora da política de aceitação.", "Rastreador obrigatório para este modelo.",
"CEP de pernoite sem aceitação.") e 13 caem no genérico, porque o atributo não está entre os que a decisão do CEO
listou ou não está escrito na forma dos padrões: blindado, importado, leilão, chassi remarcado, tabela FIPE, valor do
veículo, uso comercial ou por aplicativo, "com mais de 20 anos", cidade, município, estado, área de risco. Nesses a Lia
diz só que a seguradora não fez proposta. Ampliar a lista é decisão de produto; o risco de ampliar é o de sempre, um
atributo que também serve para falar da conta.

### 2. A ferramenta da Lia, `ver_resultado_da_cotacao`

`Native::InsuranceQuoteResult`, assíncrona, com um parâmetro: `seguradora`, `type: [string, null]`, em
`required`, sem `anyOf` (`openai_schema_spec`, `insurance_quote_result_spec`).

Lê `Insurance::ResultadoDaCotacao.da_conversa`: a execução de `cotar_seguro` mais nova da conversa com status
fora de `superseded`, `discarded`, `blocked` e `pending`. Não chama o conector nem exige conexão.

| Estado | O que acontece |
|---|---|
| sem cotação na conversa | `precheck` devolve `SEM_COTACAO` ao modelo; nenhuma execução |
| cotação encerrada com envio incerto (intenção anotada, número ausente) | `ENVIO_INCERTO` (rodada 3) |
| cotação encerrada sem número do portal (recusada no `start`) | `NAO_CHEGOU` (rodada 2) |
| cotação encerrada sem a chave (anterior a esta versão) | `SEM_RESULTADO` |
| cotação correndo sem preço (inclusive a em voo no deploy, sem a chave) | `SEM_PRECO_AINDA` |
| todo preço está num lote que a cotação ainda está enviando (`a_caminho`) | `PRECOS_A_CAMINHO`; por seguradora, "o preço dela está na fila de envio e chega numa mensagem do sistema" (rodadas 4 e 5) |
| cotação encerrada sem preço | `SEM_PRECO` |
| `seguradora` nomeia quem não fez proposta | nome + "não fez proposta" + a fala da categoria do motivo (`MOTIVOS`: do veículo ou da região), ou `SEM_MOTIVO` (rodada 7) |
| `seguradora` nomeia quem ainda corre | "ainda não respondeu" (enquanto a cotação corre; depois, "não fez proposta") |
| `seguradora` não casa ninguém | `NAO_ENCONTRADA` / `NAO_ENCONTRADA_AINDA` |
| há preço a publicar (resultado inteiro, ou `seguradora` nomeia quem cotou) | `precheck` nil, a execução abre com a cotação lida e os códigos com preço no handle (`handle_de_abertura`, rodada 2), o modelo recebe `aceite`; a 1ª passada do motor (`start`) devolve o que a abertura gravou; a 2ª (`poll`) publica os itens de `QuoteOffers.item` desses códigos e dos das execuções anteriores sem mensagem sobre a mesma cotação (rodada 3), na ordem de `QuoteOffers#quoted`, e devolve `running`; a seguinte encerra quando a lista foi aceita pelo publicador ou já é mensagem, e sem isso a publica de novo; o encerramento (prazo, tentativas, varredor) é a última tentativa (rodada 7) |

- Os textos da ferramenta ao modelo não trazem o valor do prêmio. O resultado inteiro não leva nome nem
  motivo: diz que a lista sai depois da fala, se a cotação ainda corre, se há quem não fez proposta e se a
  cotação foi sem bônus. O texto do portal nunca entra (rodada 7): o modelo lê a fala fechada da categoria.
- `poll` só publica se a cotação gravada na abertura ainda for a mais nova. A publicação reconfere de novo, na
  entrada do publicador e sob o lock da conversa: `Native::Base.publicacao_vale?`, chamado por
  `Tools::AutorizacaoDaExecucao#autorizacao`, recusa com `resultado_superado`. A retomada de envio pendente
  (`RetomadaDeEnvio`) faz a mesma pergunta e abandona a mensagem da lista quando surge cotação nova.
- **Uma lista por pedido, nunca a mesma duas vezes, e uma falha nunca perde as duas (rodadas 3 a 7,
  `InsuranceQuoteResult::Listas`; a revisão da rodada 7 mostrou que as três promessas ainda não se cumprem inteiras:
  achados P2-1, P2-2 e P2-3, abertos).** "A lista é mensagem entregue" (`lista_entregue?`) é `sequence` positivo (o
  publicador o avança na mesma transação, sob o lock da conversa, em que cria a mensagem) e nenhuma mensagem da
  execução com pendência de envio. A passada que publica (`emitir_lista`) lê, sob esse lock, as execuções anteriores
  desta ferramenta na conversa sobre a mesma cotação, da mais nova para a mais antiga: **leva** as que prometeram a
  lista numa fala (`done`, `failed`, e as `superseded` despachadas ou do mesmo turno) e não a têm entregue, com os
  códigos que a lista delas já levava (rodada 6); **desconta** as que viraram mensagem entregue depois de esta
  execução abrir (rodada 7: o cliente as recebeu depois de pedir de novo); e **para** na primeira entregue antes de
  ela abrir. Grava na própria linha, em `lista`, os códigos, as execuções levadas e a identidade da entrega. **A
  anterior só conta como levada depois de a lista nova ser aceita** pelo publicador (`Tools::EntregaAceita`) ou já ser
  mensagem (`lista_levada?`, rodada 7): antes disso ela continua valendo, a dela e a retomada do envio dela.
  `publicacao_vale?` recusa só a lista levada; a barreira da rodada 6 ("sem mensagem, barrada pela mais nova
  despachada") saiu, porque barrava antes do aceite.
- **A lista sai até ser aceita (rodada 7).** A passada que a emite devolve `running`; a seguinte encerra quando a lista
  foi aceita ou é mensagem, e, sem nenhum dos dois, a emite de novo. A primeira emissão pede a consulta seguinte no
  intervalo curto (`confirmar_logo`); a que sai de novo segue a progressão das tentativas. Prazo esgotado, tentativas
  no fim ou varredor: `closing_deliveries` publica a lista que ainda vale, a última tentativa, sem frase. A cotação
  lida deixar de ser a mais nova encerra em silêncio, sem lista e sem frase.
- **O preço que a própria cotação ainda está enviando não entra na lista (rodadas 4 a 6).**
  `ResultadoDaCotacao#a_caminho`: os códigos, pelo `LOTES_KEY`, dos lotes de preço (`PRECOS_KEY`) cuja mensagem
  existe com pendência de envio (com aceite ou sem) mais nova que a janela do varredor
  (`ReapStaleRunsJob::ENVIO_PENDENTE_JANELA`, 2 dias), ou que o publicador aceitou (`EntregaAceita::CHAVE`), não têm
  mensagem e foram emitidos há menos de `JANELA_DO_LOTE` (10 min, acima do teto de adiamentos); lote a caminho sem
  os códigos gravados (emitido antes desta versão) segura todos. O resultado inteiro e o pedido por seguradora tiram
  esses códigos da lista e dizem ao modelo que o preço está na fila de envio.
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
md5 (`b1758bb74c1a6ca87e9e7151d996ef7c`) com sete promessas, cada uma exercitada. Rodada 7: o parágrafo do motivo
diz que a ferramenta entrega se a recusa foi pelo veículo ou pela região, que a Lia conta com as palavras dela sem
acrescentar detalhe, e que nunca fala de restrição da pessoa; sem frase pronta e sem travessão. md5 novo
`a09fe65f1e2f82f910032e1c58be54de`, nove promessas.

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

## Riscos de regressão verificados, e como

| Risco | Como |
|---|---|
| Coluna "Com preço" do Super Admin | `medida_spec`: com a chave nova e 12 preços guardados, `seguradoras_com_preco` continua 11 (`entregues`); a execução da ferramenta da Lia não conta como cotação |
| Encerramento e fecho iguais | `Fecho`, `Comparativo#fechar`, `Encerramento` e o `closing_deliveries` da cotação sem alteração (o da ferramenta da Lia é novo na rodada 7, decisão 33); as suítes da fatia 1 (`*_fecha_sem_esperar_o_portal_spec`, `async_run_job_encerramento_parcial_spec`, `encerramento_spec`, `nenhum_estado_mudo`) passam |
| Ferramenta nova com o especialista desligado | `answerer_resultado_da_cotacao_spec` |
| Schema strict | `openai_schema_spec` (laço do catálogo + exemplo nomeado: uma propriedade, `required == ['seguradora']`, sem `anyOf`) |
| Nota privada | `answerer_resultado_da_cotacao_spec`: com responsável humano o `Responder` cala antes do modelo e nenhuma execução abre; humano que assume entre a fala e a publicação recebe os itens em nota privada |
| Execuções em voo no deploy | cotação correndo sem a chave ganha o resultado na consulta seguinte (`insurance_quote_resultado_spec`); a ferramenta lê essa linha como "ainda sem preço" e a encerrada sem a chave como "não guardado" (`insurance_quote_result_spec`); pedido repetido da linha sem a chave conta pelo contador (exemplos da entrega 10, inalterados) |
| `nenhum_estado_mudo` | estendido: confirmação curta + `done` com fecho, e itens da Lia sem frase pronta, sob as quatro formas de o especialista não escrever; texto ao modelo presente em todo estado sem preço |
| Pedido repetido não mente | `bound_pedido_repetido_spec`: sem entrega e com preço guardado não diz "0 resultados"; com entrega diz o número; só recusas é tentativa nova; janela de 24 h vale igual |
| Catálogo de outros agentes | `registry_spec` (tipo `custom` lê a config), `answerer_resultado_da_cotacao_spec` |
| Registro de recusa | `recusa_registro_spec` com o gatilho da saída nova |
| Contrato de nível | `base_contrato_de_nivel_spec` com `aceite`, `resultado_guardado?`, `publicacao_vale?` |
| Nenhum texto do portal ao modelo nem ao banco (rodada 7) | `insurance_quote_result_spec`: as 39 mensagens do corpus, no `kind` e no status do conector, e os 59 textos das revisões numa cotação só, perguntadas uma a uma: o modelo lê só `SEM_MOTIVO` ou as falas de `MOTIVOS`, nenhum texto aparece, e conta e pessoa saem no genérico; `resultado_por_seguradora_spec`: nenhum desses textos no JSON guardado |
| Palavra ao cliente em todo estado da lista (rodada 7) | `insurance_quote_nenhum_estado_mudo_spec`: a lista recusada pelo publicador até o prazo sai no encerramento, uma vez e sem frase; `answerer_resultado_da_cotacao_spec`: falha passageira, anterior no teto antes do aceite da nova, falha até o prazo, cotação nova e varredor. Não cobre a lista aceita que morre com o pedido seguinte (P2-1) nem a falha na publicação adiada (P2-3), achados abertos da revisão da rodada 7 |

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

- `RAILS_ENV=test bundle exec rails zeitwerk:check`: "All is good!", exit 0 (em `9c0bdcb8be`, `f727ce1844` e
  depois da rodada 3).
- RuboCop com lista explícita: 20 arquivos de `app/` (exit 0), 17 specs (exit 0), 4 arquivos do refactor
  (exit 0), 0 ofensas. Rodadas 2 e 3: os 38 `.rb` alterados desde `5742de5fcd`, 0 ofensas, exit 0. Rodada 4: os
  40 `.rb` alterados ou novos desde `5742de5fcd`, 0 ofensas, exit 0. Rodada 7: os 41 `.rb` alterados ou novos desde
  `5742de5fcd`, 0 ofensas (`--format json`, `offense_count` 0), exit 0; `zeitwerk:check` "All is good!", exit 0.

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
- **Os dois casos em que o cliente ainda pode receber a mesma seguradora em duas listas** (rodada 3), os dois
  com o cliente pedindo de novo no instante em que a lista anterior sai:
  1. a lista anterior, adiada, sai enquanto a execução do pedido novo ainda está `pending` (os segundos entre a
     chamada da ferramenta e o despacho do turno): ela não é barrada (decisão 22), e a lista nova repetia os
     códigos que o pedido novo nomeou. **Rodada 7:** a lista nova desconta a anterior que virou mensagem depois de
     ela abrir, e não repete; o que sobra é a ordem (resíduo R4 da rodada 7). O mesmo vale para a pendência de envio
     retomada depois de a nova abrir; a retomada antes, com a mensagem criada antes de a nova abrir, é o resíduo R5;
  2. mensagens cruzadas: a lista anterior vira mensagem logo antes de o pedido novo abrir. Aqui é um pedido
     novo de verdade; que o modelo veja a lista no histórico e não chame a ferramenta de novo é conduta do
     modelo, não verificada. **Corrigido pela revisão da rodada 7 (achado P3-3):** quando a lista anterior sai durante
     a chamada ao modelo do pedido novo (depois da mensagem do cliente e antes de a execução nova abrir), o histórico
     já foi montado e o modelo não tem como vê-la; o corte do desconto é a abertura da execução, e a lista nova a
     repete (sonda S4, falha nos dois SHAs). Não é conduta do modelo.
  Sem teste nos dois. A terceira revisão confirmou os dois com a cadeia humanizada real. O caso da execução
  `pending` que nunca é despachada (turno morto), que a revisão mostrou durar até o retry do turno, foi fechado
  na rodada 4 (decisão 25).
- **O lock da conversa na leitura das anteriores** (`emitir_lista`, antes `codigos_a_publicar`) fecha, pelo
  raciocínio, a corrida entre a composição da lista nova e a transação do publicador da anterior. A mutação que o
  tira (T21, U24, Y16) sobrevive: a corrida exige duas conexões concorrentes, e o spec roda numa só. A revisão da
  rodada 3 leu os caminhos de lock e não achou ordem invertida. O lock não cobre o intervalo entre a composição e
  o aceite da nova (resíduo R1 da rodada 7).
- **O lote de preço aceito cuja publicação adiada morre** fica "a caminho" para a Lia por até `JANELA_DO_LOTE`
  (10 min) depois da emissão (decisão 24). A janela é maior que o teto de adiamentos medido (6 a 8 min), não
  medida com a fila real. **E o contrário**: num incidente que pare a fila por mais de 7 a 10 min no meio do
  adiamento de um lote, o cliente que pergunta depois da janela recebe a lista da Lia, e o lote ainda sai quando a
  fila volta: o preço duas vezes (reproduzido pela quinta revisão com o relógio adiantado). Sem conserto: a
  publicação do lote não sabe que a Lia já mostrou aqueles preços.
- **Lote de preço com a mensagem criada e a pendência de envio gravada logo depois**: entre as duas escritas
  (milissegundos, com o Redis fora) a Lia veria o lote como entregue. Sem teste.
- **Três ou mais pedidos com listas levadas em cadeia e falhas no meio**: exercitados dois pedidos e a retomada do
  envio; a cadeia maior, só pela leitura.
- **A categoria do motivo contra texto real depois do #60**: medida no corpus sanitizado do conector (7 das 13
  mensagens `risco` com categoria, todas `veiculo`; nenhuma `regiao` no corpus, e a categoria da região só foi
  exercitada com texto sintético). Motivo real que nomeia o atributo com palavra fora dos padrões cai no genérico
  sem aviso; não há registro de quantos.
- **A confirmação curta encurta a janela entre as duas leituras** de 13 a 21 s para 3 a 8 s. A guarda das duas
  leituras depende de o portal já ter listado todas as seguradoras quando a lista se repete; nos brutos de
  13/09/2026 todas estavam listadas na primeira leitura, e o contrário não foi observado. Não medido com a
  janela nova.
- **Texto de conta da corretora ou de restrição da pessoa que nomeia um atributo do veículo ou da região sem nenhum
  termo das listas** sai com categoria. A revisão da rodada 7 escreveu 31 assim, todos `risco` no classificador real
  do conector, e **os 31 saem com categoria** (achado P3-1): 15 de conta ("Tipo de veículo sem aceitação para o seu
  código.", "Localidade sem aceitação na plataforma."), 14 da pessoa ("Proponente sem aceitação para esta região.",
  "Negativado: CEP sem aceitação.", "Tipo de veículo sem aceitação para menores de 25 anos.") e 2 de "modelo" que não
  é do veículo ("Este modelo de apólice não possui aceitação."). O modelo não recebe o texto, e nada é guardado além
  da categoria: o dano é a Lia afirmar um motivo que não é o verdadeiro ("não aceitou o veículo"). A versão commitada
  dizia que nenhum dos 59 textos das revisões era assim: é verdade, mas 58 deles não casam padrão de categoria nenhum
  e sairiam genéricos mesmo sem as listas de termos (sonda S6 da revisão); o filtro de termos é provado pelos exemplos
  "cada termo colado a 'Tipo de veículo não aceito'" do `motivo_da_recusa_spec`, e não por eles.
- **Ordem da lista depois da fala com a entrega humanizada ligada**, especificamente para a ferramenta nova. O
  adiamento pela cadeia do turno é o mecanismo geral (`async_publisher_spec`, "humanized chain deferral"); o
  spec de integração desta fatia usa a entrega clássica.
- **Resposta em áudio** (`deliver_voice`) seguida da lista.
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
