# Consulta de produção: Relacionamentos e Base de clientes — versão 2

**Arquivos:** 5 partes, cada uma com sua própria transação `READ ONLY` que termina em `ROLLBACK`. Rode uma por vez, em qualquer ordem.

| Parte | Arquivo | Blocos | Assunto | Teto (blocos × 60 s) |
|---|---|---|---|---|
| 1 | `1-pessoas-canais.sql` | 1 a 15 | Universo e flags, pessoa e telefone, contato x cliente, opt-out, entrada de contatos, canais | 15 min |
| 2 | `2-empresas.sql` | 16 a 21 | Empresas: vínculo, backfill por nome e por domínio do e-mail, tabela `companies` | 6 min |
| 3 | `3-crm-planilhas.sql` | 22 a 37 | CRM (negócio) e importações de planilha | 16 min |
| 4 | `4-etiquetas-atividade-campos.sql` | 38 a 51 | Etiquetas, atividade e campos personalizados | 14 min |
| 5 | `5-mensagens-90-dias.sql` | 52 | `contacts.last_activity_at` contra as mensagens dos últimos 90 dias | 1 min |

O teto é o pior caso teórico. No banco de teste, cada parte levou menos de 1 s.

**Para que serve:** medir, em todas as contas ativas das duas instalações, o que a remontagem de Relacionamentos e a ferramenta Base de clientes precisam saber, inclusive o que dá para trazer para Empresas (recurso novo, sem backfill).

**Versão 1:** um arquivo só, numa transação. Foi reprovada na auditoria da Orquestração e não foi versionada. A numeração dos 52 blocos é a mesma.

**Resultado da medição de 11/10/2026:** [`../DADOS-DE-PRODUCAO.md`](../DADOS-DE-PRODUCAO.md).

---

## 1. O que mudou desde a auditoria da Orquestração

| # | Pedido | O que mudou | Onde |
|---|---|---|---|
| 1 | Bloco 18: tirar a lista de domínios | Nenhum domínio lido do banco sai. O bloco agora conta contatos e empresas só para os domínios de duas listas **escritas na consulta**: provedores públicos que a lista da gem não tem (`hotmail.com.br`, `terra.com.br`…) e erros de digitação (`gmail.com.br`, `hotmail.con`…). O resto vira duas linhas só de contagem: `(outros comuns)` e `(lista da gem)`. O bloco 17 ganhou a coluna `gratis_fora_da_gem` | parte 2, topo e blocos 17-18 |
| 2 | Bloco 26: origem do card só em contagem | A coluna `origem` só mostra `(vazio)`, tipo de canal (`inboxes.channel_type`) e os códigos que o código grava (`contact_request`, `panel`, `public_link`, `invite`, `ai`, `autonomia_prospecting`). Qualquer outro texto vira `(outro)`, só contado | parte 3, bloco 26 |
| 3 | Bloco 39: etiqueta só em contagem | Nenhum título sai. O bloco agrupa as etiquetas pelo número de contas que têm o mesmo título (1, 2, 3 a 9, 10 ou mais) e conta as que têm `@` ou 6+ dígitos | parte 4, bloco 39 |
| 4 | Títulos de coluna (32 a 34 e 37): o guarda do md5 deixa passar a mesma planilha reimportada com uma coluna a mais | Saiu o md5. Agora: `min_contas` = 3, **conta-se a conta, não a planilha** (reimportar na mesma conta, com ou sem coluna a mais, não soma) e só entra título de planilha "boa": pelo menos 2 títulos preenchidos e nenhum com `@` ou 6+ dígitos. Cabeçalho com telefone ou e-mail, ou com um título só, quase sempre é linha de dado, e a planilha inteira fica de fora. O bloco 35 conta o que ficou de fora e por quê | parte 3, blocos 32-35 e 37 |
| 5 | Bloco 46: nome exibido com `min_contas` 3 | `min_contas` passou a 3 em todas as partes | topo de cada parte |
| 6 | Blocos 28 e 48: contar só a conta com valor | A chave só aparece se tem **valor** em 3 ou mais contas; a definição sozinha não conta. Apliquei o mesmo aos blocos 49 e 50 (`additional_attributes`) | partes 3 e 4 |
| 7 | Uma transação só, sem teto total | 5 arquivos, cada um com `BEGIN TRANSACTION READ ONLY` … `ROLLBACK`. A trava de leitura (`ACCESS SHARE`) dura só até o fim da parte. `statement_timeout` caiu de 120 s para 60 s | todas |
| 8 | Bloco 52: arquivo próprio, só contas ativas e janela de tempo | Parte 5 só com ele. Lê mensagens das contas ativas criadas nos últimos 90 dias, pelo índice `index_messages_on_account_created_type` `(account_id, created_at, message_type)` (`db/schema.rb:3318`). As colunas foram refeitas para a janela (seção 4) | parte 5 |
| 9 | Blocos 11, 42 e 37: janela de tempo ou índice | **11:** já tem janela (contatos dos últimos 18 meses); o `EXISTS` usa `index_conversations_on_contact_id` (`db/schema.rb:1814`). **42:** lê as conversas das contas ativas uma vez e agrega por contato. Precisa da última conversa de qualquer data, e não há índice em `conversations.last_activity_at` (`db/schema.rb:1806-1825`), então janela não diminuiria a leitura; o teto é o `statement_timeout`. **37:** o índice `(email_campaign_id, id)`, `idx_recipients_preflight_unchecked`, existe mas é parcial (`db/schema.rb:2837`). O bloco não ordena mais: pega 1 destinatário qualquer por campanha (`LIMIT 1` sobre um índice que começa por `email_campaign_id`, como `index_email_campaign_recipients_on_email_campaign_id`, `db/schema.rb:2841`), porque as chaves de `custom_data` são iguais em todo destinatário da mesma planilha (`recipient_importer.rb:112-113`) | partes 1, 3 e 4 |

