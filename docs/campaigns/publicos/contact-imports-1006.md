# Importar contatos — API e regras (#1006)

Refs #990 (PRD §8.7, aceite Q1–Q4). Tela do fork na entrada "Importar contatos" do menu ⋮ de
Contatos. O importador do Chatwoot (`POST /contacts/import` → `DataImport`) fica intacto e
continua sendo o usado quando a tela nova está desligada.

## Quando vale

| Flag | Efeito |
|---|---|
| `CAMPAIGN_JOURNEY_ENABLED` **e** `CAMPAIGN_IMPORT_ENABLED` ligadas | menu abre a tela nova; endpoints abaixo respondem |
| qualquer uma desligada | menu abre o diálogo antigo do Chatwoot; endpoints → `404 {"error":"contact_import.disabled"}` |
| `CAMPAIGN_JOURNEY_JEV_ENABLED` (+ chave TypeSafe) | Jev acha as colunas; desligado/fora do ar/inseguro → escolha manual na tela, sem alias silencioso |

`CAMPAIGN_IMPORT_ENABLED` entra porque os jobs de validação e gravação são os de Públicos
(`CampaignImports::ValidateJob`/`ImportJob`), que não rodam sem ela.

Permissão: a mesma da importação do Chatwoot (`ContactPolicy#import?` — administrador ou função
com `contact_manage`). Sem ela → `401`. `campaign_manage` sozinho não basta.
A gravação (#2771) pergunta de novo, a quem subiu o arquivo, na hora do job: quem perdeu a
permissão ou saiu da conta antes disso não grava nada, e a importação inteira fica `failed` com
`validation_summary.import_error = "import_not_allowed"`.

A linha gravada (`CampaignImports::ContactRow`, #2771) é a mesma do passo "Para cada item" da
Automação: acha pelo telefone (com ou sem o nono dígito) e depois pelo e-mail; contato que já
existe só ganha o que não tem (nome, telefone e e-mail preenchidos nunca são trocados); a empresa
só vai para quem não tem empresa.

O passo "Para cada item" da Automação (#2771, decisão 15) grava a rodada como importação de
contatos: `options.origem = "automacao"`, com `automacao_id` e `execucao_id`; `user` é quem ligou a
automação; uma linha por item (telefone mascarado e em hash, sem arquivo). Item com telefone que não
é celular do Brasil ou contato recusado fica `invalid` com o motivo (`problem_rows` do `GET /:id`).
Só a rodada inteira fecha (`completed`/`completed_with_failures`). A rodada que sai do passo sem
terminar (pausa por falta de permissão, falha, erro) fica `failed` ("Parou") com o que entrou até ali
e `validation_summary.parou` = motivo; o que não rodou não conta em `failed_contacts_count`. A nova
tentativa na mesma execução (erro passageiro) reabre o mesmo registro.

## Endpoints

Base: `/api/v1/accounts/:account_id/contact_imports`. Resposta: `{ payload: <campaign_import> }`,
o mesmo objeto de `api-992.md` §4 com `flow: "contacts"`.

| Método | Caminho | Corpo | |
|---|---|---|---|
| GET | `/?page=` | | Contatos > Importações (#2771): as importações de contatos da conta, da planilha e da automação, 25 por página, mais novas primeiro; `origin` `file` ou `automation`, `failed_count`, `created_by`; `meta.count` |
| POST | `/` | multipart `import_file` (.csv/.xlsx), `create_companies` (`"false"` desliga) | `201`; validação em segundo plano |
| GET | `/:id` | | acompanhar o status |
| PATCH | `/:id/columns` | `{ name, phone, email, company }` (índice ou `null`) | mesmas regras de `api-992.md` §5 |
| PATCH | `/:id/companies` | `{ create_companies: true\|false }` | mesmas regras de `api-992.md` §9 |
| POST | `/:id/confirm` | | "Importar": `queued` → `importing` → `completed`. Vale também como "tentar de novo" numa importação `failed` cuja gravação quebrou no meio (#2921): continua de onde parou, sem duplicar. `422 campaign_import.not_ready` nos outros casos, inclusive o "Parou" da automação e a `failed` cujo arquivo normalizado já foi apagado |
| GET | `/:id/download` | | CSV das linhas que ficaram de fora (celular e e-mail mascarados) |
| DELETE | `/:id` | | descarta o rascunho antes de importar |

Status, `schema_resolution`, motivos por linha e `validation_summary.companies`: iguais a Públicos.

Campos só desta importação em `validation_summary` (prontos em `ready_to_confirm`):

```json
{
  "existing_contacts": 41,
  "contact_attributes": [
    { "column": "Vencimento", "key": "vencimento", "label": "Vencimento", "existing": true, "type": "date" },
    { "column": "Plano", "key": "plano", "label": "Plano", "existing": false, "type": "text" }
  ],
  "attribute_problems": { "count": 1, "kept": 2, "by_attribute": { "Vencimento": 1 }, "rows": [{ "row_number": 9, "attribute": "Vencimento" }] },
  "contact_attributes_created": 1
}
```

`contact_attributes_created` só aparece depois de importar.

## Regras

- **Leitura (Q1):** o mesmo `CampaignImports::SpreadsheetReader` de Públicos; o pedido ao Jev leva
  só cabeçalhos, contagens e formato mascarado.
- **Contatos:** celular com ou sem o 9, depois e-mail sem diferença de caixa; nunca duplica.
  Contato existente só ganha o que falta (nome, celular, e-mail).
- **Empresas (Q2, C1–C7):** `CampaignImports::CompanyLinker` com o interruptor "Criar e ligar";
  sem a flag `companies` da conta, nada é criado e a tela esconde o bloco.
- **Colunas extras → atributos do contato (Q2):** `ContactImports::AttributeColumns`.
  - Coluna cujo cabeçalho é a chave ou o nome de um atributo de contato existente preenche esse
    atributo. Atributo com tipo (número, moeda, porcentagem, data, lista, caixa de seleção, link) tem
    o valor convertido (`ContactImports::AttributeValue`: "1.234,56", "R$ 10", "15%", "15/03/2026",
    data ISO ou número de dia do Excel, sim/não, opção da lista sem diferença de caixa) e conferido
    pela validação tipada do fork (`Relationships::ValueValidator`). Valor que não serve fica de fora
    só naquela linha; o resto da linha importa. A prévia mostra quantos e em quais linhas, sem o valor
    (`validation_summary.attribute_problems`). Valor que o contato já tem conta como `kept` (mantido, não
    "fora"): o contato fica com o dele. Texto com padrão próprio (legado) é gravado como está.
  - Senão, a chave sai do cabeçalho (`HeaderMapper.normalize_key`: sem acento, minúsculas,
    espaço vira `_`); nunca repete na planilha nem toma um campo padrão do contato (`city`,
    `email`…) — ganha `_2`, `_3`. Cabeçalho sem letra nem número vira `coluna`.
  - Atributos novos são criados como **texto**, com o cabeçalho como nome, quando a importação
    roda (a tela lista quais são novos antes de importar). Sem definição, o valor não apareceria
    na ficha do contato (a tela de contato do Chatwoot só mostra atributos definidos).
  - Valor que o contato já tem **não é sobrescrito**; célula vazia não apaga nada.
- **Não é público:** não cria etiqueta, não aparece em Públicos nem no histórico de bases
  (`CampaignImport.campaign_flows`), e `campaign_journey/campaigns` recusa usá-la (`404`/`not_an_audience`).

## Trazer minha lista (#2896, Fatias 1 e 2)

A tela nova de Relacionamentos ("Trazer minha lista") usa esta mesma importação de contatos, com uma marca:
`options.trazer` (um objeto, vazio quando nasce). Só as importações com a marca mudam de comportamento; a tela
"Importar contatos" e o passo "Para cada item" da Automação seguem como descrito acima. A leitura com a marca é feita
por `ContactImports::Trazer::Validador` (uma subclasse do leitor de contatos, escolhida por
`ContactImports::Validator#perform`).

Com a marca:

- **A leitura não para para perguntar as colunas.** A sugestão do leitor é aceita e a importação segue até
  `ready_to_confirm`. `schema_resolution` fica com `needs_confirmation: false` e mantém `uncertain_targets` e
  `targets[*].confident`: a tela mostra a coluna sugerida sem certeza como `duvidosa`, e a pessoa troca ali.
  Planilha sem coluna de telefone nem de e-mail → `validation_failed` com `missing_contact_column`.
- **DDD em coluna separada não é juntado ao telefone.** O telefone é lido como está na coluna dele; a coluna do DDD
  fica como qualquer outra (vira informação, ou "não guardar"). A junção que existia decidia pelo título qual coluna
  era o DDD, com uma lista de palavras, e saiu: lista de palavras para entender o que a pessoa escreveu falha em
  silêncio quando o título é outro (#3010 trata de apontar a coluna do DDD na tela). O que a pessoa vê hoje: o número
  sem DDD vira problema de telefone (`invalid_brazilian_mobile_number`) e pode ser consertado linha a linha; quando
  nenhuma linha tem contato que dê para usar, a leitura falha (`no_valid_rows`, ou `missing_contact_column` sem coluna
  de telefone nem de e-mail) e a tela pede o DDD junto do número, na mesma coluna. A linha com e-mail bom e telefone
  que não dá para ler (sem DDD, fixo, dígito faltando) entra só com o e-mail, pela regra de leitura que Públicos e
  Importar contatos já têm (`CampaignImports::AudienceRowContacts`); a leitura conta quantas são
  (`validation_summary.sem_telefone`, `resumo.semTelefone` na tela, só o número) e a Conferir avisa, sem travar o
  "Trazer". A planilha corrigida, enviada de novo, acha a pessoa pelo e-mail e completa o telefone
  (`CampaignImports::ContactRow`, `CampaignImports::ContactBlankFields`).
- **A mesma pessoa em várias linhas vira uma só** (`ContactImports::Trazer::MesmaPessoa`): mesmo telefone (com ou sem
  o nono dígito) ou mesmo e-mail. Sem conflito, a primeira linha é completada com o que só a outra tinha (os campos
  da linha e as células que a conferência usa: se ela virar problema, o conserto leva o e-mail e a empresa que vieram
  da outra) e a outra sai da contagem (`validation_summary.mesma_pessoa`, `resumo.juntadas` na tela). Com conflito (nome, telefone,
  e-mail, empresa ou qualquer outra coluna guardada, preenchidos e diferentes nas duas) a segunda vira problema
  `duplicada` e a pessoa escolhe com qual fica. As outras colunas contam porque juntar ficaria com o valor da
  primeira e o da outra sumiria sem ninguém ver (o "Sim" de quem é cliente, a cidade, o telefone da empresa, uma
  informação); a coluna que só uma das linhas preencheu completa a outra, sem conflito. Nome igual não junta ninguém.
- **Linha sem nome é problema** (`blank_name`) quando a planilha tem coluna de nome: a pessoa escreve o nome ou deixa
  a linha de fora.
- **Coluna `nao_guardar` não deixa valor em lugar nenhum.** A leitura não põe o valor dela em
  `campaign_import_rows.extra_values` nem a conta em `validation_summary` (`contact_attributes`,
  `attribute_problems`); a gravação não escreve o valor no contato nem cria o atributo. Quando a pessoa marca a coluna
  depois da leitura, a chave é apagada de `extra_values` de todas as linhas da importação na mesma hora (o
  `validation_summary` só se acerta na próxima leitura). A regra é uma só:
  `Relacionamentos::Trazer::Colunas.chaves_que_nao_guardam`.
- **Destinos que não são informação** (`ContactImports::Trazer::DestinosDaLinha`, que o importador chama na gravação
  de cada linha, logo depois das informações da pessoa e dentro do mesmo savepoint; não depende de a linha ter alguma
  coluna além das de contato, então "sim, todas" vale para todo mundo. `ContactImports::CustomAttributes#merge!` não
  muda: só deixa de fora as colunas que têm outro destino): `cidade` vai para a cidade da pessoa
  (`contacts.additional_attributes.city`), `telefone_da_empresa` para a empresa **da linha**
  (`companies.additional_attributes.phone_number`) e `cliente` diz quem vira cliente
  (`Contact#become_customer!`; a resposta "sim, todas" marca todo mundo). Nenhum deles cria atributo. O destino `telefone_da_empresa` só é aceito
  quando a planilha tem coluna de empresa e a conta tem Empresas (`Relacionamentos::Trazer::Colunas#tem_empresa?`),
  contando as colunas como ficariam depois da troca: a própria coluna de empresa não pode virar telefone da empresa.
  O telefone só é gravado quando a gravação ligou a pessoa à empresa da linha (o vinculador de empresas respondeu
  `created` ou `reused`; o importador passa essa resposta a `DestinosDaLinha#aplicar`). Na linha com a célula da empresa vazia, ou de
  uma pessoa que já era de outra empresa (`kept_other`), o telefone da empresa dessa linha não é guardado em lugar
  nenhum: nunca vai para a empresa que o contato já tinha. Se a coluna de empresa deixa de ser empresa, a coluna que
  era telefone da empresa volta a ser informação. Quem já existia é completado, nunca
  sobrescrito: cidade e telefone só entram onde estava vazio, e quem já era cliente fica com a data que tinha.
- **Quem é cliente é a pessoa que diz** (`ContactImports::Trazer::Cliente`). O código não interpreta o que está
  escrito na célula: não há lista de palavras que valem "sim". Com uma coluna no destino `cliente`, a tela pergunta
  "Quais destes querem dizer cliente?" e a pessoa escolhe: toda linha com algo escrito na coluna (modo `preenchidas`)
  ou os valores que ela marcar (modo `valores`). Sem a escolha a coluna não marca ninguém, e a lista não é trazida
  (`422 falta_valores_cliente`). Só uma coluna diz quem é cliente: marcar outra devolve a primeira para informação.
  - **A contagem** (`ContactImports::Trazer::ValoresDeCliente`): os valores da coluna, agrupados e contados, ficam no
    anexo `valores_cliente` da importação. Valores iguais depois de arrumar os espaços (`squish`: sem espaço nas
    pontas e um só entre as palavras; o espaço que não quebra linha, comum no que vem do Excel, é espaço) e ignorar
    maiúscula caem no mesmo grupo (é formato, não interpretação: acento e qualquer palavra a mais fazem outro valor). Vão os 20 mais
    frequentes (no empate, a ordem da planilha) e a soma dos outros; a célula vazia não entra em nada. `linhas` conta
    todas as linhas da planilha, as com problema inclusive. O `valor` mostrado é a forma mais escrita do grupo, já com os espaços arrumados e com no
    máximo 120 caracteres (`TETO_DO_VALOR`; o cortado termina em "…"): é só para a pessoa ler. O grupo e a chave são
    do valor inteiro, então dois valores longos que ficam iguais depois do corte continuam sendo dois itens, com chaves
    diferentes. A leitura da planilha refaz o anexo a cada passada; a
    troca que põe a coluna em `cliente` sem ler a planilha de novo conta na hora, pelas linhas que a leitura já gravou
    (`campaign_import_rows.extra_values`), com o mesmo resultado; a coluna que deixa de ser `cliente` leva o anexo
    junto.
  - **A chave** de um valor é `HMAC-SHA256` do id da importação, do índice da coluna e do valor agrupado (nessa
    ordem, separados por um byte nulo), com um segredo derivado do `secret_key_base`
    (`Rails.application.key_generator`): não dá para voltar dela ao texto nem para refazê-la sem o segredo. Por levar
    a importação e a coluna, o mesmo texto tem outra chave noutra planilha e noutra coluna: nenhuma conta serve de
    dicionário para outra, e a chave de uma coluna não vale em outra (`422 resposta_desconhecida`). A tela mostra o
    texto e devolve só chaves; `options.trazer` guarda só o modo e as chaves.
  - **A escolha acompanha a coluna.** Trocar a coluna que diz quem é cliente, ou mandá-la para outro destino, apaga
    a escolha na mesma escrita (`ContactImports::Trazer::Conferencia#gravar`): a pergunta volta sem resposta. A
    planilha lida de novo mantém a escolha enquanto todos os valores escolhidos ainda estão entre os da coluna; se um
    deles sumiu (ou deixou de estar entre os 20 mostrados), a escolha inteira é apagada pela leitura e a pessoa
    responde de novo. A mudança que faz a leitura falhar e é desfeita devolve a coluna de antes com a contagem e a
    escolha que tinha. O `POST trazer` confere de novo, sob a trava: no modo `valores`, se alguma chave escolhida não
    sai mais dos valores da coluna, recusa com `falta_valores_cliente` em vez de trazer sem marcar ninguém.
- **Nome e descrição da informação.** A coluna que vira informação pode receber o nome e o "para que serve" que a
  pessoa escreveu; o atributo é criado (ou reaproveitado) com esse nome e a descrição vai para
  `custom_attribute_definitions.attribute_description`.

### Onde fica cada dado

| Dado | Onde | Prazo |
|---|---|---|
| Planilha como veio | anexo `original_file` | 7 dias |
| Linhas com problema: nome, telefone, e-mail e empresa como vieram | anexo `linhas_com_problema` (`ContactImports::Trazer::LinhasComProblema`) | 7 dias da criação da importação |
| O que a pessoa consertou, com o valor digitado | anexo `consertos` (`ContactImports::Trazer::Consertos`) | 7 dias da criação da importação |
| Os valores da coluna que diz quem é cliente, contados (até 20 valores, com o texto) | anexo `valores_cliente` (`ContactImports::Trazer::ValoresDeCliente`) | 7 dias da criação da importação |
| Linhas que vão entrar, com telefone e e-mail inteiros | anexo `normalized_csv` (arquivo conferido) | 30 dias |
| Decisões da pessoa na conferência | `options.trazer` (`ContactImports::Trazer::Conferencia`) | com a importação |
| Contagens da leitura | `validation_summary` | com a importação |
| Nome, máscaras e hashes de cada linha | `campaign_import_rows` | com a importação |

**O anexo das linhas com problema** é um arquivo de texto com uma linha da planilha por linha, em JSON, na ordem
dos números: `{"linha": 143, "celulas": {"name", "phone", "email", "company"}, "outra": {"linha": 88, "celulas": {...}}}`
(`outra` só na linha repetida: é a linha da mesma pessoa que ficou aprovada). Só as células dos quatro alvos entram
(como vieram na planilha): nenhuma outra coluna, nem a marcada "não guardar". É regravado inteiro a cada
leitura e apagado quando a leitura recomeça.

**O anexo dos consertos** tem uma linha por linha consertada: o último campo consertado (`campo`), o que a pessoa
digitou por alvo (`valores`), a coluna (índice) de cada alvo consertado na leitura em que o conserto foi feito
(`colunas`), a outra linha de uma repetida que ela escolheu manter (`outra`) e, quando o conserto resolveu a linha
inteira, a linha como vai entrar (`conferida`, com as colunas do arquivo conferido); quando não resolveu, o motivo que
sobrou (`sobrou`). É o único lugar onde o valor digitado existe. Cada conserto regrava só este arquivo, que tem o
tamanho dos consertos e não o da planilha. A leitura da planilha não o apaga: a leitura que falha não perde nada (nem
a que quebra depois de conferir as linhas), e a que dá certo confere cada conserto de novo e mantém os que ainda valem
(`ContactImports::Trazer::ConsertosDaLeitura`). O conserto vale para a coluna em que foi feito: se a leitura nova põe
outra coluna naquele alvo, ele é esquecido e a linha volta como a leitura nova a vê.

**Tamanho e leitura dos dois anexos.** Cada pedido lê cada anexo no máximo uma vez: os leitores
(`LinhasComProblema`, `Consertos`) guardam o que leram e são passados adiante dentro do pedido. O anexo das linhas
com problema é baixado para um arquivo temporário e lido linha a linha, parando quando acha as linhas pedidas; só
"ficar com esta" numa linha repetida o lê inteiro, para achar as outras linhas da mesma pessoa. O dos consertos é
lido inteiro na memória. Pior caso, com o teto de 50 mil linhas e todas com problema: cerca de 10 MB no anexo das
linhas com problema (umas 200 bytes por linha) e cerca de 25 MB no dos consertos se a pessoa consertasse as 50 mil
(umas 500 bytes por linha, e ele é regravado a cada conserto). Na prática o dos consertos tem o tamanho do que a
pessoa consertou à mão. O anexo com um trecho que não dá para ler levanta `ContactImports::Trazer::ArquivoIlegivel`,
só com o nome do arquivo: o erro do leitor de JSON, que cita o trecho, não vai junto.

**Apagar um anexo** (`ContactImports::Trazer::ApagarAnexo`): o anexo sai na hora, dentro da transação, e o arquivo
só é mandado apagar depois que todas as transações abertas terminam (`ActiveRecord.after_all_transactions_commit`).
Nada usa o `purge_later` do anexo, que põe o job na fila na hora: o job roda noutra conexão, e antes do commit ainda
veria o anexo, desistiria em silêncio e deixaria o arquivo no armazenamento sem dono, com telefone, e-mail e nome
inteiros e fora do alcance do prazo. A transação que volta atrás traz o anexo de volta e não apaga nada. Trocar um
anexo por outro (`attach` em cima do que existe) é do Rails: ele destrói o anexo antigo e manda apagar o arquivo dele
depois do commit. A leitura também tira por esse caminho os arquivos do resultado anterior (conferido, erros,
relatório), em vez de apagá-los do armazenamento dentro da transação. A leitura que quebra com um erro lê a
importação de novo do banco antes de registrar a falha, para não agir sobre anexos que a transação desfeita nunca
gravou.

**O arquivo que ainda não chegou.** Entre o commit e o envio dos anexos novos ao armazenamento o anexo existe no banco
e o arquivo ainda não (`ActiveStorage::FileNotFoundError`, tratado na base das rotas): o `GET` responde `lendo` e as
rotas de escrita respondem `422 leitura_nao_pronta`. Isso vale enquanto o anexo mais novo da importação tem menos de
2 minutos. Depois disso o envio falhou e o arquivo não vem mais: o `GET` responde
`200 {"id": N, "situacao": "falhou", "erro": "leitura"}` (a tela manda enviar a planilha de novo) e as escritas seguem
com `422 leitura_nao_pronta`. Nada é gravado na importação por causa disso.

**Prazo dos anexos da conferência** (`linhas_com_problema`, `consertos` e `valores_cliente`). Somem junto com a planilha original, contando da criação da **importação** e não do
anexo (que nasce de novo a cada leitura e a cada conserto): `ContactImports::Trazer::AnexosVencidos`, chamado por
`CampaignImports::PurgeExpiredFilesJob`. Nada deles vai para o log. A importação que está fechando (`confirmed`:
a pessoa mandou trazer e o job de fechamento ainda não rodou) fica de fora: a lista mandada trazer no último dia do
prazo fecha com os consertos, e os anexos somem na passada seguinte ao fechamento.

**Nenhuma rota da tela abre a planilha original nem o arquivo conferido inteiro.** A conferência (o GET e as rotas
de linha) lê só os dois anexos acima; do arquivo conferido só os primeiros 16 KB são lidos, para os exemplos.

**`options.trazer`** só guarda índice de coluna, número de linha, código, a chave (resumo com segredo) dos valores que
querem dizer cliente e o nome que a pessoa deu a uma informação. Nunca valor de célula:

| Chave | Conteúdo |
|---|---|
| `destinos` | índice da coluna → `nao_guardar`, `cidade`, `telefone_da_empresa` ou `cliente` (informação é o padrão e não é gravada) |
| `campos` | índice da coluna → `nome` e `para_que_serve` da informação, sem caractere de controle (quebra de linha e tabulação viram espaço; o resto, o byte nulo inclusive, sai) |
| `respostas` | `clientes`, `telefone`, `coluna_telefone` (índice da coluna a que a pergunta se referia), `valores_cliente` (`{"modo": "preenchidas"}` ou `{"modo": "valores", "chaves": [...]}`) |
| `deixadas` | números das linhas com problema que a pessoa deixou de fora |
| `anterior` | só enquanto uma leitura pedida pela pessoa não termina: a conferência como estava antes da mudança (as chaves acima) e, das colunas, o índice de cada alvo, se era duvidoso, o método da leitura e a escolha manual que havia |
| `aviso` | `mudanca_desfeita`, até a próxima mudança que der certo |
| `fechamentos` | quantas vezes o fechamento da conferência começou (some quando ele termina) |
| `leitura` | o número (UUID) da leitura que está rodando; some quando ela termina |
| `leitura_em` | quando essa leitura começou (só o instante, ISO 8601); some junto com o número |
| `releituras` | quantas vezes a varredura pôs a leitura parada de volta na fila; some quando uma leitura termina |

**A trava da leitura** (`ContactImports::Trazer::Validador`, só para a importação com a marca). A leitura de planilhas
não aguenta duas execuções da mesma importação, nem juntas nem em sequência: a que termina por último apagaria as
linhas e regravaria o estado, até no meio da gravação. Com a marca:

- **Na entrada**, sob a trava da importação, a leitura só começa a partir de `uploaded`, `validating`,
  `needs_column_choice`, `ready_to_confirm` ou `validation_failed`. A partir de `confirmed`, `queued`, `importing`,
  `completed`, `completed_with_failures` ou `failed` ela sai sem tocar em nada. Ao começar, deixa a importação
  `validating` e grava o número dela em `options.trazer.leitura` e o instante em `options.trazer.leitura_em`.
- **No fim**, dentro da transação que grava o resultado (a leitura que deu certo e a que falhou) e antes de apagar
  qualquer coisa, a importação é travada e conferida: se o número não é mais o desta leitura, ou o estado não é mais
  `validating`, outra leitura (ou a varredura) passou na frente e esta é descartada sem tocar em nada. O número, o
  instante e `releituras` saem nessa mesma transação. Desfazer uma mudança (abaixo) passa pela mesma conferência.
- **O que fica fora da trava.** A trava vai do primeiro passo dessa transação até o commit, e toda escrita na
  importação espera por ela. O tipo de cada coluna (`CampaignImports::ColumnTypes`, uma chamada externa) é perguntado
  antes de a transação abrir, e os arquivos do resultado anterior são apagados do armazenamento depois do commit.
  Dentro da trava ficam apagar e gravar as linhas (até 50 mil) e as contas que leem a conta (empresas, atributos,
  contatos que já existem).
- **A troca de coluna e a resposta que leem de novo** já deixam a importação `validating` na mesma trava em que gravam
  a mudança (`CampaignImports::DraftChanges#choose_columns`). Entre o pedido e o começo do job a leitura velha não
  pode ser trazida: o `POST trazer` e o `confirm` antigo respondem `422`.
- **A varredura não tira a vez da leitura viva.** Pôr a leitura de volta na fila troca o número, e a que estava
  rodando se descarta quando termina. Por isso a leitura que começou (`validating` com `leitura_em`) tem 3 prazos
  (45 minutos, contados de `leitura_em`) para terminar; só então volta para a fila. A que nunca começou (`uploaded`,
  ou `validating` sem `leitura_em`: a leitura foi pedida e o job se perdeu) volta depois de 1 prazo (15 minutos).
- **A varredura conta as voltas**: a leitura volta para a fila no máximo 2 vezes; na terceira a importação vira
  `validation_failed` com `file_could_not_be_processed` (a tela mostra `falhou`).

A importação sem a marca não tem nada disso: é lida como sempre.

**Conferência vencida** (`ContactImports::Trazer::Conferencia.vencida?`). A importação com a marca que ainda não foi
trazida (`uploaded`, `validating`, `needs_column_choice`, `validation_failed`, `ready_to_confirm`, ou `failed` porque
o fechamento desistiu) e nasceu há mais de `CampaignImports::Config.original_file_retention` (7 dias, contados da
criação) está vencida. Nesse prazo os anexos da conferência e a planilha somem, mas o arquivo conferido vive 30 dias:
sem esta regra a lista ainda poderia ser trazida, sem os consertos e com contagem diferente da que a tela mostrou.

- `GET /leituras/:id` → `200 {"id": N, "situacao": "vencida"}`, em qualquer estado da leitura.
- Toda escrita (`PATCH respostas`, `PATCH colunas`, as três rotas de linha, `POST trazer` e o
  `POST /contact_imports/:id/confirm` da importação com a marca) → `422 {"error": "conferencia_vencida"}`, sem mudar
  nada.
- No histórico ela não aparece: rascunho nunca entra em `GET /listas`. A lista cujo fechamento desistiu e venceu
  continua lá como `falhou`, com `pode_tentar: false`.
- A lista que já foi trazida não vence.

Com isso `nada_para_trazer` por arquivo conferido apagado deixa de ser alcançável pela tela; o código fica como defesa.

**Mudança que faz a leitura falhar é desfeita** (`ContactImports::Trazer::DesfazerMudanca`). Antes de cada troca de
coluna ou resposta que lê a planilha de novo, a conferência como estava no começo do pedido fica em
`options.trazer.anterior` (só índices, códigos e o nome que a pessoa deu a uma informação). A leitura que dá certo joga
a cópia fora. A que falha com a cópia guardada não chega a virar `validation_failed`: a conferência volta ao que era,
a cópia some, a planilha é lida de novo com as colunas de antes (os consertos continuam valendo, porque são da coluna
em que foram feitos) e `options.trazer.aviso` passa a `mudanca_desfeita`. Quando essa leitura termina, as colunas
voltam a dizer o que diziam antes (quais eram duvidosas, o método, a escolha manual). É uma vez só: se a leitura
refeita também falha, a importação fica `validation_failed` (`falhou`), sem laço. O aviso sai na próxima escrita que
der certo (troca de coluna, resposta, conserto, deixar de fora, voltar atrás ou trazer).

**O arquivo conferido só muda na hora de trazer.** Até lá a linha consertada continua `invalid` no banco e fora do
`normalized_csv`. O `POST trazer` só confere e deixa a importação `confirmed`; o job
`ContactImports::Trazer::FecharConferenciaJob` fecha a conferência sob a trava
(`ContactImports::Trazer::FecharConferencia`). O arquivo conferido e os consertos são baixados antes da trava, para ela
não esperar o armazenamento; sob a trava o job confere de novo que a importação está `confirmed` e que os dois
arquivos são os que baixou (se não são, baixa de novo ali). O arquivo conferido é regravado com as aprovadas mais as
consertadas;
a linha consertada passa a `valid` com nome, hashes e máscaras; a linha aprovada que saiu no lugar de uma repetida
que a pessoa manteve passa a `invalid` com `left_out`; `valid_rows` e `invalid_rows` passam a contar o que entra de
verdade. Na mesma transação a importação passa a `queued`; a gravação de sempre (`CampaignImports::ImportJob`) vai
para a fila logo depois que a transação termina, porque o arquivo conferido regravado só é enviado ao armazenamento
nesse momento (se o processo morrer entre uma coisa e outra, a varredura de importações paradas pega a `queued`). Job
repetido não faz nada: só a importação `confirmed` é fechada. O importador não começa uma importação
`confirmed`, então a gravação nunca passa na frente do fechamento.

**Quem entra é uma conta só** (`ContactImports::Trazer::QuemEntra`): as linhas aprovadas na leitura, mais as
consertadas por inteiro que ainda são problema e que a pessoa não deixou de fora, menos as que saem no lugar de uma
repetida que ela manteve. A linha que sai no lugar de uma repetida não entra nem quando ela mesma tinha sido
consertada, e de um grupo de linhas da mesma pessoa entra uma só: "ficar com esta" deixa de fora as outras repetidas
do grupo, inclusive a que a pessoa tinha escolhido antes. A tela mostra essa conta (`resumo.entram` e `entram` nas
respostas de linha, sempre com `clientes` ao lado: `ContactImports::Trazer::QuemEntra#contas`), o `POST trazer` a usa para saber se há alguém e o fechamento grava exatamente essas linhas.

**O fechamento não fica em laço** (`ContactImports::Trazer::Fechamentos`). Cada tentativa é contada antes de rodar,
numa transação própria (`options.trazer.fechamentos`, só o número): a que derruba o processo também conta. O erro
continua subindo para a fila. Na terceira tentativa que não termina a importação vira `failed` com
`validation_summary.import_error` = `fechamento` (um código, nunca a mensagem do erro) e a tela mostra `falhou` com
`pode_tentar`. "Tentar de novo" (o `POST /contact_imports/:id/confirm` ou o `POST trazer`) zera a contagem e põe o
fechamento na fila outra vez. O fechamento roda inteiro numa transação: o que quebrou não deixa nada pela metade.
Sem de onde ler (o arquivo conferido apagado antes do job, ou o conferido ou os consertos fora do armazenamento) o
fechamento desiste na primeira tentativa, com o mesmo código: a lista não segue para a gravação nem fica esperando.
O mesmo quando o job roda com a importação de planilhas desligada na instalação (`CAMPAIGN_IMPORT_ENABLED`): a lista
vira `failed` com o código, em vez de ficar `confirmed` e a tela mostrar "trazendo" sem fim.

**A rota antiga de "Importar" não pula o fechamento.** O `POST /contact_imports/:id/confirm` de uma importação com a
marca passa sempre por `Relacionamentos::Trazer::Trazer`, com as respostas de sempre (`200` com a importação,
`422 campaign_import.not_ready`). A rota decide pela marca, que não muda, e não pelo estado lido antes da trava: a
leitura que termina entre a busca e a trava não vai para a gravação sem fechamento. O estado é conferido pelo
`Trazer`, sob a trava; a lista que já foi trazida responde `200` sem enfileirar nada. Só a gravação que parou no meio
(`import_resumable?`) continua pelo caminho antigo, direto para o importador: a conferência dela já foi fechada.

**As rotas antigas de colunas e de empresas recusam a importação com a marca.** `PATCH /contact_imports/:id/columns`
e `PATCH /contact_imports/:id/companies` respondem `422` (`campaign_import.column_choice_not_available` e
`campaign_import.companies_choice_not_available`) sem mudar nada: a lista marcada só muda de coluna pela tela dela
(`PATCH leituras/:id/colunas/:indice`), que lê a planilha de novo com as regras da conferência.

**Importação parada.** Se um job se perde (o worker morreu, o deploy caiu no meio), a varredura de importações paradas
(`CampaignImports::StalledImportsJob`, a cada 5 minutos) chama `ContactImports::Trazer::ConferenciasParadas`. A
importação com a marca `options.trazer` parada há mais de `CampaignImports::Config.stalled_import_after` (15 minutos,
contados do `updated_at`) volta para a fila: em `confirmed`, o job de fechamento; em `uploaded` ou `validating`, a
leitura da planilha (`CampaignImports::ValidateJob`), no máximo 2 vezes. A leitura que começou e ainda pode estar
rodando só volta depois de 45 minutos (ver "A trava da leitura"). A importação é
marcada como mexida agora, então a varredura seguinte não enfileira outra vez; se o job se perder de novo, o prazo
seguinte a pega. A leitura da conferência vencida não volta para a fila (a tela já a mostra como `vencida`); a lista
já mandada trazer não vence, e o fechamento dela volta. Uma importação que quebra não
impede as seguintes, e o log leva só o id e a classe do erro. A importação sem a marca nunca é tocada aqui.

**"Não guardar" apaga dentro do pedido.** Mandar uma coluna para `nao_guardar` apaga a chave dela de `extra_values` de
todas as linhas da importação numa atualização só, dentro da requisição (até 50 mil linhas). Fica assim por decisão do
dono: a pessoa vê o valor sumir na hora, e a atualização é uma só, sem carregar as linhas.

**Deixar de fora responde a um problema.** A linha deixada de fora que uma leitura nova (troca de coluna) torna
válida entra na lista e o resumo conta com ela. O conserto que deixou de valer na leitura nova é esquecido e a linha
volta como problema aberto.

### Rotas

Base: `/api/v1/accounts/:account_id/relacionamentos/trazer`. Todas, leituras inclusive, pedem a chave de conta
`relacionamentos_novo` (`404` sem ela), as duas flags de instalação da tabela "Quando vale" (`404` sem elas) e
`ContactPolicy#import?` (`401` sem ela). Só enxergam importações de contatos por arquivo da própria conta e com a
marca: as da Automação, os Públicos, as da tela "Importar contatos" e as de outra conta respondem `404`. A resposta já
vem no formato da tela.

No Guia da Plataforma, toda escrita destas rotas (as nove de `Relacionamentos::Trazer::Trazer::SEM_DESFAZER_DO_GUIA`,
somadas a `Autonomia::Guide::Acoes::SEM_DESFAZER`) pede confirmação da pessoa: o caderno do desfazer do Guia só
enxerga o que passa por callback de model, e a conferência grava com `update_all`, anexo e job.

| Método | Caminho | Corpo | |
|---|---|---|---|
| POST | `/leituras` | multipart `arquivo` (.csv/.xlsx) | `201 {"id", "situacao": "lendo"}`; cria a importação com a marca e põe a leitura na fila. `422 {"error"}`: `arquivo_obrigatorio`, `tipo` (inclusive `.xls`) ou `arquivo_grande` |
| GET | `/leituras/:id?pagina=` | | `vencida` (a conferência passou do prazo; só `id` e `situacao`); `lendo` (não abre arquivo; também enquanto os anexos da leitura ainda não chegaram ao armazenamento); `falhou` com `erro` `vazia`, `sem_contato` ou `leitura`; ou `pronta` (abaixo). Só rascunho com a marca: depois de trazida a leitura responde `404` |
| PATCH | `/leituras/:id/colunas/:indice` | `{ "destino", "nome", "para_que_serve" }` | Destinos: `nome`, `telefone`, `email`, `empresa`, `informacao`, `nao_guardar`, `cidade`, `telefone_da_empresa`, `cliente`. Entrar ou sair de um dos quatro alvos, e voltar de `nao_guardar`, lê a planilha de novo (`lendo`). Troca entre os outros destinos vale na hora e responde a leitura inteira (`pronta`), igual à do `GET` (a troca pode derrubar uma resposta ou apagar o aviso, e a tela fica sabendo sem outro GET); a coluna que vira `cliente` tira o destino da que era `cliente`, e a resposta já traz a pergunta `valores_cliente` com os valores dela; ir para `nao_guardar` apaga o valor da coluna de todas as linhas. `nome` (até 255 caracteres) e `para_que_serve` (até 1000), opcionais, dão nome e descrição à informação. O `:indice` é lido em base dez. `422 {"error"}`: `leitura_nao_pronta`, `coluna_desconhecida`, `destino_desconhecido`, `sem_contato` (tiraria a última coluna de telefone ou e-mail), `sem_empresa` (`telefone_da_empresa` sem coluna de empresa ou sem Empresas na conta, contando as colunas como ficariam depois da troca: a própria coluna de empresa é recusada) ou `{"error": "valor_invalido", "motivo": "muito_longo"}` |
| PATCH | `/leituras/:id/respostas` | `{ "clientes", "coluna_cliente", "telefone", "valores_cliente" }`, só as que a tela tem | `clientes`: `sim_todas`, `ainda_nao` ou `algumas` (com `coluna_cliente`, o índice da coluna que diz quem é). `telefone`: `da_pessoa`, `da_empresa` ou `nao_usar`. `valores_cliente`: `{"modo": "preenchidas"}` ou `{"modo": "valores", "chaves": [...]}`, sozinho ou junto de `clientes`/`coluna_cliente` (vale para a coluna como o pedido a deixa). Responde a leitura inteira (`pronta`) ou `{"id", "situacao": "lendo"}` quando a resposta pede ler a planilha de novo. Mandar a mesma resposta de novo não muda nada. `422 {"error"}`: `leitura_nao_pronta`, `resposta_desconhecida` (também o modo que não existe, `chaves` vazio no modo `valores` e a chave que não é de um valor mostrado para essa coluna desta planilha; no pedido que troca a coluna nenhuma chave vale, porque a pessoa ainda não viu os valores da coluna nova), `coluna_desconhecida`, `pergunta_desconhecida` (não há pergunta de telefone; ou `valores_cliente` sem coluna que diga quem é cliente, ou com "sim, todas"), `sem_contato` ou `sem_empresa` (`da_empresa` sem coluna de empresa ou sem Empresas na conta); a recusa desfaz o pedido inteiro |
| PATCH | `/leituras/:id/linhas/:linha` | `{ "valor" }` ou, na linha repetida, `{ "ficar_com": <número da linha> }` | Conserta a linha. `200 {"problema": {...}, "entram": N, "clientes": N}`: a linha como a tela a mostra agora (`guardado` quando o conserto resolveu a linha, ou `aberto` com o `tipo` e o `motivo` do problema que sobrou nela: a linha sem nome que teve o telefone consertado volta como `nome`) e quantas pessoas entram se a pessoa mandar trazer agora, e quantas delas como cliente (as mesmas contas de `resumo.entram` e `resumo.clientes`). Na repetida, `ficar_com` esta linha deixa de fora as outras repetidas da mesma pessoa. O `valor` perde os caracteres de controle (o byte nulo inclusive) antes de ser conferido e tem até 255 caracteres. `422 {"error"}`: `leitura_nao_pronta`, `linha_desconhecida`, `planilha_apagada` (o anexo das linhas com problema já foi apagado) ou `{"error": "valor_invalido", "motivo"}`, só quando o valor digitado é que não vale (tabela abaixo) |
| POST | `/leituras/:id/linhas/:linha/deixar_de_fora` | | `200 {"problema", "entram", "clientes"}` com `estado` `deixado`. `422`: `leitura_nao_pronta`, `linha_desconhecida` |
| POST | `/leituras/:id/linhas/:linha/reabrir` | | Volta atrás no deixar de fora e em tudo que foi consertado na linha: `200 {"problema", "entram", "clientes"}` com `estado` `aberto` e o problema original. `422`: os mesmos |
| POST | `/leituras/:id/trazer` | | Confere, deixa a importação `confirmed` e põe o fechamento da conferência na fila: `200 {"trazidaId"}`. O segundo clique responde o mesmo e não enfileira outro job. Também serve de "Tentar de novo" para a lista cujo fechamento desistiu. `422 {"error"}`: `leitura_nao_pronta`, `falta_valores_cliente` (uma coluna diz quem é cliente e a pessoa ainda não escolheu quais valores querem dizer cliente, ou escolheu um valor que a coluna não tem mais: nunca se traz adivinhando nem com meia escolha; a rota antiga de confirmar recusa o mesmo caso com `campaign_import.not_ready`) ou `nada_para_trazer` (ninguém para entrar: o arquivo conferido já foi apagado pelo prazo) |
| GET | `/listas` | | as 100 listas trazidas mais recentes (`Relacionamentos::Trazer::Historico::TETO`), a mais nova primeiro: `id`, `arquivo`, `quando` (ISO 8601), `quem`, `total`, `situacao`, `porcentagem`, `pode_tentar`. Rascunho não entra |
| GET | `/listas/:id/andamento` | | `porcentagem`, `situacao`, `total`, `novas`, `completadas`, contados pelas linhas |

"Tentar de novo" continua sendo o `POST /contact_imports/:id/confirm` acima. Toda rota de escrita responde
`422 leitura_nao_pronta` enquanto os anexos da leitura ainda não chegaram ao armazenamento, e
`422 conferencia_vencida` quando a conferência passou do prazo.

**Leitura pronta.** `arquivo`, `valores`, `colunas`, `tem_empresa`, `perguntas`, `respostas`, `resumo`, `exemplos`, `problemas`
(200 por página), `problemas_total`, `pagina`, `por_pagina` e, só quando há o que avisar, `aviso`
(`"aviso": "mudanca_desfeita"`: a última mudança fez a leitura falhar e o servidor a desfez; sem aviso a chave não
vem). `pagina` que não existe (texto, zero, negativa, além da
última) vira a primeira ou a última que existe, e a resposta diz qual foi: quem busca todas as páginas para em
`problemas_total`, não na página vazia.

- `colunas[]`: `indice`, `nome`, `destino`, `duvidosa` e, na informação, `campo` (`nome`, `para_que_serve`).
- `tem_empresa`: `true` quando o destino `telefone_da_empresa` (e a resposta `da_empresa`) pode ser oferecido: a
  planilha tem coluna de empresa e a conta tem Empresas.
- `perguntas[]`: sempre `{"id": "clientes"}`; e `{"id": "telefone", "coluna", "indice"}` quando o leitor sugeriu a
  coluna de telefone sem certeza, ou quando a pergunta já foi respondida e a coluna continua onde a resposta a pôs.
  Se a pessoa manda essa coluna para outro lugar (ou escolhe outra coluna para o telefone), a resposta antiga deixa de
  valer: a pergunta passa a ser sobre o telefone de agora, se ele for duvidoso, ou some. E, quando uma coluna tem o
  destino `cliente` e a resposta de "São clientes?" não é `sim_todas`,
  `{"id": "valores_cliente", "coluna", "indice", "preenchidas", "valores": [{"chave", "valor", "linhas"}], "outros"}`:
  `valores` tem no máximo 20, do mais frequente ao menos, e cada `valor` no máximo 120 caracteres; `outros` é `{"valores", "linhas"}` do que ficou de fora, ou
  `null`; `preenchidas` é quantas linhas têm algo escrito na coluna. Nada vem marcado: o servidor não sugere valor.
- `respostas`: o que a pessoa respondeu e ainda vale (`clientes`, `coluna_cliente` só com `algumas`, `telefone`,
  `valores_cliente` só enquanto a pergunta dela existe).
  `clientes` e `coluna_cliente` acompanham as colunas (`Relacionamentos::Trazer::Perguntas`), porque são elas que
  dizem quem é cliente na gravação: `sim_todas` vale sempre; fora disso, havendo coluna com o destino `cliente` a
  resposta é `algumas` com essa coluna, mesmo que a pessoa a tenha marcado pela tela das colunas (só uma coluna tem
  esse destino); `algumas` sem nenhuma coluna
  `cliente` deixa de valer e a pergunta volta sem resposta. `options.trazer.respostas` guarda o que a pessoa respondeu;
  o que a tela recebe é isto.
- `resumo`: `total`, `novas`, `completadas`, `comProblema`, `juntadas`, `semTelefone`, `entram`, `clientes`. Os seis primeiros são
  os da leitura e não mudam com o que a pessoa conserta. `entram` (inteiro) é quantas pessoas entram se ela mandar
  trazer agora: a mesma conta do `POST trazer` (`ContactImports::Trazer::QuemEntra`), que muda a cada conserto.
  `clientes` (inteiro) é quantas dessas entram como cliente com a resposta de agora: todas com `sim_todas`, as que a
  escolha de `valores_cliente` marca, e 0 sem resposta. É a mesma regra da gravação, aplicada às linhas que entram.
- `exemplos[]`: as três primeiras linhas aprovadas, com `cliente` verdadeiro quando a linha vai virar cliente.
- `problemas[]`: `linha`, `tipo` (`telefone`, `email`, `nome`, `sem_contato`, `duplicada`, `formula`), `nome`, `valor`,
  `estado` (`aberto`, `guardado`, `deixado`). A `duplicada` traz `outraLinha` e `duplicadas` (as duas linhas, com
  `linha`, `telefone`, `email`); a de tipo `nome` traz `contato` (o telefone ou, sem ele, o e-mail, já com o que foi
  consertado). A linha `guardado` tem o `tipo` do que foi consertado por último e traz `corrigido` (o valor como vai
  ser gravado: telefone em E.164, e-mail ou nome) ou, na repetida em que a pessoa ficou com esta linha, `ficar_com`.
  Na repetida, ficar com a outra linha deixa esta `deixado`. A linha em que o conserto valeu mas sobrou outro
  problema continua `aberto`, com o `tipo` do que sobrou.
  - **`motivo`**: toda linha `aberto` diz o que deu errado, com os códigos da tabela abaixo (`blank_phone_number`,
    `invalid_brazilian_mobile_number`, `formula_phone_number`, `blank_email`, `invalid_email`, `blank_name`,
    `formula_detected`, `missing_contact`). A célula de nome, telefone ou e-mail que parece fórmula é do tipo do campo
    dela, com `formula_detected`. Sem motivo conhecido (a `duplicada`) a chave não vem; `guardado` e `deixado` não têm.
  - **Tipo `formula`**: o erro está num campo que a tela não conserta (hoje, a fórmula na empresa). Vem com
    `campo` (`empresa`) e sem `valor`: `{"linha", "tipo": "formula", "campo": "empresa", "nome", "estado", "motivo"}`.
    O `PATCH` com `valor` nessa linha é recusado com `formula_detected`; deixar de fora e voltar atrás funcionam.
  - **O que a tela não conserta vem primeiro** (`Relacionamentos::Trazer::Pendencia`): a linha com fórmula na empresa
    aparece direto como `formula`, tenha ou não outro problema (telefone errado, sem nome). Consertar o resto não a
    faria entrar, então a tela não pede.

**Motivos de `valor_invalido`**, os mesmos códigos da leitura, sempre sobre o valor digitado:

| Tipo da linha | `motivo` |
|---|---|
| `telefone` | `blank_phone_number`, `invalid_brazilian_mobile_number`, `formula_phone_number` |
| `email` | `blank_email`, `invalid_email`, `formula_detected` |
| `nome` | `blank_name`, `formula_detected` |
| `sem_contato` (aceita telefone ou e-mail) | `missing_contact` (vazio), `invalid_brazilian_mobile_number`, `formula_phone_number`, `invalid_email`, `formula_detected` |
| `duplicada` | `linha_desconhecida` (`ficar_com` não é nenhuma das duas linhas) |
| `formula` | `formula_detected`, sempre: a tela não conserta o campo e a linha só pode ficar de fora |
| qualquer | `muito_longo` (mais de 255 caracteres) |

**Valores inteiros.** Telefone e e-mail inteiros só existem na resposta, só para quem passou em `import?`, e só
enquanto o arquivo de onde saem existe. Nada disso é gravado a mais. São dois arquivos, com prazos diferentes:

- **`valores` fala só dos `problemas`.** `problemas[].valor` (e `duplicadas`, `contato`) traz a célula como está na
  planilha, lida do anexo das linhas com problema; só as linhas da página são lidas dele. `corrigido` vem do anexo
  dos consertos. Depois que os dois anexos são apagados (7 dias da criação da importação) a resposta vem com
  `"valores": "mascarados"`: `valor` é a máscara que a linha guarda (`raw_phone_masked`, `email_masked`), `outraLinha`
  vem `null`, `duplicadas` vem vazia, as linhas consertadas voltam a `aberto` e o conserto responde
  `planilha_apagada`. Sem o anexo, a fórmula só é localizada no nome e na empresa, que a linha guarda inteiros; a linha
  que ficou de fora só por fórmula no telefone ou no e-mail aparece como `nome`, sem `motivo`. Leitura sem linha com
  problema responde `inteiros`.
- **`exemplos` não depende de `valores`.** Sai do começo do arquivo conferido (30 dias), lido por registro, e vem
  inteiro enquanto ele existir. Depois que ele também é apagado, `exemplos` vem vazio e o `POST trazer` responde
  `nada_para_trazer`.
- **O nome é a exceção.** `problemas[].nome` sai inteiro com ou sem arquivo, para quem passou em `import?`: a leitura
  de planilhas já guarda o nome de cada linha (`campaign_import_rows.raw_name`), como em Públicos e em Importar
  contatos.

**Situação da lista** (`Relacionamentos::Trazer::Situacao`):

| Importação | Situação |
|---|---|
| `confirmed`, `queued`, `importing` | `trazendo` |
| `completed`, `completed_with_failures` com `undo_status` `pending` ou `failed` | `pronto` |
| idem com `undo_status` `processing` | `desfazendo` |
| idem com `undo_status` `completed` | `desfeito` |
| `failed` com `import_started_at` | `falhou` (`pode_tentar` = `import_resumable?`) |
| `failed` com `validation_summary.import_error` = `fechamento` | `falhou` com `pode_tentar` (falso se a conferência venceu): o fechamento da conferência desistiu |
| o resto (rascunhos, `failed` sem gravação começada) | fora do histórico |

`porcentagem` = linhas `imported` + `import_failed` sobre `valid_rows`; lista que acabou responde 100.
