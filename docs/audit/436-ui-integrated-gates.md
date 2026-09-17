# #436 — gates da UI integrada

A UI foi integrada sobre os contratos reais de relatórios e reputação. O gate de frontend executa a suíte Vitest inteira, não apenas os novos componentes.

O ESLint usa o catálogo inglês real (JSONs modularizados em `dashboard/i18n/locale/en`) para validar chaves literais, promovendo chaves ausentes a erro. Isso corrige o falso aviso causado pelo glob legado do projeto, sem alterar a configuração global. Apenas a regra de chaves dinâmicas conserva o nível warning que já existe no repositório; todas as outras advertências e todos os erros bloqueiam o gate. O verificador independente compila/renderiza todos os57 módulos de idiomas sem fallback, e os testes exercitam os caminhos dinâmicos de status/motivos. O wrapper tem três testes contra liberação indevida de erros, parser e textos crus.

Os quatro avisos reais de template foram corrigidos, sem desativar regras: raiz condicional de importação preservada dentro de `contents` e separadores da proveniência formatados junto aos textos traduzidos. Não foram alterados textos por idioma para fazer lint passar.

Browser plugin não listado nesta sessão; o harness existente Playwright é usado com rotas sintéticas e bloqueio de rede externa. Build, suíte completa, locale check e navegador serão executados nesta árvore antes da publicação da PR. Não há claim de resultado antecipado, merge ou deploy.

## Dependências compartilhadas na worktree local

A primeira execução Vitest desta árvore não carregou `fake-indexeddb`: o arquivo existia, mas o node_modules local é um symlink de outra worktree e estava fora da allowlist de filesystem do Vite. Nenhum teste chegou a executar; esse resultado não é uma regressão de produto nem foi tratado como verde. O wrapper local foi ajustado para autorizar apenas a raiz do projeto e o realpath das dependências, mantendo `fs.strict=true` e cache exclusivo. O harness de browser usa a mesma allowlist estreita para suportar worktrees com dependências compartilhadas; no CI, o node_modules instalado pelo lock permanece dentro da própria raiz. Nenhuma configuração global/de produção foi relaxada.

## Gate funcional final desta árvore

- Build real Vite no modo test: aprovado, com avisos já existentes de chunks grandes e caniuse-lite; nenhum overlay/runtime error.
- Suíte frontend inteira: **459 arquivos,5.058 testes, zero falhas e zero pendentes**.
- **57 módulos de idioma**,43 ativos,262 chaves por módulo: **14.934 mensagens compiladas/renderizadas sem fallback**. Tradução por modelo, sem alegação de revisão humana nativa de todos os idiomas.
- ESLint do conjunto JS/Vue: zero erros, somente96 avisos da regra nativa de chave dinâmica; chaves literais checadas com catálogo real e regras restantes sem advertências. Prettier aprovado.
- Browser Playwright: **137 checks aprovados,97 PNGs**, desktop/mobile/dark/árabe RTL, busca/status/página/export, estados vazios/erro, teclado, proveniência SES/direct e veto de retomada. Capturas revisadas, incluindo a busca mobile corrigida.

Evidências locais: `ui-integrated-build.log`, `ui-integrated-vitest-final.json`, `ui-integrated-locales.log`, `ci/eslint.json`, `visual/results.json` e PNGs sob `tmp/email436`. O browser renderiza componentes e CSS reais com respostas sintéticas; não é um teste de envio real nem de produção. O backend/API é validado em sua própria suíte PostgreSQL. Nenhum merge/deploy/flag operacional alterado. O CI deve repetir o gate no commit publicado.
