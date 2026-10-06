# #1082 — biblioteca de e-mail em português — 06/10/2026

## Decisões

- 13 modelos aprovados na galeria (06/10) substituem os 14 do pacote Mailteorite. Conteúdo e visual mantidos; só o
  rodapé foi trocado pelo canônico de #1081 (`lockedFooter.json` em `238f9cd6b6`, com a linha de identidade, igual a
  `EmailCampaigns::LockedFooter.with_first_line` / `editableFooterMjml()`). Este PR entra **depois** de #1081.
- Fotos em `public/email-templates/biblioteca/` (5 JPG, ≤ 116 KB). O MJML guarda caminho relativo; o seed troca pelo
  `FRONTEND_URL` do stack (Nokogiri + `URI.join`, substituição literal de `src="…"`, sem regex).
- Retirada: o seed apaga só os globais com os 14 nomes de `retired.json`; outro global fora do catálogo é relatado e
  mantido; modelos das contas nunca são lidos para escrita. Sem FK de campanhas para a tabela.
- Seed passou a ser dry-run por padrão (`APPLY=1` grava) e entrou no runner de ops (`ops-email-templates-seed.yml`).
  O deploy blue-green continua sem gravar dados (só `db:chatwoot_prepare`).
- Gate de qualidade `EmailCampaigns::QualityGate` (portado de `check.py`), reutilizável; neste PR ligado só à
  biblioteca (`quality_gate_library_spec.rb`) e ao `rails email_campaign_templates:compile`. A medição em navegador
  do `check.py` (escala do NPS ≥ 44 px no celular, overflow em 375 px) ficou fora do CI.
- LICENSE do Mailteorite removida: nenhum material deles permanece em `db/seeds/email_templates/`
  (cópias históricas em `docs/campaigns/mockups/800/` não foram tocadas).

## Validação local (banco de teste `chatwoot_test_lib`, nunca produção)

- Specs da biblioteca/gate/seed/catálogo/API de modelos: 43 exemplos, 0 falhas.
- `spec/services/email_campaigns` + `spec/requests/api/v1/accounts/email_campaigns`: 782 exemplos, 2 falhas por
  contagem global de `EmailSuppressionEvent` deixada por specs de concorrência sem transação (mesmo caso registrado
  em `2026-10-01-release-campaigns-800.md`); os dois arquivos passam (12/12) num banco novo.
- Seed ponta a ponta: 14 globais antigos + 1 modelo de conta → dry-run `create=13 retire=14` sem escrita → apply →
  13 globais, 0 antigos, 5 com foto absoluta, 0 relativas, modelo da conta idêntico → segundo apply `unchanged=13`.
- Vitest (templates + locales) 257/257; `pnpm i18n:fork:check`, `pnpm guia:check` e
  `scripts/check-email-protection-i18n.mjs` sem erro; RuboCop sem ofensas nos Ruby tocados.

Publicação em produção: `docs/runbooks/email-biblioteca-modelos.md` (não executada).
