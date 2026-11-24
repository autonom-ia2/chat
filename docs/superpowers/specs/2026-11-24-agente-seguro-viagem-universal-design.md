# Agente pronto "Seguro Viagem Universal" — desenho

Issue: #3211 · Data: 24/11/2026 · Estado: rascunho para aprovação do Rodrigo

## 1. Intenção

O corretor de seguros contrata, na área de Agentes, um agente que **vende seguro viagem da Universal ao viajante final, de ponta a ponta**: tira dúvida com base oficial, cota, ajuda a escolher, monta a proposta e manda o link de pagamento. Hoje isso só existe em fluxos de automação externos, montados à mão para cada corretora.

O produto é a **instrução + as ferramentas + a qualidade da conversa**. Por isso a instrução é nossa (o corretor não edita) e a qualidade da conversa não pode ficar abaixo do que os fluxos externos já entregam (seção 8).

## 2. Objetivos

1. Cartão "Seguro Viagem Universal" na área de Agentes de **todas as contas**, com página própria explicando o que o agente faz.
2. Contratar pede só: **nome do agente**, **nome da corretora**, **descrição da corretora**. Depois, o **login e a senha do portal da Universal**. Depois, a **caixa** em que ele atende (como qualquer agente).
3. Instrução mantida por nós: melhoria chega a todas as cópias contratadas no próximo deploy, sem ação do corretor.
4. Base de conhecimento a partir de fontes oficiais da Universal, igual para todas as cópias.
5. Duas ferramentas nativas: **cotar** e **gerar proposta com link de pagamento**, chamando a API da Universal direto da plataforma.
6. Qualidade da conversa igual ou melhor que a dos fluxos externos atuais (debounce, quebra em pedaços, cadência, entrada e saída).

## 3. Fora do escopo

- Outras seguradoras de viagem (a estrutura comporta, mas só a Universal entra agora).
- Qualquer mudança de comportamento no Agente de Cotação existente (`insurance_quote`).
- Emissão do bilhete após o pagamento, pós-venda e sinistro.
- Fluxo externo de automação (n8n) no caminho da cotação e da proposta.

## 4. Anti-objetivos (falhou mesmo se "funcionar")

- O preço ou o plano da proposta vir do texto do modelo, e não da cotação guardada.
- Login ou senha da Universal aparecer em tela, log, resposta da API ou mensagem.
- Erro de login da Universal chegar ao viajante.
- Comissão, markup, ranking ou qualquer dado interno da tarifa chegar ao viajante.
- A conversa ficar mais "robótica" que a dos fluxos atuais: responder a cada mensagem picada, mandar bloco gigante, responder rápido demais.
- O corretor conseguir alterar a instrução por qualquer caminho (tela, Construtor, desfazer, API).

## 5. Decisões do Rodrigo (24/11/2026)

| # | Decisão |
|---|---|
| D1 | Agente pronto para contratar, visível em todas as contas. |
| D2 | Contratar pede só nome do agente, nome da corretora e descrição da corretora; não edita a instrução. Inspiração: aba "Agente" da página Cotação. |
| D3 | Tela de login e senha do portal da Universal no agente; os dados vão para as ferramentas de cotação e proposta. |
| D4 | Depois de contratar, o corretor escolhe a caixa. |
| D5 | Melhorias na instrução chegam a todas as cópias. |
| D6 | Público: viajante final (B2C). |
| D7 | Tudo dentro da plataforma, sem n8n na cotação e na proposta. |
| D8 | A qualidade da conversa dos fluxos atuais (debounce, quebra, cadência, entrada e saída) não pode ser perdida. |
| D9 | Instrução de referência: a instrução reformulada de outro agente de seguro viagem (B2B, outra seguradora), adaptada à Universal e ao viajante final. |
| D10 | Testes contra a API de produção da Universal. Uma proposta de teste fica registrada na Universal (sem pagamento). |
| D11 | Material da base: fontes oficiais da Universal, buscadas na web. |
| D12 | Piloto em uma conta piloto da Fase 2; teto de IA paga dos testes: US$ 10. |

## 6. Como funciona (o que foi decidido no código)

### 6.1 O agente contratado

