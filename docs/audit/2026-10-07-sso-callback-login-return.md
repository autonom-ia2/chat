# Retorno ao login apos rejeicao do callback SSO

## Decisao e escopo

O usuario autorizou uma PR exclusiva para retornar ao login do Auth quando o
Chatwoot rejeita o callback SSO. A inconsistencia cadastral sera corrigida em outro
fluxo. Esta PR nao altera autenticacao, autorizacao, provisionamento, usuarios,
contas, banco, infraestrutura ou variaveis de ambiente.

## Causa e correcao

O callback envia falhas para `/app/login?error=autonomia-sso-error` ou
`autonomia-sso-state`. O componente removia `error` da query; o prop `authError`
ficava vazio e `shouldAutoRedirectToAutonomia` voltava a ser verdadeiro. Isso
reativava o spinner, mas a navegacao so era executada em `created`, que nao e
executado novamente quando a query muda.

- As duas falhas conhecidas do callback, com SSO Autonomia disponivel, encerram o
  loading e usam `location.replace` para `/auth/autonomia?prompt=login`.
- A mensagem existente descreve falha de validacao de acesso, nao senha incorreta.
- O destino reutiliza `autonomiaRetryUrl`: somente same-origin, entrada fixa do
  Auth e `return_to` interno; email e token da tentativa anterior nao sao enviados.
- `loginApi.hasErrored` bloqueia o redirect automatico apos a limpeza de uma query
  de erro. Erros de outros provedores e SSO desabilitado permanecem na tela local.
- Falhas transitorias de `/auth/sign_in`, sucesso, MFA e limite de sessoes mantem
  os fluxos existentes.

## Validacao local

- Base: `origin/main`, commit `496258e375`.
- Regressao antes da correcao: quatro casos falharam, confirmando falta de retorno
  ao Auth e reativacao do loader apos a limpeza da query.
- `pnpm test app/javascript/v3 --maxWorkers=2 --minWorkers=1`: 44 testes aprovados.
- Regressao ampliada (v3, router, routeHelpers e store auth): 109 testes aprovados
  em 11 arquivos. Avisos externos de Browserslist e sourcemap faltante nao afetaram
  o resultado.
- ESLint dos arquivos alterados: zero erros; 24 avisos i18n preexistentes no login.
- Prettier e `git diff --check`: aprovados.
- Dependencias instaladas com lockfile congelado na worktree isolada, sem scripts
  de instalacao e sem alterar lockfiles.

## Navegador e CI

O gate de navegador existente foi ampliado para os dois erros de callback e para
o erro neutro apos a limpeza da query. O fixture agora monta o componente pelo
RouterView com props derivados da query e historico web, reproduzindo a transicao
reativa que faltava nos testes anteriores.

O gate usa respostas sinteticas, bloqueia rede externa e verifica retorno unico
ao Auth, `prompt=login`, destino interno e ausencia de tentativa de login local.
O build completo e o gate Chromium ficam para o CI do SHA da PR; nao foram
executados localmente. Teste sintetico nao equivale a login E2E em producao.

Nenhum Rails de producao, acesso EC2, alteracao RDS, merge ou deploy foi realizado.
