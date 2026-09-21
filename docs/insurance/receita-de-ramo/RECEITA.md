# Receita — o especialista de um ramo novo

> **RASCUNHO até o piloto de residencial passar por todas as fases.** Esta receita foi escrita a
> partir do que se construiu para **auto** entre 10/09 e 21/09/2026. O que ela afirma sobre auto
> foi observado em produção; o que ela prevê para outro ramo é **analogia** até o piloto provar. Cada
> buraco que o piloto revelar volta para cá no mesmo PR que o fechar.

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
| A voz das frases da cotação | `chat2you` | `insurance_quote/frases.rb` |
| A prova com conversa real | `chat2you` | `tools/cotacao-smoke/` |

## Estado de partida, medido em 21/09/2026

Não comece do zero: a maior parte do caminho de auto já serve aos outros ramos.

| O quê | Estado | Origem |
|---|---|---|
| O portal: campos de cada ramo | medido nos dez ramos em 06/09 | teste real, `docs/agger/ramos-nao-auto.md` |
| O adapter monta o corpo do ramo | nove de dez com preço em 07/09; vida global não cota por credencial da corretora | teste real **pelo script de prova**, `knowledge/cotacao-pelo-adapter.json` |
| O formulário do ramo no adapter | existe para todos, com `origem` por campo, **mas sem descrição nem valores fora de auto** ("Só auto tem, por enquanto") | código, `schema.ts` (issue adapters#34) |
| A ferramenta de cotação no chat2you | uma para os onze ramos | código, `declaracao.rb` (parâmetro `produto`) |
| O mapa de ramos por corretora | lido da conexão; a conta 16 tem os onze ativos | produção, 21/09 |
| **O formulário que o modelo vê** | **só auto.** Fora de auto o modelo escreve um JSON solto no parâmetro `dados` | código, `declaracao.rb` e `parametros.rb` |
| **O especialista do ramo** | **só auto** | código, `ESPECIALISTAS` |
| **Especialista novo em agente que já existe** | **não existe caminho.** O Builder cria especialista só no nascimento, e recusa agente repetido | código, `Builder#call` |
| **Especialista só onde a corretora cota o ramo** | **não existe.** O especialista aparece se estiver ligado, sem olhar o mapa da corretora | código, `Answerer#enabled_specialists` |
| **Cotar pelo caminho do produto** | **não provado.** A prova de 07/09 injetou o endereço do imóvel à mão (`scripts/discovery/provar-ramo-pelo-adapter.ts`) e aplicou um override que o produto não lê. Pelo caminho real, o formulário marca o endereço do imóvel como `derivado`, mas nada o deriva (`configuracoes.ts`, `enderecoDoImovel`; `quote.ts`: "aqui nao ha consulta de CEP"), e o chat2you manda só CEP e número (`quote_input.rb`). Resultado esperado: "Logradouro deve ser informado corretamente" | código, adapter e chat2you |
| **Filtro de seguradoras no caminho do produto** | **sem correção.** O override `SEGURADORAS_DO_PORTAL` só é lido pelo script de prova; o produto usa `listInsurersForQuote`, que descarta seguradora que cota (modo B10) | código, `index.ts`, `quote.ts` |
| **Descrição dos campos fora de auto** | **não existe.** O schema dos outros ramos sai sem `descricao` e sem `valores`; o chat2you só busca o schema de auto na sincronização (`connections/sync.rb`) | código |

As linhas em negrito são o trabalho de verdade de um ramo novo, e várias delas são **no adapter**, não só no
chat2you. A tabela de 07/09 prova que o corpo do ramo é aceito pelo portal; ela não prova que o produto cota.

## Fase 0 — O ramo entra agora?

Construir um especialista custa dias e cotação paga. Não entra ramo por completude.

**Critério de passagem, as três coisas:**
1. Decisão do Rodrigo registrada: este ramo, agora.
2. O ramo cota pelo adapter **hoje**, numa cotação nova, e não na tabela de uma rodada antiga. Preço é
   da execução, não do ramo: a tabela de 07/09 não prova o dia de hoje.
3. Existe pelo menos uma corretora real com o ramo ativo e seguradoras prontas no mapa da conexão.

Se o item 2 falhar por credencial da corretora na seguradora (é o caso de vida global), o ramo não
entra: isso é cadastro, e nenhum código resolve.

## Fase 1 — O adapter cota o ramo, provado por leitura de volta

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

Técnica que resolve ramo novo quando o corpo não é conhecido: cotar pela tela do portal, pegar o id na
URL de resultado, ler pela API e copiar o corpo exato (`ramos-nao-auto.md`, seção 4). **Cuidado:** a
leitura de volta traz a senha da corretora em cada seguradora, em texto claro. Use os scripts do
adapter, que removem os segredos e recusam gravar dentro do repositório:
`scripts/discovery/resumir-cotacao-do-portal.ts` e `scripts/discovery/baixar-cotacao-do-portal.ts`, no
`autonomia-adapters`.

## Fase 2 — O formulário do ramo chega ao modelo como campos

É a entrega 2 de auto feita para o ramo, e é a mais importante desta receita.

Em auto, até 10/09, o modelo entendia o pedido, escrevia num campo de texto solto, e o campo era
ignorado. Fora de auto, hoje, o desenho é o mesmo: um JSON livre em `dados`, com a instrução de mandar
`{}` na primeira chamada para descobrir o que perguntar. Isso custa uma rodada de ferramenta a cada
cotação, e cada nome de campo que o modelo digita errado é um dado que não chega.

**O que muda:** o formulário do ramo passa a ser gerado do `schema.ts` do adapter, como o de auto é
gerado hoje em `Parametros.de_auto`. Nada de nome de campo, código ou padrão digitado no chat2you.

Hoje isso tem três pré-requisitos que não existem:
- **No adapter:** os campos dos outros ramos saem sem `descricao` e sem `valores` (`schema.ts`: "Só auto tem, por
  enquanto"). Escrever as descrições do ramo, que ensinam a extrair da conversa com as palavras do cliente, é
  entrega do adapter, e a regra "campo sem descrição quebra" reprovaria o formulário até lá.
- **No chat2you:** a sincronização busca só o schema de auto (`connections/sync.rb`), e a ferramenta só lê o de
  auto (`Declaracao#schema_de_auto`).
- **O schema guardado não se renova sozinho:** só entra de novo quando a varredura da conexão roda (modo A17,
  issue chat#383). Com dez ramos, isso deixa de ser incômodo e vira defeito.

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
  sempre pessoa jurídica.
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
- As categorias de motivo de recusa que o especialista pode explicar ao cliente hoje são só de veículo e região
  (modo D12). Recusa de imóvel sai genérica até ganhar categoria própria, pelo mesmo molde fechado.
- A instrução inteira (principal + comum + ramo) cabe no limite do agente. **O histórico de versões da
  instrução tem teto de 20.000 caracteres, menor que o do agente**, até a #578 ser mergeada (em 21/09 ela está
  aberta). Com a #578 fora, o manual do ramo pode quebrar o histórico em silêncio.

## Fase 5 — O especialista existe para a Lia, e só onde a corretora cota

A Lia é genérica: não sabe ramo nenhum. Ela identifica o ramo e chama `consultar_<ramo>`. O que falta
não é na instrução dela, é no que ela enxerga.

**Critério de passagem:**
- A entrada do ramo em `ESPECIALISTAS`, com uma descrição que diz **quando** chamar (é o que a Lia lê
  para escolher).
- **O ramo chega aos agentes que já existem**, e não só aos que nascem depois (modo C9: é o mesmo buraco das
  ferramentas gravadas no nascimento). Hoje não há esse caminho.
  Criar o registro do especialista em produção é escrita no banco: aprovação do Rodrigo, uma vez por
  ambiente, com backup e rollback escritos antes.
- **O especialista só fica disponível na conta cuja conexão cota o ramo**, lido do mapa da conexão. Uma
  corretora sem residencial não recebe o especialista de residencial. Hoje isso não existe.
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

## Como esta receita é mantida

Quem aplicar a receita num ramo e achar um buraco corrige **aqui**, no mesmo PR, e registra o modo de
falha em [modos-de-falha.md](modos-de-falha.md) com sintoma, causa, o teste que pega e a fonte. Resumo
desta receita em outro lugar é proibido: resumo copiado diverge do original, e a skill
`especialista-de-ramo` aponta para cá em vez de repetir.