- `agent_type: 'sdr'` (vendedor), igual ao modelo de ramo `seguro_viagem.yml` que já existe.
- Marca de origem em `config['contratado']`:
  `{ 'modelo' => 'seguro_viagem_universal', 'nome_agente', 'nome_corretora', 'sobre_corretora' }`.
  A chave entra na lista de chaves reservadas do PATCH do agente (o corretor muda o nome do agente pela tela, nunca a marca nem o modelo).
- `Agent#contratado?` lê a marca. `Agent#instrucao_mantida?` passa a ser `insurance_quote` **ou** `contratado?`. Com isso todos os escritores da coluna `instruction` (Construtor, ajuste, desfazer, refresh, API) já recusam, sem código novo em cada um. O comportamento do `insurance_quote` não muda: a outra parte do "ou" é a mesma de hoje.
- `Agent#instrucao_do_sistema` ganha o ramo do contratado: lê o arquivo do modelo **a cada turno** e troca `$nomeAgente`, `$nomeCorretora`, `$sobreCorretora` e `$dataDeHoje` (seção 8). É o mesmo mecanismo do `insurance_quote` (`QuoteAgent::Builder.instrucao_do_principal`), e é o que faz a melhoria chegar a todas as cópias no deploy (D5).
- Os checks `== 'insurance_quote'` espalhados (answerer, interação, prompt builder, ferramentas prontas, tools controller, front) **não** são tocados: o contratado é um `sdr` normal para eles.
- Módulo novo `Autonomia::Agents::Contratados` com o catálogo (por enquanto um item) e o `Contratar` (serviço que cria o agente). O arquivo da instrução mora em `app/services/autonomia/agents/contratados/seguro_viagem_universal/instrucao.md`.
- Ferramentas fixas do modelo, lidas do catálogo em runtime (como `ferramentas_mantidas` da Lia): as 2 nativas da Universal + as prontas `pronta_cpf`, `pronta_cep`, `pronta_cidades` (nomes a confirmar no catálogo das prontas). O corretor não adiciona nem tira ferramenta deste agente.

### 6.2 Acesso à Universal (login e senha)

- Model novo e pequeno, `Autonomia::Agents::AcessoDaSeguradora`: `account_id`, `seguradora` (`'universal'`), `login` e `senha` com `encrypts`, `estado` (`nao_conferido`, `ok`, `recusado`), `conferido_em`, `motivo` (código, nunca mensagem crua da Universal). Único por `(account_id, seguradora)`.
- **Não** reutiliza `Autonomia::Insurance::Connection`: ela é do conector do Agger, e vários pontos (`available_for?`, `CepLookup`, `Builder.produtos_da_conta`) leem "qualquer conexão usável" da conta sem filtrar provedor. Uma linha da Universal ali seria lida como conexão da Lia.
- A tela manda a senha uma vez (POST) e nunca a recebe de volta; mostra só o login mascarado e o estado.
- Ao salvar, a plataforma confere o acesso com `GET /v1/Emissor/Setup` (não cota nem compra). A resposta também diz o que o emissor pode fazer — `soCotacao`, `emiteFaturado`, `emiteBoleto`, `tarifaAcordo` — e isso fica guardado no acesso. Resultado: `ok` ou `recusado`; com `soCotacao: true` a tela avisa que esse login só cota e a ferramenta de proposta não fica disponível.
- O agente só pode ser ligado numa caixa com acesso `ok` (mesma ideia do "tem onde trabalhar").

### 6.3 Cliente da API da Universal

- `Autonomia::Seguradoras::Universal::Cliente`: `setup` → `GET /v1/Emissor/Setup`; `cotar(pedido)` → `POST /v1/Cotacao`; `comprar(pedido)` → `POST /v1/Compras`; `destinos` → `GET /v1/destinos` (264 países com região, guardado em cache para validar a sigla). Cabeçalhos `Login`, `Senha`, `Content-Type`, `Accept`.
- Fontes do contrato: a coleção Postman "Documentação da API - Universal Assistance (Cliente)" (exemplos de 2023–2024) e o fluxo de proposta mais novo (08/2025), que é mais recente que a coleção onde os dois divergem.
- Tabelas de código da API: tipo de tarifa `1` Folheto, `2` Acordo; tipo de viagem `1` única, `2` multiviagens, `3` banco de dias; classificação `1` todos, `4` lazer, `5` estudante, `6` negócios, `7` gestantes, `8` marítimo; forma de pagamento documentada `1` faturado, `2` cartão, `3` boleto.
- URL base por ENV `UNIVERSAL_API_BASE_URL` (padrão: o host de produção usado hoje).
- Timeout explícito. Nunca loga cabeçalho nem corpo (tem CPF, nascimento, endereço). Erro vira código: `acesso_recusado` (401/403), `pedido_invalido` (4xx com mensagem de campo), `indisponivel` (5xx, timeout).

