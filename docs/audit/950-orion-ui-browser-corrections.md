# #950 — correções UI após browser real (2026-10-04)
Escopo: somente os seis arquivos de produto abaixo. Não alterei QA/harness/results/imagens, controller/protocolo/backend, assets globais, widget global, contas, Redis ou banco.
Flag instagram_automation_responsive_layout ativa apenas no novo painel: nav hidden md:flex (desktop >=768px mantém sidebar), main min-w-0 flex-1 overflow-auto. Fora da flag, classes anteriores preservadas. Backlink para Configurações permanece acessível no mobile. Nenhum CSS custom. Opt-out separado do widget de suporte continua exclusivo do painel.
Todos os datetime usam iso8601(3), preservando .600 etc. Texto humano usa chave própria numérica EN/PT-BR. Idade usa segundos/minutos/horas com seis plurais locais, sem depender de calendários/date.month_names ou datetime globais ausentes no pt_BR. Estado Meta/gestor e guards de reconexão permanecem.
Orientação curta: salvar identificadores antes de iniciar gestor, mesmo prefilled. Botões novos usam !important Tailwind com tokens blue11/blue8 e valores padrão do design system dentro da própria utility: asset superadmin atual não define --blue-*; isso evita cor inválida sem acrescentar vars/CSS globais. Contraste estático com branco: claro4.91/escuro5.39/hoverclaro12.66/hoverescuro7.00. Contraste computado/browser depende da rebuild.
Validação sem DB: três ERB compilados; dois renders ActionView standalone EN/PT-BR com timestamps .600 exatos, data numérica, cinco campos, flags e guard de reconexão: PASS. RuboCop helper focal: PASS. git diff --check: PASS. Prettier --check apenas en.yml/pt_BR.yml apresentou avisos de formato nos catálogos; não executei --write nem reformatei catálogos inteiros. Sem RSpec/Rails.application/build/browser durante slot Vega. Script puro: tmp/950-integration/orion-ui-nodb-check.rb.
Parent deve rebuild assets para novas utilities; rerun serial/browser antes de declarar correções verificadas visualmente. Request specs anteriores de datetime esperam iso8601 sem fração: ajustar contrato esperado para iso8601(3), mantendo comparação exata. Browser case14 label account-toggle pertence Theo; case18 erros legados SDK404 de páginas sem opt-out/422 intencional continuam fora deste patch. Não modifiquei QA para esconder esses resultados.

## SHA-256 dos arquivos de produto
- `app/views/super_admin/instagram_automation/show.html.erb` — `6cc2b68c9d909f08182c8fb42a24ec9b81084cf9d4c83c06d1dc01239ed2c52b`
- `app/views/super_admin/application/_navigation.html.erb` — `8ce85ee4b6a53f1fc2a1f14b4a83c9bfff6ecee1bbc206f1ae3857be6831fb21`
- `app/views/layouts/super_admin/application.html.erb` — `110682012b9865dc8e7288e3307f2d19d4477782259582acabf9fee17e258454`
- `app/helpers/super_admin/instagram_automation_helper.rb` — `f3c83b9a8e82176ccbf9ed6be992604a0d949e1131680e4ee4e0d4942f114d66`
- `config/locales/en.yml` — `510aaf2ad889a87a8c976c125af0edd55b27b3648b1468a64c0425a7de0c19d5`
- `config/locales/pt_BR.yml` — `677f041833156bd33f1c1579de6267b24ad287df2550a4761ee4a5d51132d65b`

### Ajuste após QA real 16/18
Aplicado `dark:!bg-n-background` exclusivamente ao main do novo painel pela flag existente. O token dark é `18 18 19`; header e seções herdam a superfície. Nenhuma mudança nos botões, sidebar ou comportamento claro. Compilação ERB isolada e `git diff --check`: PASS. Build e browser pendentes com parent/Vega; nenhuma execução de banco ou rede nesta rodada.
SHA256 `app/views/layouts/super_admin/application.html.erb`: `64a567e9599dbde6365131c9bc4050d0b9ef90b2a3f6b436eedfb6d966fdd33c`.
