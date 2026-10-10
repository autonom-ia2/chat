# Base de clientes — PRD

Épico: #1240. Origem: a conversa de 03/10/2026 sobre a tela "Dados" e as decisões do
Rodrigo de 10/10/2026.

## 1. Problema

Todo cliente novo pede para subir a própria **base de clientes**: quem já compra dele ou já
falou com ele. Sem isso, a plataforma começa vazia. O agente de IA não conhece ninguém, o
CRM não tem histórico e a campanha de reativação não tem para quem ir.

Hoje não temos uma resposta de produto para esse pedido, nem uma referência do que o
cliente costuma trazer.

## 2. O que já existe

| | Onde | Serve para a base? |
|---|---|---|
| **Configurações → Dados** (do Chatwoot) | `settings/data/`, feature da conta `data_import` (desligada por padrão em `config/features.yml`) | Não. A tela importa só de Intercom e Freshdesk, e a exportação diz "em breve". O CSV antigo do Chatwoot (`ContactsController#import`) continua sendo o usado quando a #1006 está desligada. O Chatwoot está mudando essas tabelas na branch `codex/cw-8215-contact-data-parity`. |
| **Importar contatos** (nossa, #1006) | menu ⋮ de Contatos; `ContactImports::*` sobre `CampaignImports::*`; contrato em `docs/campaigns/publicos/contact-imports-1006.md` | **Sim, é a base desta F1.** Está em produção desde 06/10 (#1038). |
| Opt-out por contato (#737) | `contacts.opted_out_at`, `opt_out_source` | Sim, para consentimento. |
| Tipo do contato (Chatwoot) | `contacts.contact_type`: `visitor`, `lead`, `customer` | Sim, para "lead × cliente". **A importação de hoje não preenche** (ver §5). |

O que a #1006 já faz, e que esta entrega **não refaz**:

- lê CSV e XLSX (`SpreadsheetReader`); o Jev acha nome, celular, e-mail e empresa, vendo só
  cabeçalhos, contagens e formato mascarado; sem o Jev, a pessoa escolhe as colunas na tela;
- confere linha a linha, rejeita celular ou e-mail repetidos dentro do arquivo e oferece
  baixar as linhas rejeitadas, com o motivo e os dados mascarados;
- reconhece contato que já existe (celular com ou sem o 9, depois e-mail sem diferença de
  caixa), nunca duplica e só preenche o que falta;
- transforma colunas extras em atributos do contato, convertendo valores tipados (moeda,
  data, lista…);
- cria ou reaproveita empresas e liga o contato a elas;
- mostra uma prévia antes de gravar ("N já eram seus contatos · M novos") e grava em
  segundo plano, com os eventos de contato desligados durante a carga;
- guarda, por linha, o `contact_id`, se o contato já existia (`was_existing_contact`) e o
  resultado da empresa (`campaign_import_rows`);
- só deixa importar quem pode importar contatos no Chatwoot (`ContactPolicy#import?`:
  administrador ou função com `contact_manage`).

O que ela **não** tem: desfazer. Uma importação de contatos só pode ser apagada enquanto é
rascunho (`CampaignImport#deletable?`). O `undo_labels` de Públicos só tira etiquetas e não
alcança importações de contatos.

## 3. Decisões

| # | Decisão | Por quê |
|---|---|---|
| D1 | **Telas nossas dentro de Contatos** (e de CRM, quando chegar o kanban). A "Dados" do Chatwoot fica escondida, no molde do #219. | Ficar fora do código que o Chatwoot está mudando. |
| D2 | **A F1 é só a base de clientes.** O kanban vem na F2. | O kanban depende da base estar certa: o card precisa de um contato. |
| D3 | **Evoluir a #1006, sem motor novo.** Fica descartado o `Autonomia::Data::*` com tabelas `autonomia_data_*` do plano de 03/10. | Ele duplicaria leitura, deduplicação e empresas, que já estão em produção. |
| D4 | **Quem interpreta a planilha é o modelo**, nunca uma lista de palavras ou regex. | Regra do Rodrigo de 20/09/2026. |

## 4. Fases

| Fase | O quê | Código? |
|---|---|---|
| **F0** | Ver arquivos reais e escrever a ficha da base de clientes | Não |
| **F1** | Base de clientes sobre a #1006 | Sim |
| F2 | Importação do kanban: cards e ligação das etapas dele às nossas | Épico próprio |
| F3 | Conectores (Kommo, RD, Pipedrive) e histórico do WhatsApp | Épico próprio |
| F4 | Exportação e LGPD | Épico próprio |

### F0 — pesquisa com arquivos reais

Pedir a 5 clientes o arquivo que eles querem subir. Nenhum dado pessoal sai da conta do
cliente: o arquivo é anonimizado antes, ou a análise é feita só sobre os cabeçalhos e o
formato.

Saídas:

1. **Ficha mínima** da base de clientes: os campos que se repetem nos arquivos.
2. **Casos difíceis**: duplicados dentro do arquivo, telefone fora do padrão, várias pessoas
   por empresa, coluna de status ("ativo", "cancelado"), coluna de consentimento.
3. Resposta às perguntas da §6.

A F1 só começa depois da F0. Sem a F0, a ficha vira chute.

### F1 — base de clientes

O que entra, em cima da #1006:

1. **Entrada própria.** "Base de clientes" em Contatos, separada de Campanhas, e a tela
   "Dados" do Chatwoot escondida (D1).
2. **Flag própria, por conta.** Hoje `ContactImports::Config.enabled?` exige as variáveis de
   ambiente `CAMPAIGN_JOURNEY_ENABLED` e `CAMPAIGN_IMPORT_ENABLED`, que valem para a instalação
   inteira. Assim não dá para ligar a base de clientes só na conta piloto. A F1 troca isso por
   uma feature da conta, sem depender de Campanhas.
3. **Tipo do contato.** A planilha pode dizer quem é cliente e quem é lead. O modelo propõe
   qual coluna diz isso e como os valores dela se traduzem, e grava em `contact_type`. Sem
   uma coluna dessas, a importação pergunta uma vez: "todos aqui são clientes?". Nenhum
   contato importado fica como `visitor`. Contato que já existia não perde o tipo que tem.
4. **Consentimento.** Se a planilha disser quem não quer receber mensagem, a importação grava
   `opted_out_at`. Para isso precisa de uma origem nova em `ContactOptOut::OPT_OUT_SOURCES`
   (hoje só `prospecting`, `email_unsubscribe` e `manual`) e do lugar dela na precedência da
   fusão de contatos (`ContactMergeAction`). A importação **nunca remove** um opt-out que já
   existe.
5. **Pergunta quando a coluna é ambígua.** Quando o modelo não tiver certeza do que é uma
   coluna, a tela pergunta em linguagem simples ("'Valor' é o valor do negócio ou o total já
   comprado?") em vez de chutar. A mesma regra de privacidade da #1006 continua valendo: o
   modelo vê cabeçalho e formato mascarado, nunca o valor.
6. **Prévia com exemplos.** Além das contagens de hoje, a prévia mostra alguns exemplos de
   como a linha vai ficar no contato (com os dados mascarados).
7. **Desfazer o lote.** Desfaz uma importação inteira: apaga os contatos criados por ela e
   devolve aos contatos que já existiam o que ela preencheu (campos, atributos, tipo,
   empresa). Hoje não existe desfazer para importação de contatos; a §5 explica o que falta.
8. **Quem pode.** Mantém a regra de hoje: administrador ou função com `contact_manage`.

Fica para depois da F1: classificar os contatos com IA depois de importar, criar cards no
funil e sugerir campanha de reativação. Esses passos dependem de a base estar certa e serão
decididos com o resultado do piloto.

**Pronto quando:** a F1 está em produção, atrás da flag, e o Rodrigo aceitou o resultado
numa conta piloto com um arquivo real da F0.

## 5. Riscos e limites conhecidos

- **Contato importado pode sumir da lista (achado nesta revisão).** O `Importer` cria o
  contato só com nome, celular e e-mail, então ele nasce `visitor`. Com o CRM novo
  (`crm_v2`) ligado, `Contact.resolved_contacts` mostra só `lead` e `customer`, e o contato
  importado não aparece em Contatos. Isso já vale para a #1006 em produção e precisa ser
  conferido antes da F1, nas contas que têm `crm_v2`.
- **Desfazer contato que já existia.** `campaign_import_rows` guarda qual contato a linha
  tocou, mas não o valor que ele tinha antes, nem a empresa que ganhou, nem os atributos
  que a importação juntou (`ContactImports::CustomAttributes#merge!`). Para devolver tudo
  isso é preciso guardar o que a importação preencheu, na tabela do fork, sem coluna nova
  em tabela do Chatwoot. Empresa criada pela importação e já ligada a outro contato também
  não pode ser apagada no desfazer.
  Contato criado pela importação e que depois recebeu conversa **não** deve ser apagado no
  desfazer. Essa regra precisa estar fechada antes do código.
- **Duplicado dentro do arquivo.** Hoje a segunda linha com o mesmo celular ou e-mail é
  rejeitada. Numa base de clientes, isso pode ser a mesma pessoa com duas compras. A F0 diz
  se isso é comum.
- **Coluna de status pode significar outra coisa.** "Situação = cancelado" pode querer dizer
  ex-cliente, contrato cancelado ou opt-out. Por isso o item 5 da F1 pergunta, em vez de
  deduzir.
- **Dado pessoal guardado sem prazo.** O arquivo original some em 7 dias e os gerados em 30
  (`PurgeExpiredFilesJob`), mas `campaign_import_rows` guarda nome, empresa e colunas extras
  sem mascarar e sem prazo. Com a base inteira do cliente passando por ali, isso entra na
  F4 (LGPD), ou antes se a F0 mostrar dado sensível nas colunas extras.
- **Construção aditiva.** `contact_type`, `opted_out_at` e as tabelas de importação já
  existem, então a F1 não precisa de coluna nova em tabela do Chatwoot.

## 6. Perguntas para a F0

1. Quais campos aparecem em pelo menos 3 dos 5 arquivos?
2. O arquivo separa cliente de lead? Como?
3. Traz consentimento ou opt-out?
4. Quantas linhas costuma ter? Os tetos de hoje (`CampaignImports::Config`) atendem? São
   10 MB por arquivo, 50 mil linhas em CSV e 20 mil em XLSX.
5. Uma pessoa aparece em várias linhas (várias compras, vários contratos)?
6. Vem de qual sistema (planilha feita à mão, Kommo, RD, ERP)? Isso orienta a F3.
