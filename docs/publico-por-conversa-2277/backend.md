# Novo público pedindo em palavras — backend (#2277)

Em **Campanhas › Público › Novo público › Das suas conversas**, a pessoa escreve quem quer encontrar. A IA da
própria conta lê as conversas do período e monta a lista. A pessoa revisa e salva como público de campanha.

## Quem pode usar

- Precisa da flag da conta `campanhas_publico_por_conversa` (`feature_flags_ext_2`), mais `CAMPAIGN_JOURNEY_ENABLED`
  e `CAMPAIGN_IMPORT_ENABLED`. Sem qualquer um dos três, a API responde 404.
- Podem usar o administrador e quem tem uma função com `campaign_manage` **e** `conversation_view`.
- Cada busca pertence a quem a fez. Ninguém mais vê a busca, nem pela API.
- No público salvo, os nomes seguem a visibilidade da conversa de origem: nos endpoints `contacts` e `sample_contact`,
  cada pessoa só vê quem veio de uma conversa que ela pode abrir (o admin vê todos). O total e o envio da campanha
  continuam com o público inteiro. Público sem o vínculo com a busca mostra a lista vazia.
- A IA só lê as conversas que a pessoa pode abrir (caixas, times e funis). A conferência acontece no plano e de novo em cada leva de leitura.
- A leitura roda numa cadeia única de jobs por busca: cada "Começar" ou "Continuar" gera um `run_token` novo, e job de
  cadeia antiga termina sem fazer nada. Busca perdida (sem batimento há 10 min, lendo ou planejando) é retomada uma
  vez só, quando a tela olha para ela.
- Os dois jobs conferem o acesso de novo antes de gastar a chave da conta. Se a pessoa perdeu a função ou saiu da conta, a busca termina como `failed` com o erro `no_access`.
- A lista e o salvar mostram só quem veio de uma conversa que a pessoa ainda pode abrir. Quem perdeu uma caixa deixa de ver o motivo das pessoas dela.

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
- Lote que falhou tenta de novo depois de 30 s, até 3 vezes. O que acontece depois depende do que falhou:
  - chave (401, 402, 403, 404): a busca para em `failed` na hora, porque todo lote falharia igual;
  - IA fora do ar (429, 5xx, tempo esgotado, rede): na 3ª tentativa a busca para em `failed`. "Tentar de novo"
    devolve as 3 tentativas a cada lote pendente;
  - a resposta daquele lote (400, resposta vazia ou ilegível): o lote fica `skipped` e a busca segue. Um lote ruim
    nunca trava o resto, e a tela diz quantas conversas ficaram sem ler.
- A tela consulta a busca a cada 3 s. Depois da primeira leitura, manda o `cursor` da resposta anterior e recebe só
  quem mudou (com 30 s de sobreposição, para não perder quem uma onda ainda gravava). Ao terminar, lê a lista inteira
  uma vez.
- "Parar" com uma onda no meio: a onda ainda grava quem achou. Enquanto ela não termina, a resposta traz
  `finishing: true` e a tela continua lendo.
- Na fila atrás de outra busca da conta, a resposta traz `ahead_minutes` (quanto falta para a outra terminar). Sem
  ninguém na frente, a tela já mostra "lendo".

### 3. Salvar (`ConversationAudience::Save`)

- Cria um `CampaignImport` de público (`flow: audience`, `completed`), como a planilha deixa. A lista de públicos,
  "Criar campanha" e o envio tratam os dois do mesmo jeito.
- Não grava contato.
- Entra quem tem celular **ou** e-mail válido, como na planilha. A campanha manda cada pessoa pelo canal que ela tem,
  então uma conta que só dispara e-mail recebe o público inteiro.
- Ficam de fora quem pediu para não receber (`nao_quer`) e quem não tem nem celular nem e-mail válido
  (`sem_contato`). A tela mostra essas pessoas à parte.
- Cada linha leva a empresa do contato e, como colunas do público, a cidade, o país e todos os atributos
  personalizados de contato da conta (`ConversationAudience::Columns`). A mensagem usa essas colunas como
  `publico.<coluna>`. Fica de fora só a coluna que ninguém do público preencheu. Atributos de data, moeda e link levam
  o tipo, para a mensagem formatar ("04/05/1990"). Coluna cuja chave já existe (outra coluna, ou uma que a campanha
  preenche sozinha: `nome`, `primeiro_nome`, `empresa`, `email`) ganha " (2)": um atributo "Empresa" nunca substitui a
  empresa do contato.
- Esses dados (empresa e colunas) são leitura de contato. Só entram se quem salva tem `contact_view` (ou
  `contact_manage`). Na tela do público salvo, quem não lê contatos não recebe os valores (`sample_contact`) nem a
  empresa (`contacts`), e o painel de contatos mostra telefone e e-mail mascarados. O envio da campanha usa as colunas
  normalmente.

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
