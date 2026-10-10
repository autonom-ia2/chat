# Spike F0 — WhatsApp Híbrido (Cloud + WAHA) — 06/10/2026

Refs autonom-ia2/chat#1067 · roteiro `docs/whatsapp-hibrido-spike-f0.md`

## Ambiente

- Stack hub2you, conta 1, caixa 111 "Autonom.ia WhatsApp" (Cloud, Coexistência, número final 3846).
- WAHA `wa-hub` 2026.9.2, engine GOWS, tier PLUS. IP de saída em São Paulo (Hostinger). Sem proxy.
- Sessão `hybrid-spike-3846`: sem App Chatwoot, sem App de números brasileiros, sem webhook. Ignora status, broadcast, canais e grupos.
- Pareamento por código (`auth/request-code`), não QR.
- Leitura de banco: psql via SSM, `default_transaction_read_only=on`. Nenhuma escrita em banco.
- Envios feitos por Ruby puro (`net/http`) dentro do `chatwoot-web`, sem Rails.

## Gate zero — vínculo

| Item | Resultado |
|---|---|
| 0.1 Sessão chega a `WORKING` | ✅ |
| 0.2 Número da sessão = número da Cloud | ✅ (final 3846) |
| 0.3 Cloud continua recebendo após o vínculo | ✅ inbound do contato continuou entrando pela Cloud |
| 0.4 Estabilidade 24h | ⏳ em observação |

## Gate um — correlação

Fluxo: `GET /api/{session}/new-message-id` → `POST /api/send*` com `id` = ID pré-gerado → eco `smb_message_echoes` na Cloud.

| Cena | Contato | ID pré-gerado | ID dentro do wamid do eco | Atraso eco | Conversa | Resultado |
|---|---|---|---|---|---|---|
| E2 texto dentro 24h | RV | 3EB06B2466E7EFBAB2DE79 | igual | 2,5 s | #44 | ✅ |
| E4 texto fora 24h | AC | 3EB0EE12CBD980492CD9DC | igual | 2,0 s | #45 | ✅ |
| E5.1 texto idêntico | RV | 3EB01617A71758B82BD2E7 | igual | 2,0 s | #44 | ✅ |
| E5.2 texto idêntico | RV | 3EB0E95A9868D8F4132568 | igual | 7,2 s | #44 | ✅ |
| E6 imagem | RV | 3EB0CCFF3DDE0E8E2E1FEC | igual | ~4 s | #44 | ✅ anexo image |
| E6 documento | RV | 3EB0A97DECC3AD3C9BE4AF | igual | ~3 s | #44 | ✅ anexo file |
| E6 áudio (voice) | RV | 3EB000FF8E741E86EB472C | igual | ~3 s | #44 | ✅ anexo audio |

Falso positivo: **0 de 7**. WAHA respeitou o ID fornecido em 7 de 7.

### Formato do wamid

`wamid.` + base64 de um protobuf curto: `\x1c\x18<len><destinatário>\x15\x14\x00\x11\x18<len><message id>\x00`.

- Nos ecos de envio WAHA o destinatário veio como BSUID (`BR.<dígitos>`), mesmo enviando para `<telefone>@c.us`.
- No inbound do mesmo contato o destinatário veio como telefone.
- Mesmo assim o eco caiu na conversa certa: 0 contatos novos, 0 conversas novas no período.

**Regra de correlação:** decodificar o wamid e extrair o message id; ele é igual ao ID pré-gerado no WAHA. Determinística, sem texto nem horário.

## Outras observações

- **E3 reply-to:** resposta citando a mensagem E2 gravou `in_reply_to = 455004` (a bolha do eco). ✅
- **E7:** mensagem enviada pelo celular já chegava como eco (`external_echo`) antes do teste. ✅
- **Sem duplicidade hoje:** sem App Chatwoot na sessão, só o eco cria a bolha. Cada envio = 1 bolha.
- O eco pode chegar 7 s depois (E5.2). O registro da tentativa precisa existir antes do POST ao WAHA.

## Pendente

- 0.4 estabilidade 24h da sessão.
- Resposta da Autonomia Comunidade após E4 (abrir janela pelo contato BSUID).
- Amostra maior (42 envios do roteiro): fazer na F1/F2 com o código real, já que a regra é estrutural.

## Decisão

Gate um aprovado. Correlação determinística via ID pré-gerado. Segue para F1 após 0.4.

## Limpeza

Sessão `hybrid-spike-3846` mantida ligada para a observação de 24h. Remover com logout + delete ao fim, salvo se for reaproveitada na F1.
