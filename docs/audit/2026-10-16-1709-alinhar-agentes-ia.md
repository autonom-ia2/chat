# #1709 — alinhamento pendente com a sessão Agentes IA (16/10/2026)

Pedido do Rodrigo, 12:49 BRT: "os agentes precisam receber as informações corretamente". A sessão Agentes IA está parada por créditos até 13:40 BRT, então a mensagem vai depois desse horário.

## O que levar aos Agentes IA

1. Envio pelo agente (IA) na caixa híbrida ou WAHA, com `whatsapp_rich_native` ligado:
   - options sai como LISTA nativa, inclusive com até 3 opções;
   - location e contact saem nativos;
   - link_button, location_request e flow continuam em texto;
   - `RichMessages.delivery_mode(..., message:)` responde `:native` só quando o envio realmente sairá nativo;
   - sem `message:`, a resposta é `:text`.
   - Pergunta para eles: o agente decide o formato da mensagem rica consultando `delivery_mode`? Precisa saber que, no Híbrido, opções viram lista e que não existem botões?
2. Resposta do cliente a uma lista:
   - chega como mensagem recebida com `content` = título da linha;
   - `content_attributes.selected_option = {id: <id original da opção>, title}`, com o id SEM o sufixo `|<message_id>`;
   - `content_attributes.in_reply_to` = id da mensagem de opções no Chatwoot.
   - Pergunta para eles: o agente lê `selected_option` ou só o texto? A ligação via `in_reply_to` serve para o contexto da IA?
3. Fase 2 (caixa WAHA comum, conector WAHA customizado): o mesmo formato de 1 e 2. O voto de enquete (`poll.vote`) ainda está em avaliação.
4. #1489 (mensagem "não suportada" recuperada):
   - `hybrid_recovered_at` (contrato do #1637) e o evento `whatsapp_hybrid.message_recovered`;
   - o PR deles do #1637 ainda não saiu: confirmar quando sai;
   - o #1489 já está mesclado com a main depois do #1627 (enum: o 8 é deles; os nossos vão de 10 a 13).
5. Pedir:
   - os specs ou fixtures do lado deles que leem `selected_option`, `rich_message` e `delivery_mode`;
   - o OK do formato antes do PR do #1709.