Linhas de `db/schema.rb`: do main `785271922d`, o que a Orquestração conferiu. Elas mudam a cada migration (na worktree da pesquisa, `a82d4517a4`, o mesmo índice de `messages` fica na 3399); o que vale é o nome da tabela e do índice, igual nos dois. Os comentários dentro das partes 1, 2 e 5 ainda citam as linhas da worktree.

**Rodada 2 (conferência da versão 2 pela Orquestração).** As partes 1, 2 e 5 foram aprovadas como estavam e não mudaram. Nas partes 3 e 4:

| Pedido | O que mudou | Onde |
|---|---|---|
| Bloco 37: faltava o portão de "linha boa" | Campanha de e-mail só é "boa" com **pelo menos 2 chaves** e nenhuma com `@` ou 6+ dígitos. Campanha com uma coluna extra só fica de fora | parte 3, bloco 37 |
| Bloco 46: visibilidade vinha das definições, que a importação #1006 cria a partir dos cabeçalhos | A chave e o nome exibido só aparecem com **valor** em 3 ou mais contas que a definem (contato, empresa e card). O modelo conversa saiu da lista (não é dado de relacionamento e obrigaria a abrir o `jsonb` de todas as conversas); as definições de conversa seguem contadas nos blocos 44 e 45 | parte 4, bloco 46 |
| Opcional: `channel_type` em lista branca | No bloco 26, o canal só sai se estiver na lista fechada das 12 classes de `app/models/channel/*.rb`; o bloco não lê mais `inboxes`. Nos blocos 13 e 14 (parte 1, já aprovada e em execução) o `channel_type` continua vindo de `inboxes`: é o tipo polimórfico que o Rails grava, nunca o nome da caixa | parte 3, bloco 26 |
| Opcional: linhas do `schema.rb` no LEIA-ME | Citadas pelo nome do índice e pela linha no main `785271922d` | este arquivo |

Outros blocos que leem `conversations` inteiro das contas ativas, como o 42: 14 e 43 (parte 1 e parte 4). Os blocos 47 a 51 abrem o `jsonb` de todos os contatos das contas ativas.

---

## 2. Como rodar