### 6.4 Ferramenta `cotar_seguro_viagem`

**Princípio (Rodrigo, 24/11):** cotar não pode causar atrito. O viajante fala como fala — "cota pra mim um seguro pra Portugal, 1 pessoa de 45 anos, de 02/02 a 06/02" — e a plataforma traduz para o pedido da Universal. Para cotar pede-se só o que muda o preço; nome, CPF e nascimento ficam para a proposta.

Parâmetros (o modelo preenche; tipos estritos):
- `destinos`: array de siglas de país (ISO 3166 alfa-2). O modelo traduz "Portugal" → `PT`, "Europa" → os países do roteiro. Viagem nacional: `["BR"]` (a confirmar no teste).
- `data_saida`, `data_retorno`: datas (AAAA-MM-DD). O modelo resolve "02/02 a 06/02" com a data de hoje que recebe no turno (seção 8, P6); nunca presume "hoje" como saída.
- `idades`: array de inteiros, uma por viajante (`[45]`). **Idade, não data de nascimento.**

Comportamento:
- Converte cada idade numa data de nascimento técnica que dá exatamente essa idade na data de saída (saída − idade anos − 6 meses), porque a API exige data. Essa data nunca aparece ao viajante e é trocada pela real na proposta.
- Valida datas (saída ≥ hoje no fuso da conta; retorno ≥ saída) e idades; erro volta como recusa com o campo faltando, para o modelo perguntar.
- Monta o pedido: `tipoViagem: 1` (viagem única); `tipoTarifa` = `2` (Acordo) quando o `Setup` do emissor diz `tarifaAcordo: true`, senão `1` (Folheto) — o fluxo atual manda `0`, que não existe na tabela; `produtoAvulso: false`; `cupom: ""`.
- `classificacoes`: `[1]` (todos) por padrão. Quando o viajante conta que é gestante, estudante, viagem de negócios ou cruzeiro, o modelo informa o `motivo` (parâmetro opcional, enum `lazer`, `estudo`, `negocios`, `gestante`, `cruzeiro`) e a ferramenta usa a classificação correspondente, porque o produto muda.
- Guarda o resultado em tabela nova `autonomia_cotacoes_de_viagem` (`account_id`, `conversation_id`, `autonomia_agent_id`, `id_cotacao` da Universal, `pedido` jsonb, `planos` jsonb, `proposta` jsonb, timestamps).
- `planos` guarda, por plano: `codigo` (curto, nosso), `id_produto`, `id_produto_acordo`, nome, descrição adicional, preço em R$, valor na moeda, moeda, câmbio, máximo de parcelas, e as coberturas principais (despesas médicas e hospitalares, bagagem, cancelamento — escolhidas por `idBeneficio`, não por texto).
- Devolve ao modelo só o resumo: `codigo`, nome, preço em R$, parcelas e coberturas principais. **Nunca** `comissao`, `comissaoIntermediario`, `markup`, `rank`, `quotationPorcentagem*`, `valorSemDesconto*`.
- Filtro dos planos: o fluxo atual mostra só planos com despesas médicas e hospitalares; mantemos, pelo `idBeneficio`.
- Gera o **PDF comparativo** (6.4.2) e o entrega na conversa junto da resposta.

### 6.4.1 Ferramenta `detalhes_da_cotacao` — a IA sabe tudo, o viajante recebe o que serve à venda

O viajante pergunta muito sobre coberturas. Na conta piloto, em 60 dias, os temas mais frequentes foram: valor de cada cobertura (11 conversas; 4 reclamaram que o PDF não mostrava), quem é a seguradora (10), "achei caro" (6), pagamento e parcelas (6), preço por pessoa ou total (4), reembolso ou pagamento direto à clínica (3), odontológico, esporte, emergência em português, sala VIP. O fluxo atual resolve parte disso com a ferramenta "Cotação Detalhes", que baixa o PDF e extrai o texto.

