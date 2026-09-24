# Receita — o especialista de um ramo novo

> **Versão 2, 24/09/2026: provada em residencial.** A versão 1 foi escrita a partir de **auto** (10 a
> 21/09/2026). O piloto de residencial passou pelas oito fases entre 21 e 23/09 e está em produção na
> conta 16 desde 22/09; a rodada de teste de 24/09 fechou os últimos buracos (chat#634, #639). O próximo
> ramo, **empresarial** (decisão do CEO de 24/09), é o primeiro a nascer desta receita: o que ele
> revelar volta para cá no mesmo PR que o fechar.

Ordem de construção do especialista de um ramo de seguro (residencial, condomínio, empresarial,
vida, acidentes pessoais, fiança locatícia, viagem, celular, bike, vida global) e da passagem da
Lia até ele. Oito fases, cada uma com um **critério de passagem**. Critério vermelho bloqueia a fase
seguinte.

A ordem não é estética. Cada critério existe porque a falha correspondente aconteceu com auto e
custou dinheiro, tempo ou a confiança do Rodrigo. Estão todas em
[modos-de-falha.md](modos-de-falha.md): **leia antes de escrever a primeira linha**, não durante o
debug.

## Onde cada coisa mora

Um ramo novo mexe em dois repositórios, e esquecer um deles é a falha mais barata de cometer.

| Camada | Repositório | Onde |
|---|---|---|
| O que o portal exige de cada ramo | `autonomia-adapters` | `docs/agger/ramos-nao-auto.md`, `src/platforms/agger/knowledge/` |
| Montar o corpo e cotar | `autonomia-adapters` | `src/platforms/agger/ramos/` (`contratos.ts`, `configuracoes.ts`) |
| O formulário do ramo, com a origem de cada campo | `autonomia-adapters` | `src/platforms/agger/ramos/schema.ts` |
| As travas de regra do ramo | `autonomia-adapters` | `src/platforms/agger/ramos/condicionais.ts`, `validacao.ts` |
| A ferramenta que cota | `chat2you` | `app/services/autonomia/agents/tools/native/insurance_quote.rb` (uma só para os onze ramos: parâmetro `produto` em `insurance_quote/declaracao.rb`) |
| O formulário que o modelo vê | `chat2you` | `app/services/autonomia/insurance/parametros.rb` |
| Quais ramos a corretora cota | `chat2you` | conexão da conta (`capabilities`), lida por `consultar_produtos_cotacao` |
| O especialista e o manual dele | `chat2you` | `quote_agent/builder.rb` (`ESPECIALISTAS`), `quote_agent/instrucoes/` |
| O que o modelo lê sobre cada evento da cotação | `chat2you` | `insurance_quote/eventos.rb` (não há frase pronta ao cliente desde a PR C) |
| O que a equipe lê sobre quem ficou sem proposta | `chat2you` | `insurance_quote/nota_da_equipe.rb`, `tools/nota_interna.rb` |
| Em que conta o ramo está ligado | `chat2you` | `Insurance::Config` (`autonomia_insurance_ramos_liberados`, por conta) |
| A prova com conversa real | `chat2you` | `tools/cotacao-smoke/` |

## Estado de partida, medido em 24/09/2026

Com auto e residencial em produção, o que era trabalho de verdade na versão 1 virou caminho pronto. Um ramo
novo reaproveita tudo isto; o trabalho dele é o que está na coluna da direita.

| O quê | Estado em 24/09 | O que o ramo novo ainda faz |
|---|---|---|
| Formulário do ramo no adapter, com `descricao` e `valores` | pronto para residencial (`RAMOS_PRONTOS`, adapters#78) | escrever as descrições do ramo em `descricoes-por-ramo.json` e entrar em `RAMOS_PRONTOS` |
| Formulário que o modelo vê | gerado do schema, um por especialista (chat#592) | nada no chat, se o schema do adapter estiver completo |
| Endereço do imóvel pelo CEP do portal | pronto (`lookupCep`, adapters#88; `consultar_cep`, chat#597) | declarar os campos `derivado` do ramo |
| Pacote de coberturas e tetos | tabela por objeto e tetos pelo incêndio, residencial (adapters#80/#84/#86) | **medir** o pacote do ramo, seguradora por seguradora (Fase 3) |
| Nome do segurado pelo CPF | todos os ramos (adapters#92) | nada; conferir PJ (CNPJ) |
| Comparativo em PDF | todo ramo fora de auto usa `printType` 2 (adapters#90) | provar que o PDF do ramo sai |
| Especialista nos agentes que já existem | migration que insere o especialista (chat#604) | uma migration nova para o ramo |
| Especialista só onde a corretora cota | `Builder.disponivel?` pela conexão e `ramos_liberados` por conta | liberar a conta (escrita em produção, com OK) |
| Resumo da entrada no `ver_resultado` | auto e residencial (chat#605) | o resumo do ramo |
| Quem ficou sem proposta | a Lia não fala disso; a nota interna leva o motivo à equipe (chat#634, #639) | nada: é do bloco comum e da ferramenta |
| Vários bens na mesma conversa | uma cotação por bem, em paralelo (chat#612) | testar o ramo combinado com auto e residencial |
| Várias cotações da mesma corretora | a abertura é uma por vez por conexão; a cotação corre em paralelo (chat#621, adapters#94) | nada; medir em lote respeitando isso |

## Antes de desenhar: a jornada de auto, etapa por etapa

Auto é a referência de jornada e de processo (regra do Rodrigo, 22/09/2026). O residencial nasceu pedindo nome
(em auto sai do CPF) e escrevendo preço em texto (em auto o preço vai pelo PDF), e cada diferença era defeito
que o cliente sente. Preencha esta tabela para o ramo **antes** da primeira linha de código e mostre ao Rodrigo;
toda célula diferente de auto precisa de motivo.

| Etapa | Auto (a referência) | O ramo novo |
|---|---|---|
| Reconhecer o ramo | a Lia identifica e chama o especialista | idem |
| Coleta mínima | quatro dados; o resto tem padrão ou é buscado | quais são os mínimos do ramo |
| O que se busca sozinho | nome e nascimento pelo CPF; veículo pela placa | nome pelo CPF/CNPJ; endereço pelo CEP; e o que mais |
| Documento do cliente | a apólice anterior dá bem e coberturas, nunca o segurado; CPF só da pessoa indicada pelo nome | idem |
| Conferência grátis | `quote/validate` antes de cotar | idem |
| Envio | uma cotação por bem, em paralelo | idem |
| Preço | pelo comparativo em PDF; em texto só se perguntar antes do PDF | idem |
| Fecho | um evento, a Lia fala depois do PDF; nada sobre quem ficou sem proposta | idem |
| Ninguém cotou | `sem_aceitacao`: encaminha à equipe, sem motivo; nota interna | idem |
| Ver resultado | `ver_resultado_da_cotacao` com o resumo da entrada | o resumo do ramo |
| Proposta de uma seguradora | `enviar_proposta_da_seguradora` | provar que sai |
| Lapidação | mudar um dado e recotar parte da entrada anterior do mesmo bem | idem |
| Pedido repetido | 24 h responde do histórico | idem |
| Passagem à equipe | a fala da Lia de que vai encaminhar dispara o CRM | idem |

Depois da tabela, procure `auto?`, `RAMO_AUTO`, `ramo == '31'` e o nome do ramo pronto (`residencial`) nos dois
repositórios: cada condicional de ramo é um lugar onde o ramo novo pode cair no caminho errado em silêncio.

## Fase 0 — O ramo entra agora?

Construir um especialista custa dias e cotação paga. Não entra ramo por completude.

**Critério de passagem, as três coisas:**
1. Decisão do Rodrigo registrada: este ramo, agora.
2. O ramo cota pelo adapter **hoje**, numa cotação nova, e não na tabela de uma rodada antiga. Preço é
   da execução, não do ramo: a tabela de 07/09 não prova o dia de hoje.
3. Existe pelo menos uma corretora real com o ramo ativo e seguradoras prontas no mapa da conexão.

Se o item 2 falhar por credencial da corretora na seguradora (é o caso de vida global), o ramo não
entra: isso é cadastro, e nenhum código resolve.

**Medir em lote, sem travar a conta.** Abrir várias cotações no mesmo segundo derruba a conferência de login
das seguradoras (cada abertura confere umas 15) e, em 23/09/2026, fez o firewall do portal bloquear a conta 16.
Abra **uma cotação por vez**, espere ela aparecer no portal antes da próxima e leia os resultados em paralelo:
ler é de graça e não disputa nada. Dado de cliente fictício **novo** a cada cotação.

## Fase 1 — O adapter cota o ramo, provado por leitura de volta

**Antes de qualquer cotação, leia o que já foi descoberto.** A colheita de 04/09/2026 levantou, do código do portal e
da API ao vivo, o formulário de residencial, vida e empresarial: payload, campos obrigatórios, mínimos para cotar,
pacote de coberturas, tabelas de código e armadilhas (`~/dev/projetos.noindex/agger-descoberta/ramos/<ramo>/*-campos.json`
e o README ao lado). Em 24/09 treze cotações de empresarial redescobriram o que estava lá (modo F8). Meça só o que a
descoberta não responde.

Antes de mexer no chat2you, prove a ponta que custa dinheiro.

**Toca produção e custa cotação paga: aprovação do Rodrigo para a rodada**, a não ser que ela já tenha sido
dada para o piloto em curso.

**Critério de passagem:**
- A cotação sai **pelo mesmo caminho que o chat2you usa** (a entrada que `quote_input.rb` monta, chegando a
  `listInsurersForQuote` e ao `startRamo` do adapter), e não pelo script de prova. O script injeta dado e override
  que o produto não tem: ele prova o corpo, não o produto.
- Uma cotação real pelo adapter, com dado de cliente fictício **novo** (pedido repetido em 24 horas é
  respondido do histórico, não cota).
- **Lida de volta no portal:** o que o portal gravou tem os campos que mandamos, com os valores que
  mandamos. Preço mudar não prova travessia: o mesmo corpo dá preços diferentes em execuções
  diferentes. Ler de volta é determinístico.
- Pelo menos uma seguradora com preço. Recusa nomeada pelo portal é informação: registre no
  `ramos-nao-auto.md` qual campo ela nomeou.

O filtro de seguradoras do adapter descarta seguradora que cota (modo B10). O override
`SEGURADORAS_DO_PORTAL` em `ramos/contratos.ts` **não resolve em produção: só o script de prova o lê.** Confira
quais seguradoras o portal oferece para o ramo na tela, compare com as que o caminho do produto acionou, e leve a
correção para o caminho do produto se a lista divergir.

**Endereço do imóvel: a consulta de CEP é a do portal.** Medido em 21/09/2026 com 20 CEPs (capitais, interior,
cidades de CEP único e um inexistente), a consulta que auto já usa (`GET /calculo/cep`, `lookupCep` em
`http/quote.ts`) achou 19 de 19 CEPs válidos, entre 141 e 507 ms. O ViaCEP achou 16 de 19 e falhou numa capital.
Três consequências para o ramo:
- O logradouro vem no formato do portal, com a faixa de numeração ("Avenida Paulista - de 612 A 1510 - Lado Par").
  Confira na leitura de volta, e na proposta impressa, como ele sai.
- Cidade de CEP único volta sem rua, no portal e no ViaCEP: o especialista pergunta a rua ao cliente.
- CEP inexistente não volta vazio: o portal responde erro 502 depois de uns 3 segundos. O adapter tem de tratar isso
  como "confirme o CEP com o cliente", e não como portal fora do ar.

Técnica que resolve ramo novo quando o corpo não é conhecido: cotar pela tela do portal, pegar o id na
URL de resultado, ler pela API e copiar o corpo exato (`ramos-nao-auto.md`, seção 4). **Cuidado:** a
leitura de volta traz a senha da corretora em cada seguradora, em texto claro. Use os scripts do
adapter, que removem os segredos e recusam gravar dentro do repositório:
`scripts/discovery/resumir-cotacao-do-portal.ts` e `scripts/discovery/baixar-cotacao-do-portal.ts`, no
`autonomia-adapters`.

## Fase 2 — O formulário do ramo chega ao modelo como campos

É a entrega 2 de auto feita para o ramo, e é a mais importante desta receita.

Em auto, até 10/09, o modelo entendia o pedido, escrevia num campo de texto solto, e o campo era
ignorado. Ramo que não está pronto ainda cai nesse desenho: um JSON livre em `dados`, que custa uma rodada de
ferramenta a cada cotação, e cada nome de campo que o modelo digita errado é um dado que não chega.

**O caminho, provado em residencial (chat#592):** o formulário do ramo é gerado do `schema.ts` do adapter, um por
especialista. Nada de nome de campo, código ou padrão digitado no chat2you. Para o ramo novo:
- **No adapter:** escrever a descrição de cada campo de origem `cliente` em `knowledge/descricoes-por-ramo.json`,
  ligar os domínios de valor do ramo em `DOMINIOS_POR_RAMO` (o mesmo campo muda de lista entre ramos) e pôr o
  ramo em `RAMOS_PRONTOS`. A suíte reprova ramo pronto com campo sem descrição ou código sem valores.
- **No chat2you:** nada, se o schema do adapter estiver completo.
- **O schema guardado não se renova sozinho** (modo A17, issue chat#383): depois de publicar o adapter, a conexão
  da corretora é sincronizada ("Atualizar produtos"), ou o chat segue com o formulário velho.

**Critério de passagem:**
- Todo campo que o formulário declara **chega ao envio**. Guarda automática: campo declarado que não
  atravessa reprova a suíte (o equivalente de `quote_input_travessia_spec` para o ramo).
- Campo novo no adapter sem descrição **quebra**, não some.
- Só o campo de origem `cliente` é pergunta. Os de origem `derivado` o adapter busca; os de origem
  `escolha` têm padrão seguro, que vem de recusa nomeada pelo portal. O agente que pergunta sessenta
  coisas porque o formulário tem sessenta campos é o defeito que a issue adapters#34 nomeia.
- Em modo `strict` da OpenAI não existe campo opcional: todo campo vai em `required`, e o opcional se
  diz pelo tipo com `null`. Um opcional mal declarado derruba a chamada inteira e deixa o agente mudo.
- A descrição de cada campo **não traz valor entre crases nem travessão**: o modelo copia os dois para
  o WhatsApp.
- A decisão de desenho fica registrada: um formulário por especialista (cada um vê o do seu ramo) ou
  um formulário com todos os ramos. O primeiro é o esperado; o segundo multiplica o tamanho do que o
  modelo lê a cada turno.

## Fase 3 — As regras que custam dinheiro viram trava

Regra que custa dinheiro escrita só no manual é intenção: a IA já violou o próprio manual em ponto
que custava dinheiro, duas vezes no mesmo dia.

**Critério de passagem:**
- Cada regra condicional do ramo é uma trava no adapter, com um teste que **falha sem ela**. Em residencial,
  **os valores padrão já respeitam as proporções** (`configuracoes.ts`, `valoresDeCobertura`: alagamento fora,
  incêndio como base e as demais baixas, piso de danos morais; testes em `ramos-no-adapter.test.ts`). O que não
  existe é conferir o **valor que o cliente informa**: a função não mexe no que já veio preenchido (modo B4). As
  regras conhecidas: danos elétricos até 50% de incêndio; alagamento fora por padrão;
  vendaval e impacto de veículos são uma cobertura só, e o portal soma os dois
  (`ramos-nao-auto.md`, seção 2).
- A trava **pergunta ao cliente** o que falta; ela não recusa a cotação em silêncio nem a manda para um
  humano. Recusa que vira escalada é defeito (o cenário `pj-sem-nascimento` da suíte existe por isso).
- **Pessoa física e jurídica conferidas separadamente.** A trava de empresa de auto cobrou nascimento e
  sexo de um CNPJ e matou todas as cotações de empresa em 20/09 (adapters#70). Condomínio é
  sempre pessoa jurídica, e empresarial quase sempre.
- **O pacote padrão depende do que se protege**, e cada variante é medida: em residencial, "prédio e
  conteúdo" cotou em 10 de 11, "só prédio" em 7 de 11 e "só conteúdo" em 6 de 11 até cada cobertura
  recusada sair do pacote daquela variante (`PACOTE_POR_OBJETO`).
- **Teto que a seguradora não nomeia se acha por bisseção.** A Tokio recusava "cobertura limitada a 5% do
  incêndio" sem dizer qual; três cotações, cada uma mudando uma cobertura só, acharam Registros e Documentos.
- **Valor abaixo do mínimo de uma seguradora não bloqueia o cliente**: cota com o mínimo e a Lia explica
  (decisão do Rodrigo, 22/09). Trava que deixa quem insiste sem cotação nenhuma é pior que o limite.
- Cópia local de dado nunca fica atrás de fornecedor pago: se a regra usa um dado que a conversa já tem,
  ela não depende da consulta paga para funcionar.

## Fase 4 — O manual do ramo

Arquivo `quote_agent/instrucoes/especialista_<ramo>.md`, lido **depois** do bloco comum
(`comum_especialista.md`), que vale para todo ramo e não é revogado por ele.

**Critério de passagem:**
- **Direção, não exemplo.** O manual diz o momento e o que obter; as palavras são do modelo. Frase de
  exemplo é copiada inteira e sai igual para todo cliente.
- **Nenhum valor de cobertura escrito no manual.** Quem tem o número é um lugar só (o adapter). Em auto,
  o manual prometia o dobro do que era cotado.
- **Nenhuma promessa sem capacidade.** Toda ferramenta citada existe, e há guarda automática que cruza
  as citações com as ferramentas reais. Promessa nova entra na tabela de promessas do manual com o
  código que a sustenta.
- **Procurar na conversa antes de pedir.** O especialista recebe a conversa e os documentos; pedir o que
  está na frente dele vira pergunta repetida ao cliente.
- **Sem contradição com o bloco comum nem dentro do próprio arquivo.** Regra nova numa seção e regra
  oposta noutra seção, mais perto da ação: o modelo segue a mais perto. Procure no arquivo inteiro.
- O manual é assinado (md5) como os outros dois: mudou uma letra, a suíte reprova até alguém reler.
- **Quem ficou sem proposta não é assunto do cliente** (decisões do CEO de 23 e 24/09, chat#634 e #639): nem
  recusa, nem prazo, nem instabilidade. O bloco comum já diz isso; o manual do ramo não pode reabrir. Nenhum
  texto que o modelo lê pode trazer a frase que não se quer ouvir: ele a copia (modo D13).
- **Quem é o segurado, o cliente decide; o documento dá o CPF da pessoa que ele NOMEOU.** Com o nome dito e
  um documento ou cotação da conversa trazendo o CPF de alguém com esse nome, use-o; indicação só por
  parentesco, ou dois CPFs com o mesmo nome, pergunta (modo C12).
- A instrução inteira (principal + comum + ramo) cabe no limite do agente. O histórico de versões guarda o
  que o agente aceita desde a chat#578.

## Fase 5 — O especialista existe para a Lia, e só onde a corretora cota

A Lia é genérica: não sabe ramo nenhum. Ela identifica o ramo e chama `consultar_<ramo>`. O que falta
não é na instrução dela, é no que ela enxerga.

**Critério de passagem:**
- A entrada do ramo em `ESPECIALISTAS`, com uma descrição que diz **quando** chamar (é o que a Lia lê
  para escolher).
- **O ramo chega aos agentes que já existem**, e não só aos que nascem depois (modo C9). O caminho é uma
  migration que insere o especialista nos agentes de cotação (a de residencial é a 20260922200000). É
  escrita no banco de produção: aprovação do Rodrigo, com backup e rollback escritos antes.
- **O especialista só fica disponível na conta cuja conexão cota o ramo** (`Builder.disponivel?`) **e que
  liberou o ramo** (`Insurance::Config`, `autonomia_insurance_ramos_liberados`). Liberar a conta é escrita
  em produção: OK do Rodrigo. Depois de mudar o schema no adapter, a conexão precisa ser sincronizada
  ("Atualizar produtos" na tela de Conexões), senão o chat segue com o formulário antigo.
- Numa conversa real, a Lia chama o especialista do ramo certo, e **numa conta sem o ramo** ela diz que
  não cota aquele seguro e oferece o que a corretora cota, sem abrir cotação.

## Fase 6 — Prova real, ponta a ponta

**Toca produção:** a suíte lê o banco de produção e cada cenário é uma cotação real paga. Aprovação do Rodrigo
para a rodada, a não ser que já dada para o piloto em curso.

**Critério de passagem:**
- Cenários do ramo na suíte de conversas (`tools/cotacao-smoke/cenarios.json`), cada um com o campo
  `motivo` dizendo qual falha ele pega. Veredito lido do banco, nunca do texto da resposta.
- Uma cotação real pela conversa: execução nova, cotação concluída, comparativo em PDF na conversa.
- **Antes de rodar, a conversa de teste está sem responsável humano.** Com responsável, a Lia não
  responde por desenho, e a suíte mede o nada (21/09). **Tirar o responsável é escrita em produção: peça ao
  Rodrigo que desatribua pelo painel.** Não use `toggle_status` com token de usuário: ele zera o `ai_assignee` e a
  IA some da conversa (`tools/cotacao-smoke/README.md`).
- A conversa inteira lida por gente: o nome usado, o bem chamado pelo que ele é, primeira pessoa, uma
  mensagem só com o comparativo. Teste não prova voz.
- **O roteiro da rodada de teste é fixo**: o ramo sozinho; o ramo e depois outro ramo na mesma conversa;
  dois bens do ramo de uma vez; o ramo combinado com auto e residencial; e, entre as rodadas, **a conversa
  resolvida**. Histórico de rodada anterior contamina a seguinte: em 24/09 "o mesmo CPF da cotação do carro"
  pegou o CPF de outro carro da véspera (modo C13).
- O caminho da rodada: a sessão do WhatsApp do Rodrigo no WAHA (`5511937016094`) para a Lia (`555196569128`),
  e a telemetria ligada antes (mensagens, execuções, notas internas, fila do worker e a Lambda).

## Fase 7 — Operação

**Critério de passagem:**
- A medição conta as cotações do ramo por corretora (`/super_admin/insurance_measurement`).
- A seguradora que recusa a credencial da corretora aparece na tela de Conexões, nunca para o cliente.
- Toda recusa de cotar do ramo deixa registro com conversa, agente, motivo e o que faltava.

## Antes de declarar pronto, em qualquer fase

- **O check verde da PR não conta.** O CI de testes completo está desligado por decisão do Rodrigo, e o
  único check que roda pula os testes quando a mudança não é de e-mail. O portão é a suíte local
  inteira do módulo (`spec/models/autonomia`, `spec/requests/api/v1/accounts/autonomia`,
  `spec/services/autonomia`, `spec/jobs/autonomia`) e a suíte do adapter, lidas no resultado em JSON:
  código de saída, falhas e erros fora de exemplo.
- **Todo teste novo é visto falhando antes da correção**, pelo motivo certo.
- **Toda expectativa reescrita é provada por mutação:** desfaça a mudança de produção e conte quantos
  testes reprovam. Nenhum reprova, o teste é enfeite.
- **Revisão adversarial independente** antes do pedido de merge. CI não é revisão.
- **Merge e deploy só com OK explícito do Rodrigo**, e o deploy acompanhado até o fim, com a imagem
  conferida por dentro do container.
- **Ordem do deploy: o chat antes do adapter** sempre que o chat precisa entender o que o adapter passa a
  mandar. Em 24/09 a recusa escrita nos planos (adapters#97) só subiu depois do chat que a deixa fora da fala
  da Lia: na ordem inversa, o chat antigo classificaria o texto novo.
- **O merge no chat dispara o deploy das duas stacks**, uns 40 minutos de troca de instância. Outra sessão pode
  estar mexendo no mesmo repositório: combine a vez antes do merge.

## Como esta receita é mantida

Quem aplicar a receita num ramo e achar um buraco corrige **aqui**, no mesmo PR, e registra o modo de
falha em [modos-de-falha.md](modos-de-falha.md) com sintoma, causa, o teste que pega e a fonte. Resumo
desta receita em outro lugar é proibido: resumo copiado diverge do original.
