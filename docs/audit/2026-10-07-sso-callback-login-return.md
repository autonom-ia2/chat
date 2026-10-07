# Retorno ao login apos rejeicao do callback SSO

## Decisao e escopo

O usuario autorizou uma PR exclusiva para retornar ao login do Auth quando o
Chatwoot rejeita o callback SSO. A inconsistencia cadastral sera corrigida em outro
fluxo. Esta PR nao altera as regras de autenticacao, autorizacao, provisionamento, usuarios,
contas, banco, infraestrutura ou variaveis de ambiente.

## Causa e correcao

O callback envia falhas para `/app/login?error=autonomia-sso-error` ou
`autonomia-sso-state`. O componente removia `error` da query; o prop `authError`
ficava vazio e `shouldAutoRedirectToAutonomia` voltava a ser verdadeiro. Isso
reativava o spinner, mas a navegacao so era executada em `created`, que nao e
executado novamente quando a query muda.

- Recusa de vinculo de conta passa a ter a excecao tipada
  `CustomExceptions::AutonomiaUntrustedAccount`, mantendo a mesma regra e mensagem
  do provisioner. O callback retorna `autonomia-sso-account` nesse caso.
- Recusa de conta e estado invalido encerram o loading. So usam
  `location.replace` para `/auth/autonomia?prompt=login` quando SSO disponivel e
  redirecionamento automatico habilitado pela configuracao existente.
- `autonomia-sso-error` fica na recuperacao manual, sem reinicio automatico.
  `access_denied` retorna `autonomia-sso-cancelled`, mantendo o formulario local.
- O callback preserva `redirect_to` do estado consumido e validado nas falhas.
  Estado invalido nao recupera destino e parametros externos nao sao confiados.
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
- Revisao dos comentarios: tres casos JS falharam antes do ajuste de classificacao;
  depois, os 25 testes de recuperacao e a regressao ampliada de 112 testes em 11
  arquivos passaram.
- ESLint dos arquivos alterados: zero erros; 25 avisos do catalogo i18n no login.
- `pnpm i18n:fork:check`: aprovado, en/pt_BR consistentes.
- Adicionados sete cenarios de request do callback: recusa de conta, timeout,
  excecao generica, cancelamento com consumo de state, erro do provider e rejeicao
  de destinos externos/nao validados. Syntax Ruby validada localmente.
- RSpec/RuboCop nao executados localmente: ambiente possui apenas Ruby 2.6, sem
  rbenv/Ruby requerido pelo projeto. A validacao Rails fica para o CI do novo SHA.
- Prettier e `git diff --check`: aprovados.
- Dependencias instaladas com lockfile congelado na worktree isolada, sem scripts
  de instalacao e sem alterar lockfiles.

## Navegador e CI

O gate de navegador existente foi ampliado para recusa de conta, estado invalido,
falha generica, cancelamento e redirecionamento automatico desabilitado, alem do
erro neutro apos a limpeza da query. O fixture agora monta o componente pelo
RouterView com props derivados da query e historico web, reproduzindo a transicao
reativa que faltava nos testes anteriores.

O gate usa respostas sinteticas, bloqueia rede externa e verifica retorno unico
ao Auth, `prompt=login`, destino interno e ausencia de tentativa de login local.
O build completo e o gate Chromium ficam para o CI do SHA da PR; nao foram
executados localmente. O gate visual passou no SHA original `70c0a6d`; essa
evidencia nao valida o novo commit. Teste sintetico nao equivale a login E2E em producao.

Nenhum Rails de producao, acesso EC2, alteracao RDS, merge ou deploy foi realizado.
