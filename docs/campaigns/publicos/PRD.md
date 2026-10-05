# PRD — Públicos e nova jornada de campanha WhatsApp

Data: 05/10/2026 · Dono: Rodrigo · Status: proposta para aprovação

Evidência de origem: [auditoria de 05/10/2026](../../audit/2026-10-05-auditoria-base-de-campanha.md). Épica: [#990](https://github.com/autonom-ia2/chat/issues/990) · Mockup: https://claude.ai/artifact/DEgd2WS2gp4XuvqTbh6vwP

## 1. Problema

A base de campanha (planilha de nome + celular) mora no menu ⋮ de **Contatos**, longe da campanha que a usa. O único uso real em produção (conta 6, 13 importações, 11 disparos, 771 contatos, jul–set/2026) mostra:

1. **Base e campanha são 1:1.** Cada disparo teve sua própria importação. O usuário importa em Contatos, decora o nome da etiqueta e depois a procura numa lista com todas as etiquetas `campanha_*` e `_lote_N`.
2. **Lotes nunca foram usados** (`batch_count = 1` nas 13). O fatiamento real foi feito à mão, criando campanhas de 20 → 40 → 100 → 200 contatos para aquecer o número.
3. **Não há prova de entrega.** As 11 campanhas aparecem "concluídas", mas nada registra se cada mensagem saiu, chegou ou falhou.
4. **Uma linha ruim derruba o arquivo** (caso real: 1 celular inválido em 100).
5. **Cabeçalho rígido.** Só nomes de coluna de uma lista fixa; o Jev já resolve isso na importação de e-mail, não aqui.
6. **Respostas se perdem em contato duplicado** quando o WhatsApp devolve o número sem o 9 (6 de 771; correção de código já em produção, sem prova com base importada).
7. **Erro no cálculo de lotes** (lote vazio ou falha genérica com poucas linhas).

## 2. Objetivo

Quem cria uma campanha de WhatsApp sobe a planilha **dentro da campanha**, vê quem vai receber e quem ficou de fora, agenda o envio e depois acompanha enviados, entregues, lidos, respondidos e falhas — sem passar por Contatos e sem conhecer etiqueta.

### Métricas de sucesso

| Métrica | Hoje | Meta |
|---|---|---|
| Telas percorridas da planilha ao agendamento | 2 áreas, 2 formulários, etiqueta digitada/procurada | 1 fluxo de 3 passos |
| Arquivos recusados por cabeçalho | sem medição na base; 7 de 14 no e-mail antes do Jev | 0 com nome de coluna reconhecível por pessoa |
| Arquivos recusados por poucas linhas ruins | 1 de 13 | 0 (importa as válidas) |
| Destinatários com situação conhecida após o disparo | 0% | 100% (enviado, entregue, lido, falhou ou pulado com motivo) |
| Respostas de campanha em contato duplicado | 6 de 771 | 0 |

## 3. Fora do escopo

- Importação de destinatários de **e-mail** (continua dentro da campanha de e-mail; já usa Jev). Unificar com Públicos é outra fase.
- Campanhas de SMS e Chat ao vivo (SMS poderá escolher um Público em fase futura; nada muda nele agora).
- Segmentação por atributo/filtro dinâmico. Público aqui é **lista estática** vinda de planilha ou etiqueta.
- **Envio em etapas / lotes.** Fora por decisão de 05/10 (simplicidade). O backend de lotes continua, invisível, sempre com 1 lote.
- Custo estimado por conversa da Meta (não temos tabela de preço confiável na base).
- Juntar os 6 contatos duplicados já existentes (operação de banco de produção, decisão separada do Rodrigo).

## 4. Usuários e permissões

- **Quem cria campanha:** administrador ou função personalizada com `campaign_manage`.
- **Quem só consulta:** `campaign_view` vê Públicos, campanhas e resultados; não importa, não desfaz, não dispara.
- Mesmas chaves que hoje (`CampaignImportPolicy`). Nenhuma chave nova.

## 5. Decisões de produto

| # | Decisão | Por quê |
|---|---|---|
| D1 | **Públicos** vira subpágina própria em **Campanhas**, compartilhada pelos canais WhatsApp. Sai do menu ⋮ de Contatos ("Base Campanha" e "Histórico de bases"). | A base gera contatos + etiquetas, que servem a qualquer canal. Uma página por tipo duplicaria histórico. É o padrão de Mailchimp (Audience), Klaviyo (Lists & segments) e HubSpot (Lists). |
| D2 | O caminho principal é **subir a planilha dentro de "Nova campanha"**. Públicos é para reaproveitar, consultar e desfazer. | Uso real 1:1. |
| D3 | **Lotes saem da interface** (importação, Públicos e campanha). Sem envio em etapas: a campanha envia tudo no horário escolhido. O código de lotes fica no backend, sempre com 1 lote. Decisão do Rodrigo em 05/10: simplicidade primeiro. | Lote nunca foi usado (`batch_count = 1` nas 13). Quem quiser aquecer número cria campanhas menores, como já faz. |
| D4 | **Importa as linhas válidas**; as inválidas ficam listadas com motivo e baixáveis. | Recusar 100 por 1 é atrito sem ganho. |
| D5 | **O sistema acha as colunas sozinho** (nome, celular e cada variável do modelo) usando o Jev por baixo. **A interface nunca cita o Jev**: diz só "colunas encontradas". O modelo recebe cabeçalhos, formato mascarado e a lista do que o modelo de mensagem precisa; nunca nome ou número. | Mesmo contrato de privacidade do e-mail (#764). O usuário quer o resultado, não o nome da ferramenta. |
| D8 | **O modelo de mensagem é escolhido antes do público.** As variáveis dele (`{{1}}` nome, `{{2}}` mês de vencimento…) viram a lista do que procurar na planilha. | Com o alvo conhecido, achar a coluna é mais certeiro (ex.: `{{2}} mês de vencimento` → coluna *Vencimento*), e o usuário vê de onde sai cada pedaço da mensagem antes de enviar. |
| D6 | O nome técnico da etiqueta some da interface. O usuário vê o **nome do público**. A etiqueta continua existindo por baixo. | Ninguém deve decorar `campanha_7_envio_100_annt_nova_11`. |
| D7 | Criação em **página com passos**, no layout das campanhas de e-mail (#800), não no formulário flutuante. | Padrão visual atual do produto. |

## 6. Jornada

### 6.1 Nova campanha WhatsApp Oficial — 3 passos

`Campanhas › WhatsApp Oficial › Nova campanha`

**Passo 1 — Mensagem**
- Nome da campanha.
- Caixa de envio: só caixas WhatsApp Cloud aparecem. Se a conta não tiver nenhuma, o passo explica e leva para criar.
- Modelo aprovado: escolha com busca. Mostra categoria (Marketing, Utilidade) e idioma.
- Variáveis do modelo: cada `{{n}}` tem um campo; a fonte é um dado do contato (nome, primeiro nome), **uma coluna da planilha** (achada no Passo 2) ou texto fixo. O passo explica que escolher o modelo antes ajuda a achar as colunas certas.
- Prévia como o cliente vê, com o primeiro contato do público quando ele já existir.

**Passo 2 — Público**

Duas opções, lado a lado:

- **Enviar planilha** (padrão)
  1. Arrastar ou escolher CSV/XLSX (até 10 MB, 20 mil linhas XLSX / 50 mil CSV).
  2. Lendo… (barra de progresso, a tela não trava).
  3. Resultado em "O que a mensagem precisa e de onde vem": uma linha por necessidade — Nome (`{{1}}`), Celular, e cada variável do modelo que vem da planilha (ex.: `{{2}}` Mês de vencimento) —, com a coluna encontrada, um exemplo (número mascarado), quantas linhas estão preenchidas e "Trocar". Nenhuma menção ao Jev ou a IA.
  4. Contagem: **98 prontos para receber · 2 com problema · 3 já recusaram mensagens**. "Ver problemas" mostra motivo por linha (número mascarado) e "Baixar planilha de correção".
  5. Quem já existe na base é reconhecido (inclusive com/sem o 9) e não é duplicado; a tela diz "41 já eram seus contatos".
- **Usar público salvo**
  - Escolha com busca entre Públicos da conta (nome, contatos, data, campanhas que já usaram).

Abaixo, em ambos:


**Passo 3 — Revisar e agendar**
- Resumo: caixa, modelo com prévia, público, quantos recebem, quantos ficam de fora e por quê.
- Quando: agora ou data/hora (fuso da conta).
- Botão principal: "Agendar envio" / "Enviar agora". Confirmação final com o número de pessoas.
- Importação de contatos acontece **na confirmação**, não antes. Abandonar o fluxo não cria contato nem etiqueta.

### 6.2 Depois do envio — detalhe da campanha

- Faixa de resultado: Público · Enviadas · Entregues · Lidas · Responderam · Falharam · Puladas.
- Tabela de destinatários com filtro por situação, número mascarado, motivo da falha traduzido (ex.: "Número sem WhatsApp", "Limite diário da Meta atingido") e link para a conversa quando houver resposta.
- "Baixar resultado" (CSV, número mascarado).

### 6.3 Públicos

`Campanhas › Públicos`

- Resumo: públicos salvos, contatos em públicos, importados nos últimos 30 dias.
- Lista: nome, origem (planilha/etiqueta), contatos, criados × já existentes, campanhas que usaram, data, situação.
- Ação principal: "Novo público" (mesmo componente do Passo 2, sem campanha).
- Painel lateral do público: números, problemas da importação (baixáveis), campanhas que usaram, **"Remover do público"** (= desfazer etiquetas; nunca apaga contato) e "Usar em nova campanha".
- Substitui o "Histórico de bases". Importações antigas aparecem aqui com o nome da campanha original.

### 6.4 WhatsApp API

A página WhatsApp API usa o mesmo Passo 2 (planilha ou público salvo). O motor de envio do canal não muda.

## 7. Layout

Seguir o padrão do workspace de e-mail (#800, `EmailCampaignsPage.vue`) e as regras de `docs/audit/800-email-campaigns-uiux.md` e `docs/relationships/visual-contract.md`:

- Moldura `max-w-[90rem]`, caminho "Campanhas › WhatsApp Oficial", título + subtítulo, **uma** ação principal à direita.
- Faixa de resumo contínua; primeiro bloco em azul-marinho `#0D2344`.
- Lista em cartão, abas por situação (Rascunho, Agendadas, Enviando, Concluídas), busca.
- Criação em página com passos numerados (`aria-current="step"`), como `EmailBuilderPage.vue`.
- Detalhes de público em painel lateral de 37rem; abaixo de 1280px, sobreposto.
- Escolhas com `ChoiceSelect`. Nenhum `<select>` nativo, nenhum `ComboBox`/`TagMultiSelectComboBox` antigo nas telas tocadas.
- Tailwind e tokens `n-*`; sem CSS próprio.
- Larguras validadas: 1440, 1280, 1024, 768 e 390px; claro e escuro.

## 8. Requisitos técnicos

### 8.1 Dados (migrations aditivas)

- `campaigns.campaign_import_id` e `whatsapp_api_campaigns.campaign_import_id` (nullable, índice): liga campanha ao público.
- `campaign_imports.name` (nome do público mostrado ao usuário; preenchido com `campaign_name` nas existentes).
- `campaign_imports.schema_resolution` (jsonb; mesmo formato do e-mail: método, colunas, sem dados de linha).
- Nenhuma coluna removida. Novas importações gravam `batch_count = 1` (sem etiquetas `_lote_N` além da do lote único, como hoje); o campo não aparece em nenhuma tela. Os antigos ficam como estão.

### 8.2 Importação

- `CampaignImports::SchemaResolver` ganha modo telefone: candidato com evidência de celular válido (`PhoneNormalizer`), Jev resolve `phone_index`/`name_index`, fallback determinístico com os aliases de hoje. `TypesafeAi::ImportSchemaResolver` recebe o alvo (`email` | `phone`) e as instruções correspondentes. Recebe também as **variáveis do modelo escolhido** (rótulo e posição, sem valores) para mapear cada uma a uma coluna ou declarar "não há coluna"; o resultado guarda `variable_columns` em `schema_resolution`. Perfil enviado ao modelo: cabeçalho, contagem, formato mascarado (`0` dígito, `x` outro), nunca valor.
- Jev desligado ou sem chave: segue determinístico; cabeçalho não reconhecido mostra a escolha manual de colunas (não um erro).
- Validação marca linha a linha; arquivo só é recusado se **nenhuma** linha for válida ou por erro global (formato, tamanho, limite de linhas, fórmula).
- Busca de contato existente pelas variantes brasileiras (`Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer#contact_candidates`), não por igualdade exata.
- Contato com `opted_out` entra no público mas é contado como "já recusou" e nunca recebe.
- Gravação em blocos de 500 linhas, cada bloco em sua transação, idempotente por `row_number`; falha de uma linha marca só ela.
- Rascunho de público (validado, não confirmado) não cria contato nem etiqueta; expira em 30 dias (regra atual).

### 8.3 Disparo WhatsApp Oficial

- Guarda de caixa: criação/edição recusa caixa que não seja `whatsapp_cloud` (422 com código explicável), antes de qualquer `mark_processing!`.
- Público por `campaign_import_id` (contatos com status importado) ou etiquetas, como hoje.
- Destinatários registrados **antes** do envio (situação `queued`), atualizados por `mark_sent!`/`mark_failed!`/`mark_skipped!` e pelo webhook de status (já existente).
- "Respondeu" = mensagem recebida do contato na mesma caixa até 72h depois de `sent_at`.

### 8.4 Correções obrigatórias (entram primeiro)

- `LabelPlanner#batch_sizes`: distribuição com `divmod` (nunca tamanho ≤ 0). Mantido só para importações antigas/reprocessamento.
- `Validator`: não engolir exceção como `file_could_not_be_processed` sem registrar classe e mensagem segura em log.

### 8.5 Guia da Plataforma e i18n

- Rotas novas (`campaigns_audiences_index`, criação em passos) entram no roteador; rodar `pnpm guia:build` e escrever os blocos em `lib/operator_guide/porques.md`. Remover os fluxos de "Base Campanha" e "Histórico de bases" de Contatos.
- Textos novos em `en.json` (+ `pt_BR` quando o catálogo for do fork, conforme `docs/i18n/fork-translations.md`; `pnpm i18n:fork:check`).

### 8.6 Rotas e redirecionamentos

- `/contacts/campaign-imports` redireciona para `/campaigns/audiences`.
- Flag `CAMPAIGN_IMPORT_ENABLED` continua sendo o desligamento geral.

## 9. Termos de aceite

Formato: **Dado** · **Quando** · **Então**. Um item só passa com evidência (teste automatizado citado no PR ou captura do produto construído). "Funciona na minha máquina" não conta.

### A. Lugar e navegação

- **A1** Dado um usuário com `campaign_view`, quando abre o menu Campanhas, então vê "Públicos" logo abaixo de "Gestão de campanhas" (ou na posição aprovada no mockup).
- **A2** Dado qualquer usuário, quando abre o menu ⋮ de Contatos, então **não** vê "Base Campanha" nem "Histórico de bases".
- **A3** Dado o endereço antigo `/contacts/campaign-imports`, quando acessado, então redireciona para Públicos sem erro.
- **A4** Dado um usuário só com `campaign_view`, quando abre Públicos ou uma campanha, então não vê botões de importar, remover do público, agendar ou disparar, e a API devolve 401/403 para essas ações.

### B. Planilha e colunas

- **B1** Dado um XLSX com colunas `Segurado`, `Fone 1` e `Vencimento` e o modelo com `{{1}}` nome e `{{2}}` mês de vencimento, com Jev ligado, quando enviado no Passo 2, então nome, celular e `{{2}}` são ligados às três colunas, a tela mostra cada ligação com exemplo e contagem de preenchidos, e `schema_resolution.method = "jev"`.
- **B1a** Em nenhuma tela, texto, dica ou selo da jornada aparece "Jev", "IA" ou nome de modelo — spec de interface verifica os textos i18n das telas novas.
- **B1b** Dado uma linha com celular válido mas sem valor na coluna de uma variável do modelo, quando validada, então fica de fora com motivo "falta <variável>" (a mensagem não sai com lacuna), salvo se o usuário escolher um texto padrão para a variável.
- **B2** Dado o mesmo arquivo com Jev desligado, quando enviado, então a tela pede a escolha manual das colunas que faltarem (não mostra erro) e a importação conclui depois da escolha.
- **B3** Dado um arquivo com cabeçalho na linha 3 (linhas informativas acima), quando enviado, então o cabeçalho é achado sem intervenção.
- **B4** Dado qualquer arquivo, quando o Jev é chamado, então o corpo da requisição contém só cabeçalhos, contagens e formato mascarado — teste automatizado prova que nenhum nome e nenhum número do arquivo aparece no payload.
- **B5** Dado um arquivo com 100 linhas e 2 celulares inválidos, quando validado, então a tela mostra "98 prontos · 2 com problema", com motivo por linha e número mascarado, e permite seguir com os 98.
- **B6** Dado um arquivo sem nenhuma linha válida, quando validado, então é recusado com a lista de motivos e nada é gravado.
- **B7** Dado um celular já salvo na conta como `+55DD8XXXXXXX` (sem o 9), quando a planilha traz `+55DD98XXXXXXX`, então o contato existente é reutilizado (nenhum contato novo) e contado como "já era seu contato".
- **B8** Dado um contato que recusou mensagens ativas, quando está na planilha, então aparece em "já recusaram" e não entra no total que recebe.
- **B9** Dado que o usuário sai do fluxo antes de confirmar, quando a campanha não é agendada, então nenhum contato, etiqueta ou vínculo é criado (teste de banco).
- **B10** Dado um arquivo de 20.000 linhas XLSX, quando confirmado, então a importação conclui em até 5 minutos no ambiente de teste, em blocos, e uma falha simulada numa linha marca só essa linha.

### C. Envio

- **C1** Dado uma conta com caixa WhatsApp não-Cloud, quando abre o Passo 1, então essa caixa não aparece; e a API de criação recusa com 422 e código explicável se ela for enviada à força.
- **C2** Dado "Tudo de uma vez", quando o horário chega, então todos os destinatários elegíveis ficam com situação registrada (`sent`, `failed` ou `skipped` com motivo) — zero destinatários sem situação depois que a campanha conclui.
- **C3** Dado a criação, a importação, Públicos e o detalhe da campanha, quando o usuário navega, então nenhuma tela mostra lote, quantidade de lotes ou envio em etapas; toda importação nova grava `batch_count = 1`.
- **C5** Dado um erro da Meta para um número, quando o envio falha, então o destinatário fica `failed` com motivo legível em português na tela, e os demais seguem.
- **C6** Dado um contato que recusou mensagens durante o disparo, quando chega a vez dele, então é pulado com motivo "recusou mensagens" (regra #737 preservada).
- **C7** Dado um destinatário que responde de um número sem o 9, quando a mensagem chega, então ela entra na conversa do contato importado (nenhum contato novo) — teste com webhook simulado.

### D. Acompanhamento

- **D1** Dado uma campanha concluída, quando o usuário abre o detalhe, então vê Público, Enviadas, Entregues, Lidas, Responderam, Falharam e Puladas, e a soma Enviadas + Falharam + Puladas = Público elegível.
- **D2** Dado o webhook de status da Meta (`delivered`, `read`), quando chega, então os números da tela mudam sem recarregar (ou no próximo polling de até 30s).
- **D3** Dado um destinatário que respondeu, quando o usuário clica nele, então abre a conversa.
- **D4** Dado "Baixar resultado", quando clicado, então o CSV traz situação, horários e motivo por destinatário com número mascarado.

### E. Públicos

- **E1** Dado as 13 importações antigas da conta 6, quando a página Públicos abre, então todas aparecem com nome, contatos e a campanha que as usou (vínculo inferido pela etiqueta na migração de dados).
- **E2** Dado um público usado por uma campanha, quando o usuário clica "Remover do público", então só as etiquetas daquela importação saem dos contatos, nenhum contato é apagado, e a campanha concluída mantém seus resultados.
- **E3** Dado um público, quando o usuário clica "Usar em nova campanha", então abre o Passo 1 com o Passo 2 já preenchido.
- **E4** Dado o nome técnico da etiqueta (`campanha_*`, `_lote_N`), quando o usuário navega por Públicos e pela criação, então esse nome não aparece em nenhum texto da interface.

### F. Layout e acessibilidade

- **F1** As telas de WhatsApp Oficial, Nova campanha e Públicos seguem o padrão do #800 (moldura, faixa de resumo, lista com abas, criação em passos) — revisão visual comparando com o mockup aprovado.
- **F2** Nenhum `<select>` nativo nem `ComboBox` antigo nas telas tocadas; spec automatizado no estilo de `uxAcceptance444.spec.js` cobre os arquivos novos.
- **F3** Sem rolagem horizontal nem texto cortado em 1440, 1280, 1024, 768 e 390px, tema claro e escuro (capturas no PR).
- **F4** Navegação completa por teclado nos 3 passos; passos com `aria-current="step"`; alvos de toque ≥ 44px; contraste ≥ 4.5:1.

### G. Correções

- **G1** `LabelPlanner` com (9 linhas, 4 lotes) gera [3,2,2,2] ou equivalente sem zero; (5, 4) gera tamanhos positivos somando 5. Spec cobre 1..50 linhas × 1..10 lotes, todos positivos e soma exata.
- **G2** Exceção inesperada na validação aparece no log com classe e mensagem sem dados pessoais.

### H. Operação

- **H1** `pnpm guia:check`, `pnpm i18n:fork:check`, RuboCop, ESLint, RSpec e Vitest dos arquivos tocados verdes; saída lida, não só o código de saída.
- **H2** Revisor independente antes do merge; tester de produção com roteiro listado antes de rodar.
- **H3** Rollback escrito antes do deploy: desligar `CAMPAIGN_IMPORT_ENABLED` esconde a entrada; migrations aditivas não são revertidas; campanhas agendadas e ainda não disparadas continuam agendadas.
- **H4** Primeiro disparo real em produção acompanhado: zero destinatários sem situação, comparação de entregues com o painel da Meta.

## 10. Entrega em PRs

| PR | Conteúdo | Aceite |
|---|---|---|
| 1 — Correções (#991) | `LabelPlanner` (backend, sem tela), importar só válidas, busca com/sem 9, blocos de 500, guarda de caixa Cloud, log da exceção | B5–B7, B10, C1, G1, G2 |
| 2 — Jev para telefone (#992) | Modo telefone no `SchemaResolver` + resolvedor TypeSafe, escolha manual de colunas | B1–B4 |
| 3 — Públicos e jornada (#993) | Página Públicos, criação em 3 passos, detalhe com resultados, remoção do menu de Contatos, layout #800 | A, B8–B9, C2, C3, C5–C7, D, E, F |

Cada PR com `Refs #990`; o último fecha a épica.

## 11. Riscos

| Risco | Mitigação |
|---|---|
| Jev indisponível ou caro | Fallback determinístico + escolha manual; uma chamada por arquivo ambíguo; desligável no SuperAdmin |
| Importar parcialmente esconde problema da planilha | Contagem e download dos problemas sempre visíveis antes de confirmar |
| Limite de mensagens da Meta por dia | Motivo de falha legível e aviso na revisão quando o público passar do limite conhecido da caixa; não fazemos retentativa automática nesta fase |
| Importações antigas sem vínculo com campanha | Migração de dados liga por etiqueta (sabemos que é 1:1 na conta 6) e é idempotente |
