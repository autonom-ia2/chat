# #436 — contrato final de retomada UI / DTO público

Data: 2026-09-16. Recorte local de apresentação e testes. Sem execução Rails, banco,
SMTP, AWS, SSH, rede, instalação, leitura de `.env` ou escrita Git.
Não constitui aprovação de PR, merge, deploy ou prova de funcionamento em produção.

## Decisões e comportamento

- `Protection#capabilities.resume` exige policy update/resume, campanha pausada, provedor
  permitido, import inativo e elegibilidade real dos destinatários. Conta sem bloqueio
  pode retomar pausa manual sem 50 envios, sem estado de risco e sem geração publicada.
  `release_eligible` continua sendo evidência reputacional, e pode ser false nesse caso.
- Conta protegida por latch ou flag legada continua exigindo release_eligible: geração
  publicada atual, feedback atual, avaliação recente, snapshot da policy correspondente
  e aprovação da policy pura/LegacyDecision. Override não substitui essas condições.
- Preflight ausente/malformado/inconsistente ou modo diferente da configuração nega resume.
  Shadow/warning respeitam o modo real de `PreflightDecision`, sem introduzir enforcement
  de DNS no GET. Enforce exige ready positivo, decisão comum da campanha e candidato
  com validação fresca, checked_at e valid_until.
- Candidato real: pending, sent_at ausente, ses_message_id ausente/vazio, sem proteção
  por status nem supressão legada/ativa. `RecipientState` fornece as subconsultas comuns.
  Campanha vazia, toda protegida, sem pending ou com apenas linhas ambíguas não retoma.
  Existem no máximo dois EXISTS de destinatários por campanha em enforce, sem materializar
  listas. A medição SQL está especificada no RSpec, mas não foi executada neste recorte.
- Direct inbox ignora o breaker SES e não exige amostra SES para pausa manual sem bloqueio
  da conta. Unknown permitido/monitor desligado continua unknown; bloqueio do provedor
  sempre veta SES, inclusive para conta healthy, manual ou com override.
- UI: proteção pausada só oferece retomada com release_eligible === true e
  capabilities.resume === true. O estado visual e trigger continuam pausados.
  Provider blocked/paused/disabled veta a ação. DTO incompleto/ausente também veta,
  inclusive motivo manual legado. Provider unknown válido pode ser autorizado pelo servidor.
- `EmailProtectionPanel`, `EmailCampaignHealth` e `EmailCampaignsPage` foram lidos.
  Já utilizam o helper compartilhado; nenhuma alteração desses componentes foi necessária.
  Testes montam os componentes reais e comprovam clique único, estado pausado durante POST,
  erro seguro sem mutação otimista, payload ainda pausado e atualização após sucesso.
- Nenhuma chave/string de produto ou tradução foi adicionada. As correções de plural
  existentes foram preservadas. Verificação SHA-256: 2.829 arquivos de locale inalterados
  entre o snapshot anterior às verificações e a conferência final.

## Manifesto exato para cópia pelo parent

Arquivos alterados/criados neste recorte, sem commit ou staging:

1. `app/services/email_campaigns/presentation/protection.rb`
2. `spec/services/email_campaigns/presentation/protection_spec.rb`
3. `app/javascript/dashboard/components-next/Campaigns/EmailProtection/presentation.js`
4. `app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/presentation.spec.js`
5. `app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/panels.spec.js`
6. `app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/actions.spec.js`
7. `docs/email-campaigns/reports.md` — notas do contrato/wiring de resume.
8. `docs/audit/436-resume-contract.md`

Sem alteração de controllers, models, serviços de reputação/provedor, higiene, sender,
traduções ou outros módulos. O parent informou que C/Evaluator já publica
current_metrics.evaluation_generation; esse produtor não está presente nesta árvore e
não foi modificado nem validado por execução aqui.

## Verificações executadas

Ferramentas locais já instaladas. Todos os comandos Node abaixo foram executados com
`env -i`, PATH explícito e sem herdar variáveis reais. Não houve pnpm/npx/install.