1. **Fora de deploy**, depois de conferir no `pg_stat_activity` que não há DDL em andamento.
2. **Uma parte por vez**, nas duas instalações (Hub2You e Autonom.ia). Guarde as saídas separadas: o `account_id` é de cada banco.
3. Precisa ser **psql**: as partes usam `\echo`, `\set` e as variáveis `:ativas`, `:min_contas` (e, na parte 2, `:min_contas_dominio` e as três listas de e-mail). Cada parte é completa sozinha: não inclui outro arquivo.
   ```sh
   psql "<conexão de leitura>" -X -v ON_ERROR_STOP=1 -f 1-pessoas-canais.sql > saida-1-<instalacao>.txt 2>&1
   ```
   Por SSM + `docker exec`, mande a parte pela entrada padrão e siga o runbook de produção do projeto. Nunca use `rails runner`.
   ```sh
   docker exec -i <container-do-postgres> psql -U <usuario> -d <banco> -X -v ON_ERROR_STOP=1 < 1-pessoas-canais.sql > saida-1-<instalacao>.txt 2>&1
   ```
4. **Se um bloco falhar** (passou de 60 s ou esperou mais de 2 s por trava): o psql para ali e a transação da parte é desfeita. O que já saiu vale. Para seguir, rode a parte de novo sem o bloco que falhou, apagando da linha `\echo '== N.` até o `;` daquele SELECT.
5. **Tamanho da saída:** com N contas ativas, perto de 1.000 a 3.000 linhas somando as 5 partes. Linhas por bloco na seção 5.

---

## 3. Garantia de que nenhum dado de pessoa sai

