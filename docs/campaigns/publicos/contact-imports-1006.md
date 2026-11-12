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

## Trazer minha lista (#2896, Fatia 1)

A tela nova de Relacionamentos ("Trazer minha lista") usa esta mesma importação de contatos, com uma marca:
`options.trazer` (um objeto, vazio quando nasce). Só as importações com a marca mudam de comportamento; a tela
"Importar contatos" e o passo "Para cada item" da Automação seguem como descrito acima.

Com a marca:

- **A leitura não para para perguntar as colunas.** A sugestão do leitor é aceita e a importação segue até
  `ready_to_confirm`. `schema_resolution` fica com `needs_confirmation: false` e mantém `uncertain_targets` e
  `targets[*].confident`: a tela mostra a coluna sugerida sem certeza como `duvidosa`, e a pessoa troca ali.
  Planilha sem coluna de telefone nem de e-mail → `validation_failed` com `missing_contact_column`.
- **`options.trazer.destinos`** guarda, pelo índice da coluna, o destino que a pessoa escolheu para uma coluna que
  não é nome, telefone, e-mail nem empresa. Nesta fatia só `nao_guardar` é gravado (o padrão é virar informação da
  pessoa).
- **Coluna `nao_guardar` não deixa valor em lugar nenhum.** A leitura não põe o valor dela em
  `campaign_import_rows.extra_values` nem a conta em `validation_summary` (`contact_attributes`,
  `attribute_problems`); a gravação não escreve o valor no contato nem cria o atributo. Quando a pessoa marca a coluna
  depois da leitura, a chave é apagada de `extra_values` de todas as linhas da importação na mesma hora (o
  `validation_summary` só se acerta na próxima leitura). A regra é uma só:
  `Relacionamentos::Trazer::Colunas.chaves_que_nao_guardam`.
- Em `options` e em `validation_summary` só entram índice de coluna e código: nunca valor de célula.

### Rotas

Base: `/api/v1/accounts/:account_id/relacionamentos/trazer`. Todas, leituras inclusive, pedem a chave de conta
`relacionamentos_novo` (`404` sem ela), as duas flags de instalação da tabela "Quando vale" (`404` sem elas) e
`ContactPolicy#import?` (`401` sem ela). Só enxergam importações de contatos por arquivo da própria conta: as da
Automação, os Públicos e as de outra conta respondem `404`. A resposta já vem no formato da tela.

| Método | Caminho | Corpo | |
|---|---|---|---|
| POST | `/leituras` | multipart `arquivo` (.csv/.xlsx) | `201 {"id", "situacao": "lendo"}`; cria a importação com a marca e põe a leitura na fila. `422 {"error"}`: `arquivo_obrigatorio`, `tipo` (inclusive `.xls`) ou `arquivo_grande` |
| GET | `/leituras/:id?pagina=` | | `lendo` (não abre arquivo); `falhou` com `erro` `vazia`, `sem_contato` ou `leitura`; ou `pronta`: `arquivo`, `valores`, `colunas`, `resumo`, `exemplos`, `problemas` (200 por página), `problemas_total`, `pagina`, `por_pagina`; `perguntas` e `respostas` vazias nesta fatia. `pagina` que não existe (texto, zero, negativa, além da última) vira a primeira ou a última que existe, e a resposta diz qual foi: quem busca todas as páginas para em `problemas_total`, não na página vazia. Só rascunho com a marca: depois de trazida a leitura responde `404` |
| PATCH | `/leituras/:id/colunas/:indice` | `{ "destino" }` | `nome`, `telefone`, `email` ou `empresa`: a coluna entra no alvo (quem estava nele sai), a planilha é lida de novo e a resposta é `lendo`. Coluna que é alvo e vai para `informacao` ou `nao_guardar`: sai do alvo e a planilha é lida de novo (`lendo`). Coluna que não é alvo e vai para `nao_guardar`: vale na hora, o valor dela é apagado de todas as linhas e a resposta é `pronta` com `colunas`. Coluna que volta de `nao_guardar` para `informacao`: a planilha é lida de novo (`lendo`), porque o valor só existe no arquivo. Coluna que já está no destino pedido: `pronta` com `colunas`, sem mudar nada. O `:indice` é lido em base dez. `422 {"error"}`: `leitura_nao_pronta`, `coluna_desconhecida`, `destino_desconhecido` ou `sem_contato` (tiraria a última coluna de telefone ou e-mail) |
| GET | `/listas` | | as 100 listas trazidas mais recentes (`Relacionamentos::Trazer::Historico::TETO`), a mais nova primeiro: `id`, `arquivo`, `quando` (ISO 8601), `quem`, `total`, `situacao`, `porcentagem`, `pode_tentar`. Rascunho não entra |
| GET | `/listas/:id/andamento` | | `porcentagem`, `situacao`, `total`, `novas`, `completadas`, contados pelas linhas |

"Trazer" e "Tentar de novo" continuam sendo o `POST /contact_imports/:id/confirm` acima.

**Valores inteiros.** Telefone e e-mail inteiros só existem na resposta, só para quem passou em `import?`, e só
enquanto o arquivo de onde saem existe. Nada disso é gravado a mais. São dois arquivos, com prazos diferentes:

- **`valores` fala só dos `problemas`.** `problemas[].valor` (e `duplicadas`) traz a célula como está na planilha,
  lida do arquivo original na hora da resposta; só as linhas da página são lidas dele. Depois que o arquivo original é
  apagado (7 dias) a resposta vem com `"valores": "mascarados"`: `valor` é a máscara que a linha guarda
  (`raw_phone_masked`, `email_masked`), `outraLinha` vem `null` e `duplicadas` vem vazia.
- **`exemplos` não depende de `valores`.** São as três primeiras linhas aprovadas do arquivo conferido (30 dias) e
  saem inteiros enquanto ele existir, mesmo com `"valores": "mascarados"`. Depois que o arquivo conferido também é
  apagado, `exemplos` vem vazio: nenhum telefone ou e-mail inteiro sai.
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
| o resto (rascunhos, `failed` sem gravação começada) | fora do histórico |

`porcentagem` = linhas `imported` + `import_failed` sobre `valid_rows`; lista que acabou responde 100.
