# #1093 — rascunho da Nova campanha, teste para qualquer endereço, "Melhorar com IA"

Decisões do Rodrigo (07/10/2026), registradas na issue:

1. Com campanha sem terminar, "Nova campanha" pergunta antes: [Continuar essa] [Começar uma nova].
   O botão "Voltei do editor" sai. A entrada vem do endereço (`journeyEntry`): `returned=1`,
   `audience=<id>`, `email=<id>` (só retoma se for o e-mail do rascunho), `draft=1` (recarregar no meio).
   Rascunho vazio = sem rascunho (o armazenamento é limpo).
2. Teste de envio para qualquer endereço digitado: até 5, só `campaign_manage`, limite 10 por hora por
   usuário e campanha contando **envios** (um pedido), não endereços — no máximo 50 e-mails por hora.
   Endereço suprimido ou de contato que recusou mensagens é recusado antes de qualquer envio
   (`EmailCampaign#refuses_address?`, a mesma proteção do envio real).
3. "Melhorar com IA" só com texto ou botão selecionado; desligado mostra a dica. `setSelectedText`
   nunca troca seção/coluna (defesa em profundidade).

Overlay Enterprise: nenhum override de `TestSendsController` nem de `EmailCampaignPolicy`;
`campaign_manage` já está em `CustomRole::PERMISSIONS`.

Validação local (worktree, sem produção):

- vitest (campanhas, jornada, Campaigns): 69 arquivos, 874 testes, 0 falhas (com `TZ=UTC`, como no CI).
  Sem `TZ`, `journeyHelpers.spec.js` falha 1 teste de fuso também no `origin/main` (fuso da máquina).
- rspec (`email_campaigns`, `campaign_journey/email_campaigns`, `services/email_campaigns`,
  `autonomia/guide/formatos`): 841 exemplos, 0 falhas.
- rubocop: 3 arquivos, 0 ofensas. eslint: 0 erros. `pnpm i18n:fork:check`, `pnpm guia:check` e
  `rails autonomia:guia:formatos:check` em dia (formatos regenerados: `to_emails`).
- Prints das telas (1440 e 390): retomar rascunho, campo do teste, "Melhorar com IA" ligado/desligado.
