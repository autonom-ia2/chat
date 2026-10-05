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

## Endpoints

Base: `/api/v1/accounts/:account_id/contact_imports`. Resposta: `{ payload: <campaign_import> }`,
o mesmo objeto de `api-992.md` §4 com `flow: "contacts"`.

| Método | Caminho | Corpo | |
|---|---|---|---|
| POST | `/` | multipart `import_file` (.csv/.xlsx), `create_companies` (`"false"` desliga) | `201`; validação em segundo plano |
| GET | `/:id` | | acompanhar o status |
| PATCH | `/:id/columns` | `{ name, phone, email, company }` (índice ou `null`) | mesmas regras de `api-992.md` §5 |
| PATCH | `/:id/companies` | `{ create_companies: true\|false }` | mesmas regras de `api-992.md` §9 |
| POST | `/:id/confirm` | | "Importar": `queued` → `importing` → `completed`; `422 campaign_import.not_ready` fora de `ready_to_confirm` |
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
  "attribute_problems": { "count": 1, "by_attribute": { "Vencimento": 1 }, "rows": [{ "row_number": 9, "attribute": "Vencimento" }] },
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
    (`validation_summary.attribute_problems`). Texto com padrão próprio (legado) é gravado como está.
  - Senão, a chave sai do cabeçalho (`HeaderMapper.normalize_key`: sem acento, minúsculas,
    espaço vira `_`); nunca repete na planilha nem toma um campo padrão do contato (`city`,
    `email`…) — ganha `_2`, `_3`. Cabeçalho sem letra nem número vira `coluna`.
  - Atributos novos são criados como **texto**, com o cabeçalho como nome, quando a importação
    roda (a tela lista quais são novos antes de importar). Sem definição, o valor não apareceria
    na ficha do contato (a tela de contato do Chatwoot só mostra atributos definidos).
  - Valor que o contato já tem **não é sobrescrito**; célula vazia não apaga nada.
- **Não é público:** não cria etiqueta, não aparece em Públicos nem no histórico de bases
  (`CampaignImport.campaign_flows`), e `campaign_journey/campaigns` recusa usá-la (`404`/`not_an_audience`).
