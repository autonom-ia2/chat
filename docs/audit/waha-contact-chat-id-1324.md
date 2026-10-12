# Leitor único do chat id WAHA do contato (#1324)

Refs #1322 (§3.1). Refatoração sem mudança de comportamento. Sem migration, sem flag.

## Decisão

`Waha::ContactChatId` (`app/services/waha/contact_chat_id.rb`) passa a ser dono dos nomes dos atributos
(`waha_whatsapp_chat_id`, `waha_whatsapp_jid`, `waha_whatsapp_lid`), da leitura e da escrita do chat id WAHA do contato.

- `candidates(contact, contact_inbox: nil)`: chat_id → jid → source_id, só os presentes, valor bruto.
- `primary(contact, contact_inbox: nil)`: o primeiro dos candidatos.
- `values(contact, *sources, contact_inbox: nil)`: só as fontes pedidas (`:chat_id`, `:jid`, `:source_id`).
- `store!(contact, chat_id)`: o que era `WahaChat#store!`, sem mudança (sufixo `@lid` por `end_with?`).

Chamadores:

- `BroadcastGuard#blocked?`: `values(contact, :chat_id, :source_id, ...)`. **O jid continua fora de propósito**; passar a
  olhá-lo muda comportamento e vai em PR próprio, com OK do Rodrigo. O spec do guard fixa isso.
- `WhatsappGroupDetector.chat_id`: `primary`.
- `Notices::WahaChat`: grava por `store!`.

## Validação

Banco de teste isolado (`chatwoot_ag_1324`), specs focados:

| Rodada | Arquivos | Resultado |
|---|---|---|
| Antes (código e specs do main) | guard, detector, sender, booking_pages_notices, webhook_listener, SLA | 151 exemplos, 0 falhas, 1 pendente |
| Specs novos dos chamadores contra o código antigo | guard, detector, sender, booking_pages_notices | 96 exemplos, 0 falhas |
| Depois | os seis + `waha/contact_chat_id_spec.rb` | 175 exemplos, 0 falhas, 1 pendente |

O pendente é a quarentena antiga de `webhook_listener_spec.rb:127`, igual antes e depois.
RuboCop nos 7 arquivos tocados: sem ofensas.

## Revisão

`caveman:cavecrew-reviewer`, foco "mudou comportamento?": nenhuma mudança encontrada; 0 bloqueantes. Um nit de
legibilidade (`contact&.custom_attributes.to_h`, mesmo idioma do código antigo) mantido para a equivalência ficar
evidente.