Diretório temporário: `/private/tmp/436-resume-et1e3nlz`.
Contém pasta `empty-env` vazia, snapshot SHA-256 dos locales e este wrapper:

```js
import config from '/Users/rodrigosilva/dev/worktrees/chat2you/436-email-protection/vitest.config.ts';
export default {
  ...config,
  envDir: '/private/tmp/436-resume-et1e3nlz/empty-env',
};
```

O wrapper mantém a configuração real de testes, apontando a carga de arquivos de ambiente
para a pasta vazia. Não foi alterada a configuração do projeto.

### Vitest focado + todos os locales

```sh
env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin TZ=UTC node node_modules/vitest/vitest.mjs run --config /private/tmp/436-resume-et1e3nlz/vitest.config.mjs --no-cache --no-coverage --maxWorkers=2 --minWorkers=1 app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs
```

Resultado: **7 arquivos, 269 testes aprovados**, 4,26 segundos; máximo de 2 workers.
Panels 52; recipients 13; actions 20; presentation 26; management 1; locales 156;
campaignList 1. Aviso informativo de caniuse-lite antigo; nenhuma atualização executada.

### Verificador independente de idiomas

```sh
env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin node scripts/check-email-protection-i18n.mjs
```

Resultado: saída 0; 57 pastas, 43 idiomas ativos, 57 índices; 92 chaves de proteção +
167 legadas = 259 por idioma; **14.763 mensagens compiladas/renderizadas**, fallback false.

### ESLint e Prettier limitados ao escopo

```sh
env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin node node_modules/eslint/bin/eslint.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/presentation.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailProtectionPanel.vue app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/presentation.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/panels.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/actions.spec.js

env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin node node_modules/prettier/bin/prettier.cjs --write app/javascript/dashboard/components-next/Campaigns/EmailProtection/presentation.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/presentation.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/panels.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/actions.spec.js

env -i PATH=/Users/rodrigosilva/.nvm/versions/node/v24.11.0/bin:/usr/bin:/bin node node_modules/prettier/bin/prettier.cjs --check app/javascript/dashboard/components-next/Campaigns/EmailProtection/presentation.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailProtectionPanel.vue app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/presentation.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/panels.spec.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/actions.spec.js
```

ESLint: saída 0, **0 erros, 55 avisos** de chaves dinâmicas/não encontradas pela configuração
estática de i18n. O teste com os índices reais acima valida essas mensagens sem fallback.
Prettier: verificação aprovada. O write formatou somente os specs de panels/actions;
helper e presentation.spec já estavam no formato.

### Ruby: apenas parser, sem carregar aplicação

```sh
env -i PATH=/usr/bin:/bin /usr/bin/ruby -c app/services/email_campaigns/presentation/protection.rb
env -i PATH=/usr/bin:/bin /usr/bin/ruby -c spec/services/email_campaigns/presentation/protection_spec.rb
```

Ambos: `Syntax OK`. Nenhuma linha desses arquivos ultrapassa 150 caracteres.
Isso não equivale à execução de RSpec/Rails/RuboCop.

## Trabalho que permanece com o parent

- Integrar DTO com o Hygiene atual em listas/detalhe e respostas de POST; normalizar
  pause_reason e retornar payload com campanha/protection/preflight. Notas em reports.md.
- POST continua autoritativo: não aceitar release_eligible do cliente, revalidar provider,
  higiene e, para conta protegida, geração/feedback/release no fluxo transacional.
- Criar novo presenter após mutação; não reutilizar estado carregado antes do POST.
- Executar no ambiente Rails isolado já autorizado:

```sh
eval "$(rbenv init -)"
bundle exec rspec spec/services/email_campaigns/presentation/protection_spec.rb
```

- Executar integração de controllers/relatórios e confirmar o contrato HTTP. O RSpec deste
  recorte cobre gates/SQL somente quando rodado pelo parent; o caso de novo evento nocivo
  simula a invalidação persistida dos contadores de feedback/geração, sem disparar SNS.
- Nenhuma conclusão de PR pronta: integração backend e execução Rails permanecem pendentes.