Aqui, sem chamada nova à Universal e sem ler PDF: a ferramenta lê a cotação guardada e devolve, para um plano ou para comparar planos, **todas** as coberturas com valor e moeda, a descrição completa de cada uma (`descricaoCompleta`), limites de idade, regra de cancelamento, máximo de parcelas, preço por pessoa e total, câmbio. Continua sem comissão, markup e ranking. O que a cotação não diz (reembolso, rede, odontológico, esporte) vem da base de conhecimento (6.7).

A instrução separa: a IA consulta tudo; ao viajante mostra o necessário para decidir, e responde o resto quando ele pergunta.

### 6.4.2 PDF comparativo

- Gerado na plataforma com Prawn (já no Gemfile, usado na exportação do painel de desempenho), visual atual, com o nome da corretora.
- Conteúdo: destino, datas, viajantes por idade; por plano, preço total, preço por pessoa, parcelas e **todas as coberturas com valor**, em tabela lado a lado; data da cotação e validade.
- Entregue como anexo na conversa, junto da resposta (o mecanismo de entrega de arquivo pelas ferramentas já existe; o construtor escolhe o encaixe).

### 6.5 Ferramenta `gerar_proposta_seguro_viagem`

**Na hora da proposta, aí sim, pede os dados** (nome completo, CPF, nascimento de cada viajante; e-mail, telefone, CEP, número e complemento do titular; contato de emergência). A instrução manda ler o histórico antes e nunca pedir de novo o que já veio.

Parâmetros:
- `codigo_do_plano`: um dos `codigo` da **última cotação desta conversa**. O plano, o preço e o câmbio saem da tabela, nunca do modelo. Código que não existe → recusa.
- `titular`: `{ nome_completo, cpf, data_nascimento, email, telefone, cep, numero, complemento }`. Rua, bairro, cidade e UF vêm do CEP (consulta pronta), não do modelo.
- `demais_viajantes`: array de `{ nome_completo, cpf, data_nascimento }`. A quantidade tem de bater com a cotação.
- Com o nascimento real, a ferramenta confere se a idade na saída ainda cai na mesma faixa de preço da cotação. Se mudou, recusa com "recotar": o modelo cota de novo com as idades certas e avisa o viajante se o preço mudou, antes de gerar a proposta.
- `contato_de_emergencia`: `{ nome, telefone }`.

Comportamento:
- `escreve? = true`. Idempotente por `(cotação, plano, CPFs)`: repetir a chamada não gera segunda proposta.
- Monta `DadosBasicos`, `DadosTitular`, `DadosIntegrantes`, `DadosProdutos`, `DadosPagamento` como o fluxo atual, corrigindo: datas reais da cotação, `TipoTarifa` igual ao da cotação, nascimento informado (não 1º de janeiro).
- **Pagamento por link, nunca cartão no chat.** A coleção documenta faturado (`1`), cartão (`2`, exige número e código do cartão no pedido) e boleto (`3`). O fluxo de proposta mais novo usa `FormaPagamento: 8`, não documentado, e a resposta traz em `urlVoucher` um endereço de `pagamento.universal-assistance.com`; o fluxo o transforma em `https://pagamento.universal-assistance.com/?IdCarrinho=<codigoCarrinho>`. Usamos o `8` e montamos o link a partir do `codigoCarrinho` (com o parser de URL, sem regex). O primeiro teste real em produção confirma; se o `8` não servir, a decisão volta ao Rodrigo (boleto ou faturado).
- Resposta de `/v1/Compras`: `{ codigoCarrinho, codigoCotacao, urlVoucher, valorBrutoBrl }`; erro `400` com `message` (ex.: "Valor enviado no cartão é incompatível com a tarifa do produto"). Guarda em `proposta` e devolve ao modelo o link de pagamento e o número do carrinho.
- Depois do pagamento (fora deste escopo, candidato a próxima entrega): `GET /v1/StatusPagamento/:idCarrinho` diz se pagou, e `GET /v1/Bilhete/:idCarrinho` / `GET /v1/Voucher/imprimir/:idCarrinho` dão o bilhete e o voucher para o agente enviar.

### 6.6 Erros

