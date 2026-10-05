# Auditoria — Base de campanha → disparo WhatsApp (05/10/2026)

Pedido do Rodrigo: verificar, em todas as contas e logs, se importar base e disparar campanha funciona de ponta a ponta; conferir o código em produção; avaliar uso do Jev na importação; repensar lugar, jornada e layout.

## Como foi verificado

- Produção, só leitura: `psql` via SSM dentro de `chatwoot-web`, com `default_transaction_read_only=on` e `statement_timeout`. Nenhum `rails runner`, nenhuma escrita, nenhum envio, nenhuma chamada paga ao Jev.
- Duas stacks: Hub2You (`354307071110`) e Autonom.ia (`140023375763`).
- Imagem em produção na Hub2You: `8800a6ac2f003f3f099daf27f6f255ae08414d01` = `origin/main` em 05/10. Sem diferença de código de importação/disparo entre produção e `main`.
- Telefones exibidos só mascarados (`+5545…30`). Nenhum nome de cliente registrado aqui.

## Uso real

| Stack | Importações de base | Campanhas WhatsApp | WhatsApp API |
|---|---|---|---|
| Hub2You | 13, todas na conta 6 (07/07 a 01/09) | 11, conta 6, WhatsApp Oficial (Cloud), caixa 51 | 0 |
| Autonom.ia | 0 | 0 | 0 |

A conta 16 (Hub2you, das capturas) nunca importou base.

Padrão de uso da conta 6: **uma importação por campanha** (11 bases para 11 disparos, ligadas 1:1 pela etiqueta) e **sempre 1 lote** (`batch_count = 1` nas 13). O fatiamento foi feito à mão, em campanhas de 20 → 40 → 100 → 200 contatos — aquecimento de número feito pelo operador.

## O que funciona

- 12 importações concluídas, 1 recusada por 1 celular inválido em 100 linhas (reenviada no minuto seguinte com 99).
- Etiquetas: as 11 campanhas apontam para a etiqueta-base certa, e o número de contatos etiquetados hoje bate com o importado (20, 20, 12, 40, 41, 40, 100, 100, 100, 199, 99 = 771).
- As 11 campanhas ficaram `completed`. Etiquetas ocultas (`show_on_sidebar=false`) aparecem no seletor de público (getter `labels/getLabels` não filtra).
- Contatos importados não duplicaram contatos já existentes (nenhum par criado antes da importação).

## Problemas encontrados

### P1 — Não há prova de entrega dos 771 envios

- `campaign_recipients` está vazia nas duas stacks. O rastreio por destinatário (upstream #15276) entrou depois dos disparos de agosto; o serviço antigo descartava o retorno do `send_template` e só escrevia em log.
- Logs de agosto não existem mais: os contêineres são recriados a cada deploy (atuais têm 35 min).
- "Concluída" só significa "o job terminou". Erro da Meta por contato não ficou registrado em lugar nenhum.
- Única evidência indireta: respostas. Em 7 dias, ~15 contatos importados responderam na caixa 51, mais 6 respostas que caíram em contatos duplicados (P2) — **~21 de 771, cerca de 3%**. Não dá para separar "não entregue" de "não respondeu".
- Código atual já grava `sent/failed/skipped` por destinatário e tem tela de análise. Ainda não foi exercitado em produção (zero linhas).

### P2 — Respostas caíram em contato duplicado (9º dígito) — já corrigido no código

- 6 de 771 contatos responderam com o número sem o 9 (`wa_id` de 12 dígitos); o Chatwoot criou um contato novo (`+55DD8…`) em vez de achar o importado (`+55DD98…`). A resposta ficou sem as etiquetas da campanha e fora do histórico do contato importado.
- Causa: o importado não tem `contact_inbox` na caixa, e a busca por telefone não tentava as variantes brasileiras.
- Correção `9550de83e4` (03/09) está na imagem em produção. Nenhuma campanha rodou depois, então ainda não foi provada com base importada.
- Os 6 pares continuam separados no banco. Juntar exige escrita em produção — decisão do Rodrigo.

### P3 — Plano de lotes calcula errado

`LabelPlanner#batch_sizes`: primeiro lote = `total − ceil(total/lotes) × (lotes − 1)`.

- 9 contatos em 4 lotes → `lote_1` com **0** contatos.
- 5 contatos em 4 lotes → tamanho **−1**, `Array.new(-1)` estoura, e a tela mostra o genérico `file_could_not_be_processed`.
- A checagem `batch_count <= linhas` não pega esses casos. Não afetou produção (sempre 1 lote).

### P4 — Base e campanha não se conhecem

- Nada liga `campaign_imports` a `campaigns`; a única ponte é o nome da etiqueta, que o usuário precisa achar numa lista com todas as etiquetas `campanha_*` e `_lote_N`.
- Lotes não fazem nada no disparo: para usar 5 lotes o usuário cria 5 campanhas à mão.
- "Gestão de campanhas" só mostra e-mail.

### P5 — Uma linha ruim derruba a base inteira

Validação recusa o arquivo todo se qualquer linha tiver erro (caso real: 1 em 100). A importação roda numa transação única: um erro em um contato desfaz todos e marca todos como falha.

### P6 — Cabeçalho rígido; Jev só no e-mail

- Base de campanha aceita só os aliases fixos (`nome`, `telefone`, `whatsapp`, `celular`, `numero`…). "Fone", "Tel. celular", "Contato WhatsApp" ou cabeçalho em linha 3 falham.
- `TypesafeAi::ImportSchemaResolver` (Jev `jev-1.13.0`) é chamado só por `EmailCampaigns::RecipientImporter`. Em produção, 1 importação de e-mail já foi resolvida pelo Jev (01/10); antes dele, 7 falharam por cabeçalho (`missing_name_header`, `missing_email_header`).
- O resolvedor e o prompt são específicos de e-mail (`EMAIL_INSTRUCTIONS`, `contains_valid_email`). Para telefone, falta o equivalente com evidência de celular válido.

### P7 — Risco latente no WhatsApp Oficial

O seletor de caixa aceita caixa WhatsApp não-Cloud; o serviço recusa só depois de marcar a campanha como `processing`, e ela fica presa sem destinatário. Não ocorreu (caixa 51 é Cloud).

## Rollback

Nada foi alterado. Sem rollback.
