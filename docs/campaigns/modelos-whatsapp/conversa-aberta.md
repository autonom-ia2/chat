# Conversa aberta na campanha do WhatsApp oficial (#1335, épico #1320)

Na campanha do WhatsApp oficial, quem mandou mensagem para a caixa nas últimas 24 horas recebe uma **mensagem escrita**
(texto livre, sem modelo). Quem não falou recebe o **modelo aprovado**, como sempre. A pessoa escreve o texto com uma
ajuda de IA (canal `whatsapp_campanha` do `Ai::Redacao::Escrever`).

Decisões do Rodrigo (13/10/2026): divulgação também vale como texto livre, com um aviso na tela quando o modelo é de
divulgação; link só por campo; ajuda na caixa de resposta da conversa fica para outro PR; flag própria, ligada em todas
as contas.

## Regras

- **Janela**: a do contato na caixa (`Whatsapp::ServiceWindow`), pela hora da última mensagem recebida dele. Ela é
  medida na tela (uma foto) e **conferida de novo no envio de cada pessoa**.
- **Envio** (`CampaignJourney::ConversaAberta::Envio`): a pessoa recebe o texto se a campanha tem mensagem escrita, a
  conta tem a flag e a janela está aberta agora. Em qualquer outro caso, recebe o modelo:
  - falta o valor de um campo;
  - a Meta recusa o texto na hora;
  - a Meta avisa depois com `131047` (janela fechada). Neste caso o modelo sai uma vez só, pela
    `CampaignJourney::ConversaAberta::Queda` e o `QuedaJob`. A queda não acontece se o Híbrido já entregou o texto pelo
    WhatsApp API.
- **Na conversa**: a mensagem escrita entra na conversa do contato com
  `additional_attributes = { campaign_id, campaign_free_text: true }`. O robô do #1405 não assume conversa de campanha.
- **Campos**: os do catálogo, mais as colunas do Público.
  - Campos do catálogo: `cliente.primeiro_nome`, `cliente.nome`, `minha_empresa.nome`, `minha_empresa.site`.
  - Colunas do Público: `{{publico.<cabeçalho com _ no lugar dos espaços>}}`. O `Ai::Redacao::Chaves` não aceita
    espaço na chave, e `Texto.colunas` volta ao cabeçalho real.
- **Link**:
  - Trava só o inequívoco ("://" ou "www.").
  - O "ponto entre letras" (`WhatsappTexto.link_inventado?`) só avisa, porque erra em "Sr.Paulo" e "Ltda.São Paulo".
  - Tudo com métodos de string, sem regex.
- **Preço**: o do contrato do #1322 (`Whatsapp::Pricing`). O modelo custa pela categoria. A mensagem escrita é grátis
  até a franquia do mês do número (`Whatsapp::ServiceMessageCount`); depois paga a tarifa de serviço. Sem a franquia
  lida, a tela conta tudo como pago.

## Limitações conhecidas

- **Híbrido e 131047.** Quando a Meta recusa o texto com 131047 e o WhatsApp Híbrido **assume** o reenvio pelo WhatsApp
  API, a mensagem ganha a marca `whatsapp_transport_fallback`. Com essa marca, a campanha **não** manda o modelo: a marca
  quer dizer "o Híbrido assumiu", não "entregou". Se o envio do Híbrido falhar depois, a pessoa fica sem texto e sem
  modelo. É uma escolha conservadora, para não mandar duas mensagens à mesma pessoa.
- **Mensagem achada pelo id.** O Híbrido troca o `source_id` da mensagem pelo id do WAHA antes de enviar. Por isso a
  entrega guarda o `message_id` da mensagem da conversa, e a queda acha a mensagem por ele. A entrega em si é achada
  pelo `source_id` do aviso, que é o wamid gravado no envio.
- **Contagem.** Quem falou nas últimas 24 h mas não tem o valor de um campo do texto entra em "falaram com você" e, no
  envio, recebe o modelo. A tela avisa que é uma estimativa.

## Tempo da contagem (medido em 13/10/2026)

Volume sintético, local: 400 mil mensagens recebidas em 2 caixas e 20 mil contatos.

- **Consulta de um lote de 1.000 contatos** (`EXPLAIN ANALYZE`): 1,9 ms. Usa o índice
  `index_messages_on_sender_and_created` (sender_type, sender_id, created_at), filtrando conta, caixa e tipo.
- **Público de 20 mil pessoas**: 20 lotes, cerca de 40 ms, mais a leitura das linhas do público (a mesma regra do envio).
- **No envio**: uma consulta igual por pessoa, com 1 contato, lida pelo mesmo índice.

Antes de ligar numa conta muito grande, vale repetir o `EXPLAIN` com o volume real (só leitura).

## API (gate: `CAMPAIGN_JOURNEY_ENABLED` + flag `campaign_open_window_text` no servidor; `campaign_manage`)

`GET /api/v1/accounts/:id/campaign_journey/conversa_aberta?campaign_import_id=&inbox_id=&categoria=MARKETING`

```json
{ "payload": { "dentro": 37, "fora": 1163, "fecham_logo": 6, "conferido_em": "2026-10-13T12:00:00-03:00",
  "precos": { "modelo": { "valor": "0.3217", "moeda": "BRL" }, "escrita": { "valor": "0.035", "moeda": "BRL" } },
  "franquia": { "limite": 1000, "usadas": 230 } } }
```

`POST /api/v1/accounts/:id/campaign_journey/conversa_aberta/escrever`

- Corpo: `{ campaign_import_id, inbox_id, objetivo, resposta, tom, base, melhoria, categoria }`.
- `melhoria` aceita `mais_curta`, `mais_clara` ou `mais_simpatica`; com ela preenchida, `base` é o texto atual.
- Resposta: `{ payload: { status, opcoes: [{ texto }], pergunta, sugestoes } }`.
- A IA indisponível responde 503 `ia_indisponivel`.

A criação da campanha (`POST campaign_journey/campaigns`, canal `whatsapp_cloud`) aceita `campaign.free_text`. O texto
é conferido antes de gravar e a recusa vem com o motivo: 422 `free_text_invalid`, `details.reason`. Com a flag
desligada, a resposta é 422 `free_text_disabled`.

## Banco

- `campaign_free_texts`: o texto, um por campanha.
- `campaign_free_text_deliveries`: quem recebeu o texto, para a queda no 131047.

As duas tabelas são do fork, sem coluna nas do Chatwoot (migration `20261024100000`). A flag é ligada em todas as contas
e nas novas pela migration `20261024100001` (`lib/feature_flag_rollout.rb`).

## Se der erro: desligar

O que faz: tira o bit 262144 (bit 18 da `feature_flags_ext_1`) de todas as contas e põe o padrão das contas novas em
`false`. Com a flag desligada, toda campanha volta a mandar só o modelo e a API responde 404. Nenhum dado é apagado.

```sql
UPDATE accounts SET feature_flags_ext_1 = feature_flags_ext_1 & ~262144 WHERE feature_flags_ext_1 & 262144 <> 0;
UPDATE installation_configs
   SET serialized_value = jsonb_set(serialized_value, '{value}', (
     SELECT jsonb_agg(CASE WHEN item->>'name' = 'campaign_open_window_text' THEN item || '{"enabled": false}' ELSE item END)
       FROM jsonb_array_elements(serialized_value->'value') AS item))
 WHERE name = 'ACCOUNT_LEVEL_FEATURE_DEFAULTS';
```

Depois, limpar o cache do GlobalConfig (`GlobalConfig.clear_cache`) ou esperar a expiração.