- `acesso_recusado`: marca o acesso como `recusado`, posta **nota privada** para a equipe (padrão `Insurance::NotaNaHora`) e o viajante ouve uma frase neutra de que alguém da equipe vai continuar; a conversa passa para a equipe pela Atribuição.
- `pedido_invalido`: recusa com o campo, para o modelo corrigir com o viajante.
- `indisponivel`: frase neutra ao viajante e nota privada; sem repetir em laço.

### 6.7 Base de conhecimento

- O retriever é sempre por agente; não existe base de sistema compartilhada.
- Material versionado no repo (texto extraído dos PDFs oficiais da Universal: condições gerais vigentes, folheto comparativo de produtos). Ao contratar, os trechos são semeados no agente, como o Guia faz por conta; nova versão do material re-semeia as cópias.
- Custo de embedding por contratação: estimado em centavos de dólar (a medir na etapa 1).

### 6.8 Telas

Mockup em prints antes do código (regra da casa), com diretor de arte. Fluxo:
1. Área de Agentes → cartão "Seguro Viagem Universal" em "Prontos para contratar".
2. Página do modelo: o que ele faz, o que precisa, botão **Contratar**.
3. Três campos (nome do agente, nome da corretora, descrição da corretora) → cria o agente parado.
4. Login e senha da Universal → confere na hora → "Acesso conferido".
5. Escolher a caixa (tela que já existe na página do agente) → liga.

Sem `<select>` nativo; só Tailwind; textos em en e pt_BR.

### 6.9 Liberação

- Flag de conta nova para o cartão. Como flag nova só nasce ligada em conta nova, a Orquestração liga nas contas existentes depois do deploy.
- Piloto (D12) antes de ligar em todas.

## 7. Validação

- Specs na CI (sem rspec local): instrução mantida recusa todos os escritores; render com variáveis; cliente da Universal com respostas gravadas (sem dado real); as duas ferramentas (validação, filtro de campos internos, proposta lendo a cotação guardada, idempotência, erros); acesso cifrado e nunca devolvido.
- Vitest nas telas novas; lint.
- Jornada paga na conta piloto, teto US$ 10: viajante "QI 60" do primeiro "oi" ao link de pagamento, com cotação e proposta reais na Universal.
- Revisor `agentes-ia-refactor-reviewer`; testador depois do deploy.

## 8. Qualidade da conversa — paridade com os fluxos atuais

Referência: a cadeia viva do fluxo externo (entrada "formatInputMessage - Unificado - Fast" com debounce embutido → agente → saída "formatOutputMessage Chatwoot - Unificado - fast"), lida nas execuções de 23–24/11. O "Smart Debounce" com autotune **não** está no caminho vivo; a entrada viva só usa mínimo e máximo da política.

| Item | Fluxo externo (referência) | Plataforma hoje | O que fazer |
|---|---|---|---|
| Quem vence a rajada | A última mensagem vence | Igual | — |
| Quanto espera | `max(1 s, fim previsto da fala anterior − agora)`, teto 180 s | Fixo 6 s após a última mensagem, sem teto | **P1** esperar a fala anterior acabar, mínimo curto |
| Agente ocupado | Fila: confere de 2 em 2 s até espera + 150 s | Só com Fase 2 descarta a resposta velha | **P2** fila atrás do turno em curso |
| Juntar a rajada | Todas as mensagens desde a última resposta viram uma pergunta | Só a última; as outras pelo histórico | **P1** juntar todas |
| Corte da entrega | Depois do 1º pedaço, o resto sai mesmo com mensagem nova | Mensagem nova aborta os pedaços restantes | **P3** igualar ao externo |
| Quebra em balões | 60 / 260 / 420, até 8 pedaços; regras de sentido por regex | 60 / 260 / 420, até 5; lista inteira; URL sozinha | — **mantém a da plataforma** (Rodrigo, 24/11: "os agentes da plataforma já fazem isso"). Na conta piloto, 8–10 balões por cotação foi reclamação; a instrução pede cotação em até 3 balões, pergunta por último |
| Cadência: fórmula | 24–38 ms/caractere + pausas de pontuação + extra; 0,9–15 s; total 90 s | **Igual** | — |
| Pausa pós-envio | 1–3 s | Não tem | **P5** |
| "Digitando" WhatsApp oficial | Espera 1/5 do tempo; cheia a cada 25 s (Meta apaga em ~25 s) | Espera cheia a cada pedaço | **P5** |
| "Digitando" WAHA | `startTyping` a cada pedaço | Provavelmente não tem (não confirmado) | **P5** |
| Data e hora | "Agora:" no fim do turno | **Não recebe** | **P6** `$dataDeHoje` + hora, fuso da conta |
| Áudio do cliente | Transcreve | Transcreve | — |
| Imagem | Texto extraído por IA | Imagem vai direto ao modelo (melhor) | — |
| PDF | OCR + organização | Só texto, sem OCR | Fora (pouco uso em viagem) |
| Planilha, doc | Viram texto | Não | Fora |
| Mensagem citada | Busca a original e explica | Trecho de 160 caracteres | — |
| Responder em áudio | Quando o cliente manda áudio e não há link | Existe, desligado por padrão | **P7** ligado neste agente |
| Resposta superada com ferramenta | Fica na memória como "não enviada" | Descartada | — (a cotação fica guardada na tabela) |

