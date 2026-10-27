# Novo público pedindo em palavras — backend (#2277)

Em **Campanhas › Público › Novo público › Das suas conversas**, a pessoa escreve quem quer encontrar. A IA da
própria conta lê as conversas do período e monta a lista. A pessoa revisa e salva como público de campanha.

## Quem pode usar

- Precisa da flag da conta `campanhas_publico_por_conversa` (`feature_flags_ext_2`), mais `CAMPAIGN_JOURNEY_ENABLED`
  e `CAMPAIGN_IMPORT_ENABLED`. Sem qualquer um dos três, a API responde 404.
- Podem usar o administrador e quem tem uma função com `campaign_manage` **e** `conversation_view`.
- Cada busca pertence a quem a fez. Ninguém mais vê a busca, nem pela API.

## Quem paga

- Só a chave de IA da própria conta: a integração "IA do CRM" (`crm_kanban_ai`).
- A chave da instalação (`CAPTAIN_OPEN_AI_API_KEY`) nunca é usada. Sem a chave da conta, a tela pede para conectar,
  e o job para com `no_key`.
- Cada chamada aparece no Gasto com IA, com estas features:
  - `campaign_conversation_audience_plan`: o planejador;
  - `campaign_conversation_audience_read`: os leitores.

## Como roda

### 1. Planejar (`ConversationAudience::PlanJob`, fila `default`)

- Modelo `gpt-6.1-sol`, esforço medium.
- Entrada: o pedido e 12 trechos curtos de conversas da conta.
- Saída: a regra e, quando o pedido tem duas leituras, uma pergunta.
- Com a regra pronta, divide o período em lotes de até 20 conversas ou 60 mil caracteres.
- Mostra custo e tempo estimados. O teto é o dobro da estimativa.

### 2. Ler (`ConversationAudience::ReadJob`, fila `low`)

- Uma onda por vez: até 6 lotes em paralelo, com `gpt-6-luna` e esforço medium.
- Concorrência: uma busca por conta e três na instalação (`ConversationAudience::Semaphore`). A busca que passa do
  limite espera na fila; nunca dá erro por isso.
- Antes de cada onda, se a onda puder passar do teto, a busca para em `ceiling` e pergunta.
- Lote lido não é lido de novo. Parar, continuar e retomar depois de erro seguem do próximo lote pendente.
- Falha passageira (429, 5xx, rede): o lote tenta de novo na onda seguinte, até 3 vezes. Chave recusada ou cota
  esgotada param a busca em `failed`.

### 3. Salvar (`ConversationAudience::Save`)

- Cria um `CampaignImport` de público (`flow: audience`, `completed`), como a planilha deixa. A lista de públicos,
  "Criar campanha" e o envio tratam os dois do mesmo jeito.
- Não grava contato.
- Ficam de fora quem pediu para não receber e quem não tem celular válido. A tela mostra essas pessoas à parte.

### 4. Sininho

- A notificação `conversation_audience_ready` avisa quem pediu quando a busca termina, para no teto ou falha.
- É só no painel: não manda e-mail nem push.
- Clicar abre a busca em `Novo público?busca=<id>`.

## Estados

| Estado | O que significa |
|---|---|
| `planning` | a IA está entendendo o pedido |
| `question` | a IA espera a resposta da pessoa |
| `planned` | plano pronto, ainda não foi pago nada |
| `queued` | na fila |
| `reading` | lendo as conversas |
| `done` | terminou |
| `stopped` | parada pela pessoa |
| `ceiling` | parada no custo combinado |
| `failed` | parada por erro |
| `saved` | virou público |

Cancelar enquanto está na fila (`queued`, nada lido) volta para `planned`.

## Instruções das IAs

- As instruções estão em `ConversationAudience::Planner::INSTRUCTIONS` e `ConversationAudience::Reader.instructions`.
- São as mesmas medidas no eval de qualidade de 27/10/2026 (conta 3, com o Opus 5.5 como controle). Valem para
  qualquer ramo de negócio.
- O que mais muda a qualidade da lista é a regra que o planejador escreve. Mudou alguma instrução? Meça de novo antes
  de subir.

## Custo de referência

Na conta inteira da GTA (1.381 conversas), uma busca custou cerca de US$ 0,40 (≈ R$ 2,20) e levou de 1 a 3 minutos.
