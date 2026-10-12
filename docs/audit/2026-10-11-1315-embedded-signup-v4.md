# #1315 — Embedded Signup v4: evidência e registro por conexão (11/10/2026)

## Prazo da Meta

- Embedded Signup v2 descontinuada em 15/10/2026; na tabela de versões, v2 e v3 "disponíveis até outubro de 2026"; v4 sem fim.
- A versão vem da configuração do Facebook Login for Business: com produtos selecionados ela é v4. O `extras` do JS não escolhe a versão.
- Fontes: [Versions](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/versions),
  [Implementation](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/implementation),
  [Business app users](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users).

## Configuração (leitura do painel, 11/10)

A configuração usada pelas duas instalações tem produtos selecionados (Cloud API, Marketing Messages API, CTWA,
Conversions API): v4. O código não passa `extras.version`. Os eventos v4 já eram tratados desde o #225.

## Produção (11/10, psql via SSM, `BEGIN TRANSACTION READ ONLY`, só ids, datas e contagens)

| Stack | Caixas `source = embedded_signup` | Mais recente | Observação |
|---|---|---|---|
| hub2you | 7 (jun → 10/10/2026) | 10/10/2026 | todas com `phone_number_id` e WABA; 6 com `history_sync_requested_at` |
| autonomia | 0 | — | — |

- Nenhuma caixa guarda evento, versão ou se foi Coexistência. A conexão bem-sucedida não gravava log.
- Log do container: zerado no deploy blue-green de 11/10 13:12 UTC, sem linhas de authorization. Prova durável só no banco.
- Conclusão: conexões recentes funcionaram com a configuração atual, mas não havia como provar a versão por registro nosso.

## O que o #1315 grava

`provider_config` ganha `signup_event`, `signup_version`, `signup_is_coexistence` e `signup_completed_at` em toda
conexão e reautorização (chaves no jsonb existente, sem coluna nova). Também uma linha
`[WHATSAPP] Embedded signup completed … event=… version=… coexistence=…`, sem token nem número.

Conferência pós-deploy (psql só leitura):

```sql
SELECT id, account_id, provider_config->>'signup_event' AS evento, provider_config->>'signup_version' AS versao,
       provider_config->>'signup_is_coexistence' AS coexistencia, provider_config->>'signup_completed_at' AS quando
FROM channel_whatsapp WHERE provider_config ? 'signup_event' ORDER BY updated_at DESC LIMIT 20;
```

## Validação local

- rspec (serviço, controllers WhatsApp, HistorySync, Reauthorization e specs de formatos do Guia): 101 exemplos, 0 falhas.
- vitest (composable, Reauthorize, SwitchAccount, ConfigurationPage, onboarding, EmbeddedSignup): 59 testes, 0 falhas.
- rubocop: sem ofensas; lint de e-mail/i18n da CI: 0 bloqueios; `autonomia:guia:formatos:check`: em dia.
- Revisão independente: 0 bloqueantes. O risco de o HistorySync perder a gravação foi testado no banco real e não se confirma.