Como entra, sem mudar os outros agentes: P1–P3 e P5–P7 viram **opções por agente** no `config` (o padrão de `debounce_seconds` e `humanize_delivery`), ligadas pelo `Contratar` neste agente e desligadas nos demais. Nenhum `if` por tipo de agente; independe da Fase 2 da conta (o agente vai para todas as contas).

## 9. Etapas

1. Instrução (≤ 50 mil caracteres) e base: de/para contra a instrução de referência; revisão do Rodrigo.
2. Mockup em prints + diretor de arte; aprovação do Rodrigo.
3. Um PR: agente contratado, acesso à Universal, cliente, 2 ferramentas, tabela de cotações, paridade da conversa, telas. Revisor e CI.
4. Teste pago na conta piloto; pedido de merge e deploy pela gestora da fila; testador; limpeza.

## 10. Chamadas minhas (para o Rodrigo conferir)

- `agent_type: 'sdr'` + marca `config['contratado']`, em vez de um `agent_type` novo: um tipo novo teria de ser tratado em ~15 pontos que hoje só conhecem `insurance_quote`.
- Model próprio para o acesso, em vez de `Insurance::Connection` (risco de a Lia ler a conexão da Universal).
- Cotação síncrona com tabela própria, em vez de ferramenta assíncrona com `ToolRun`.
- Ferramentas fixas: o corretor não tira nem põe ferramenta neste agente.
- Conferir o acesso com `GET /v1/Emissor/Setup` ao salvar (sem cotar).
- Base semeada por agente na contratação, como o Guia.

## 11. Respostas à revisão de construtor (24/11)

| Pergunta | Resposta |
|---|---|
| Cartão em todas as contas ou só seguros? Convive com o modelo de ramo `seguro_viagem`? | Todas as contas (D1). Seção nova "Prontos para contratar" na escolha de agente, separada dos modelos de ramo. O modelo de ramo continua: ele monta um agente genérico que não cota; este vende a Universal. |
| Paridade da conversa no mesmo PR? Quem vence com Fase 2? | **PR próprio, antes do PR do agente**: menor, revisado e testado isolado. As opções valem por agente; com a opção ligada, ela vence o comportamento da Fase 2 para aquele agente. Sem a opção, nada muda. |
| Onde está a instrução de referência (D9)? | Arquivo local, fora do repositório (repo público). Entra só como insumo da etapa 1; o de/para mostra o que foi aproveitado. |
| Acesso à Universal por conta ou por agente? | **Por agente** (D3: "na área dele"): único por `autonomia_agent_id`. Uma conta com duas corretoras contrata duas cópias, cada uma com seu login. |
| Setup ou cotação mínima? | Setup (seção 6.2). |
| Corretor mexe na base? | Não. A base deste agente é só a nossa; a tela e a API de material ficam só leitura para ele. |
| Nome e descrição da corretora editáveis depois? | Sim, pela mesma tela dos 3 campos (endpoint próprio que regrava `config['contratado']`, menos o `modelo`). Não re-semeia a base, que não depende deles. |
| Flag nasce ligada? | Declarada `enabled: true` (regra da casa, vale para conta nova). Nas contas existentes, a Orquestração liga só depois do piloto aprovado. |
| Login da Universal do teste pago | Pergunta ao Rodrigo. |