### 3.1 Somente leitura
- Cada parte começa com `BEGIN TRANSACTION READ ONLY`, `SET LOCAL statement_timeout = '60s'` e `SET LOCAL lock_timeout = '2s'`, e termina com `ROLLBACK`.
- Fora dos comentários, nenhuma parte tem `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `GRANT`, `COPY`, `VACUUM` nem `LOCK`. Conferido por busca, parte por parte.
- O psql recebe só `\echo`, `\set`, `\pset pager off` e `\timing on`. Não há `\o`, `\!`, `\copy`, `\w`, `\gset` nem `\cd`.

### 3.2 Somente totais
Nenhum SELECT devolve nome, telefone, e-mail, `identifier`, conteúdo de mensagem, título, descrição ou motivo de card, nome de empresa, de funil ou de etapa, valor de campo, `source_filename` ou o `example_masked` das colunas.

Saem: `account_id`, contagens, percentuais, percentis, meses (AAAA-MM), booleanos de flag, códigos do sistema e os textos da regra abaixo. Os códigos que o código grava a partir de uma lista fixa (`opt_out_source`, `fluxo`, `metodo`, `alvo`, origem do card) são comparados com essa lista e saem como `(outro)` se vierem diferentes.

**Domínio de e-mail, etiqueta e origem de card digitada não saem mais como texto.** Os únicos domínios que aparecem são os escritos na própria consulta (parte 2, topo).

### 3.3 Regra do texto (versão 2)
Vale para chave de campo, nome exibido de campo, título de coluna de planilha e chave de JSON. O texto só sai quando cumpre todas:
1. não tem `@`;
2. tem menos de 6 dígitos (contados com `translate()`, sem regex);
3. aparece em pelo menos **3** contas ativas (`min_contas`). Nos blocos de campo (21, 28, 46, 48, 49, 50 e 51), só conta a conta em que a chave tem **valor**;
4. só para título de planilha (blocos 32 a 35) e chave de e-mail (37): vem de planilha (ou campanha) "boa": pelo menos 2 títulos (ou chaves) preenchidos e nenhum com `@` ou 6+ dígitos. **Conta-se a conta, não a planilha.**

O teste é feito no texto inteiro; o texto sai em minúsculas, sem espaço nas pontas e cortado em 60 caracteres. O que não passa vira `(oculto)` e entra só na contagem; nas listas de mais comuns (32 a 34 e 37), fica de fora e é contado no bloco 35.

### 3.4 Risco que sobra
A regra é um filtro, não uma prova. O caso que ainda passaria: uma linha de dado lida como cabeçalho, **sem telefone nem e-mail**, com pelo menos 2 células preenchidas (ex.: nome e cidade), importada em 3 contas diferentes. Planilha de contatos quase sempre tem telefone ou e-mail na primeira linha, o que a torna "suspeita"; mesmo assim, antes de levar a saída para fora da conversa com o Rodrigo, passe o olho nas colunas de texto dos blocos 32 a 34, 37, 46 e 48. São listas curtas, e um nome de pessoa salta à vista.

### 3.5 Teste que comprova
- **Banco de teste vazio** (`chatwoot_test_1246`, porta 55432, `-X -v ON_ERROR_STOP=1 -f`): as 5 partes saíram com código 0, todos os blocos (15, 6, 16, 14 e 1) e a linha `FIM` de cada parte, sem erro nem aviso; primeira linha `BEGIN`, última `ROLLBACK`.
- **Dados inventados** (`teste/fixture-v2.sql`, roda cada parte com `-v parte=<caminho absoluto da parte>`): a fixture da versão 1 mais as contas ativas 990004 e 990005, para exercitar a regra de 3 contas nos dois sentidos. Cobre domínio pessoal (`paulo-pii-silva.com.br`) em 3 contas, erro de digitação de e-mail, origem de card digitada, etiqueta em 3 contas, chave definida em 3 contas com valor em 2, a mesma planilha reimportada com uma coluna a mais, uma linha de dado lida como cabeçalho ("Maria PII Souza", telefone, endereço) em 3 contas, campanha de e-mail com uma chave só que é nome de pessoa ("ana pii costa") em 3 contas e origem de card com cara de classe de canal fora da lista (`Channel::PIIFulano`).
  - **Nenhuma marca apareceu na saída.** A busca por `pii|exemplo|acme|corretora|paulo|12345678|99999|5511|5521|ramal|joao|maria|souza|rua |luca|ana |costa|fulano|@` não achou nada fora das linhas `\echo` e do aviso do psql.
  - Os números dos blocos alterados bateram com o calculado à mão. Exemplos: bloco 18, `hotmail.com.br` em 3 contas, `gmail.com.br` com 1 contato, `(outros comuns)` = 1 domínio em 3 contas, sem nome; bloco 28, `apolice` visível (valor em 3 contas) e `renovacao` oculta (definida em 3, valor em 1); bloco 35, na conta 990004, 3 visíveis, 3 ocultos por planilha suspeita, 1 de uma conta e 1 de poucas contas; bloco 48, `segmento` oculto (definido em 3, valor em 2); bloco 46, `cpf` e `apolice` visíveis e `segmento` e `renovacao` ocultos pela mesma razão; bloco 37, só `cidade` (a chave de uma coluna só não sai); bloco 26, `Channel::PIIFulano` contado em `(outro)`; bloco 52, 4 escreveram, 2 iguais, 1 vazio, 1 atrasado, 1 campo sem mensagem.
  - O banco de teste já tinha duas contas (1116 e 1117) com as mesmas 67 importações. Nelas, a planilha cujo "cabeçalho" é `João Luca Campos` e duas colunas vazias, que na versão 1 passou pela regra das 2 contas, agora conta como suspeita (um título só) e não sai.
  - Depois de cada execução, o banco de teste voltou a ter 0 contas, 0 contatos, 0 empresas e 0 importações de teste.
  - No teste, cada parte roda dentro da transação aberta pela fixture, por isso o psql avisa "there is already a transaction in progress". O aviso só aparece no teste.
- **Ao validar no Mac do Rodrigo,** chame o psql pelo caminho completo do binário: o `psql` do PATH passa pelo resumo do `rtk` e corta linhas da saída.

---

## 4. Bloco 52 na versão 2 (colunas novas)

Tudo sobre a janela de 90 dias, só contas ativas:
- `escreveram_90d`: contatos com mensagem própria (`sender_type = 'Contact'`, a condição que atualiza o campo, `message.rb:349-350`) nos 90 dias. É a soma das 4 colunas seguintes.
- `campo_igual`: `last_activity_at` a até 1 dia da última mensagem.
- `campo_vazio`: escreveu, mas `last_activity_at` é nulo.
- `campo_atrasado`: `last_activity_at` mais de 1 dia antes da última mensagem.
- `campo_adiantado`: `last_activity_at` mais de 1 dia depois (outra fonte, como importação).
- `campo_90d_sem_mensagem`: `last_activity_at` nos últimos 90 dias sem mensagem do contato na janela (data trazida por importação, `data_imports/importer.rb:310,364`, ou mensagem que não conta).

Mensagem de histórico da Coexistência não atualiza o campo (`message.rb:337`): pode explicar `campo_vazio` e `campo_atrasado`.

---

## 5. Blocos

N = número de contas ativas. "+ TOTAL" quer dizer uma linha a mais com a soma.

| # | Pergunta de produto | Decisão que informa | Linhas |
|---|---|---|---|
| **Parte 1 — A. Universo e flags** ||||
| 1 | Quantas contas há em cada status (o universo é `status = 0`) | todas | ≤ 2 |
| 2 | Quais das 21 flags cada conta tem ligadas e em que mês a conta foi criada | D1 (`companies`), D2 (`crm_v2`), LG (`relationships_navigation`) | N |
| 3 | Quantas contas têm cada flag principal | D1: "`companies` em menos de ~5% das contas" | 1 |
| **B. Pessoa** ||||
| 4 | Tamanho da base; quantos contatos têm telefone, e-mail ou `identifier`; quantos não têm nenhum; bloqueados | LG e o campo que identifica a pessoa na importação | N+1 |
| 5 | Contatos por conta: p50, p90, p99 e máximo | LG (paginação), Base de clientes (limites) | 1 |
| 6 | Formato do telefone e duplicados prováveis, iguais ou só pelo nono dígito | LG ("juntar repetidos") e regra de duplicado | N+1 |
| **C. Contato x cliente** ||||
| 7 | Uso de `contact_type`; `customer_since`; card ganho; customer com e sem ganho; ganho sem ser customer | **T**, D2, LG | N+1 |
| 8 | Em que meses o `customer_since` foi preenchido | T e D2 | meses |
| **D. Opt-out** ||||
| 9 | Contatos com opt-out, marcados por usuário; primeiro e último mês | LG | N+1 |
| 10 | De onde veio cada opt-out | LG; a importação tem que respeitar a recusa | ≤ 5 |
| **E. Entrada de contatos** ||||
| 11 | Contatos criados por mês (18 meses) e quantos já conversaram | LG e ritmo de entrada | ≤ 18 |
| 12 | Por conta e mês (12 meses): criados e maior número num só dia | Base de clientes: quem já importa base | ≤ 12N |
| **F. Canais** ||||
| 13 | Caixas por tipo de canal | LG | ≤ N×(canais+1)+1 |
| 14 | Contatos por canal: ligados, que conversaram e em 90 dias | LG | ≤ N×canais |
| 15 | Contatos em 1 ou em mais de um tipo de canal | LG | N+1 |
| **Parte 2 — G. Empresas** ||||
| 16 | `company_id` x texto `company_name`; ligáveis a empresa existente; empresas a criar | **D1**: quanto o backfill por nome traria | N+1 |
| 17 | Simulação do backfill de Empresas por domínio do e-mail: grátis da gem, **grátis fora da gem** (listas da consulta), comum, já cadastrado, próprio | **D1**: rodar o backfill como está? | N+1 |
| 18 | Contatos e empresas por domínio **das listas escritas na consulta**; `(outros comuns)` e `(lista da gem)` só em contagem | **D1**: completar a lista antes de rodar | 44 |
| 19 | A tabela `companies`: preenchimento, vínculo real, contador divergente, Prospecção | **D1** | N+1 |
| 20 | Empresas criadas por mês | D1 | meses+1 |
| 21 | Chaves preenchidas em empresas | D1 | curto |
| **Parte 3 — H. CRM (negócio)** ||||
| 22 | Funis, etapas de ganho e perda, caixas que criam card | **D2** | ≤ N |
| 23 | Etapas por funil: mediana, p90, máximo | D2 | 1 |
| 24 | Cards por status, sem contato, com valor, `external_id`, campo | D2 e T | N+1 |
| 25 | Cards criados por mês, 18 meses | D2 | ≤ 18 |
| 26 | Origem do card: canal (lista fechada), códigos do sistema, `(vazio)`, `(outro)` | D2 | curto |
| 27 | Cards abertos sem conversa e parados | D2 | N+1 |
| 28 | Campos de card por conta e chave (chave visível = valor em 3+ contas) | D2 e PS | ≤ N×(chaves+1) |
| **I. Importações e planilhas** ||||
| 29 | Importações por conta e fluxo | Base de clientes | ≤ 3N+1 |
| 30 | Importações por mês e fluxo | idem | meses × fluxos |
| 31 | Quem decidiu as colunas e largura das planilhas | Base de clientes | ≤ 15 |
| 32 | Os 150 títulos de coluna mais comuns (planilhas boas, 3+ contas) | **D1/D2**, **T** | ≤ 150 |
| 33 | Título que virou nome, telefone, e-mail ou empresa | D1 | ≤ 120 |
| 34 | Títulos que viraram coluna extra | D1, D2, PS | ≤ 100 |
| 35 | Por conta: títulos visíveis e ocultos, por motivo; planilhas suspeitas | quanto do vocabulário é de cada cliente | N+1 |
| 36 | Importações de e-mail por status e método | Base de clientes | curto |
| 37 | Chaves das colunas extras de e-mail (campanhas boas: 2+ chaves; 3+ contas) | idem | ≤ 80 |
| **Parte 4 — J. Etiquetas** ||||
| 38 | Etiquetas configuradas e usadas, contatos etiquetados | LG | N+1 |
| 39 | Etiquetas por número de contas com o mesmo título (só contagem) | **T** e LG | ≤ 4 |
| 40 | Tag em contato que não é etiqueta configurada | limpeza antes de importar | ≤ N+1 |
| **K. Atividade** ||||
| 41 | Faixas pela última vez que o contato escreveu | **LG** | N+1 |
| 42 | Faixas pela última movimentação em qualquer conversa; sem conversa | LG | N+1 |
| 43 | Conversas por contato: p50, p90, p99, máximo | LG | N+1 |
| **L. Campos e atributos** ||||
| 44 | Campos definidos por conta e modelo; sem descrição | **PS** | N+1 |
| 45 | Campos por modelo e tipo | PS | ≤ 32 |
| 46 | Chaves de campo de contato, empresa e card que se repetem entre contas, com o nome mais comum (valor em 3+ contas) | PS e D1 | curto |
| 47 | Por conta: campos de contato definidos, usados e nunca preenchidos | **PS** | N+1 |
| 48 | Campos de contato por chave (chave visível = valor em 3+ contas) | PS | curto |
| 49 | Chaves de `additional_attributes` no total (preenchidas em 3+ contas) | LG e PS | curto |
| 50 | As mesmas chaves por conta | idem | ≤ N×chaves |
| 51 | Redes sociais preenchidas | LG | ≤ 10 |
| **Parte 5 — M. Conferência** ||||
| 52 | Últimos 90 dias: mensagem do contato x `contacts.last_activity_at` (seção 4) | LG: os grupos podem usar só o campo, que tem índice? | N+1 |

Siglas: **D1** empresa como destino na v1; **D2** criar negócio na importação; **LG** lista e grupos prontos; **PS** "Para que serve?" (`attribute_description`); **T** termos "contato" ou "cliente". Detalhe em `docs/base-de-clientes/PESQUISA-RELACIONAMENTOS.md`.

---

## 6. Achados no código que mudam a leitura dos números

1. **Já existe backfill de Empresas por domínio de e-mail, e ele não é seguro para o Brasil como está.** `rake companies:backfill` (`enterprise/lib/tasks/companies.rake:3-11`) roda em todas as contas e cria empresa pelo domínio, pulando só o e-mail "gratuito" da gem `email-provider-info` 0.0.1 (161 domínios). A gem não tem `hotmail.com.br`, `outlook.com.br`, `live.com`, `msn.com`, `terra.com.br`, `ig.com.br`, `globo.com`, `r7.com`, `zipmail.com.br`, `oi.com.br` e outros. Os blocos 17 e 18 medem quantos contatos cairiam numa "empresa" desse tipo.
2. **A mesma regra já roda sozinha** quando um contato de conta com a flag `companies` ganha o primeiro e-mail (`enterprise/app/models/enterprise/concerns/contact.rb:9-33`). A importação desliga essa associação (`company_linker.rb:108`).
3. **O backfill em lote não atualiza o contador nem o `company_name` do contato** (`company_account_batch_job.rb:20`). A coluna `contador_divergente` do bloco 19 mede isso.
4. **O "Importar contatos" cria a informação nova só como texto e sem descrição** (`contact_imports/custom_attributes.rb:51`).
5. **O card chega à empresa pelo contato ou pela Prospecção** (`crm/cards/company_resolver.rb:2-3,61`).
6. **Mensagem de histórico da Coexistência não atualiza `last_activity_at`** (`message.rb:337`).
