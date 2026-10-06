# Recuperação de falha no login SSO

Data: 2026-10-03

Issue: https://github.com/autonom-ia2/chat/issues/918

## Escopo

Correção restrita ao handoff do Auth Autonomia para o login local do Chatwoot. Nenhuma autenticação, permissão, credencial, infraestrutura ou ambiente de produção foi alterado.

## Causa raiz

`/app/login` recebe `email` e um `sso_auth_token` de uso único e inicia o login local automaticamente. Quando `/auth/sign_in` rejeitava essa tentativa, o componente mantinha o estado visual de SSO silencioso porque o token continuava presente nos props. O fallback também navegava para `/app/login` sem distinguir rejeição terminal de indisponibilidade transitória, o que podia reiniciar o SSO automático sem oferecer uma recuperação estável.

## Comportamento corrigido

- O retorno especial ao Auth só é aplicado quando o handoff declara `sso_source=autonomia`; falhas de Google, SAML e impersonação mantêm o fallback neutro de login.
- Respostas terminais `400`, `401`, `403`, `410` e `422` encerram o loading e reiniciam o Auth por `/auth/autonomia?prompt=login`.
- Falha de rede e respostas `5xx` encerram o loading, exibem estado de erro e permitem repetir a mesma tentativa ou reiniciar no Auth.
- Uma nova tentativa limpa o estado de erro; o login bem-sucedido mantém o redirecionamento existente.
- A tela de erro recebida pelo callback não volta automaticamente ao SSO; o link manual força um login novo.
- O callback restaura o `return_to` interno guardado no estado OAuth quando o provisionamento não fornece um destino mais específico.

## Revisão de segurança do redirect

Fronteiras: status e mensagens da API são não confiáveis; `redirect_to` vem da query da tela; `AUTONOMIA_SSO_URL` vem da configuração da instalação.

Controles aplicados:

- O destino de recuperação é fixado no path same-origin `/auth/autonomia`; configuração externa ou path diferente é descartada nesse fluxo.
- Somente `/app` e caminhos iniciados por `/app/` podem ser preservados como `return_to`.
- `URLSearchParams` codifica o destino interno.
- E-mail e `sso_auth_token` não são copiados para a URL de recuperação, mensagens ou logs.
- Mensagens exibidas são traduções fixas; detalhes retornados pela API não são renderizados no estado de recuperação SSO.
- Não houve mudança na validação do token, autorização ou criação de sessão.

## Correções após revisão

- A origem do token passou a integrar explicitamente o handoff (`sso_source=autonomia`), impedindo que tokens emitidos por Google, SAML ou impersonação acionem a recuperação do Auth Autonomia.
- O `return_to` validado e assinado no estado OAuth agora é consumido no callback; um redirecionamento específico do provisionador continua tendo prioridade.
- A validação de destino aceita `/app` e `/app/...`, mas rejeita prefixos parecidos como `/application`.
- As páginas sintéticas do gate visual passaram a usar exclusivamente os assets e utilitários Tailwind compilados do projeto, sem bloco `<style>`.
- O comentário do workflow foi atualizado para refletir que a suíte principal está ativa.

Validação local da rodada pós-revisão:

- Vitest direcionado: 2 arquivos e 19 testes aprovados, incluindo quatro origens não Autonomia.
- ESLint direcionado: nenhum erro; somente os 24 avisos preexistentes de chaves i18n dinâmicas no componente de login.
- Prettier, `git diff --check`, sintaxe Ruby dos dois controllers e sintaxe Node do gate visual: aprovados.
- As specs Rails adicionadas ficaram para o CI: o host continua sem Ruby 3.4.4 e Bundler 2.5.16.

## Validação executada

- `pnpm test app/javascript/v3` — 6 arquivos e 35 testes aprovados.
- Testes novos — 15 casos aprovados, cobrindo status terminal, token inválido/expirado, rede, `5xx`, nova tentativa, sucesso, destino interno, tentativa de open redirect e supressão de loop.
- Mutação da guarda do loader — 6 testes falharam como esperado; a guarda foi restaurada.
- `pnpm exec eslint` nos arquivos alterados — nenhum erro; permanecem avisos preexistentes do carregamento dinâmico de catálogos i18n nesse componente.
- `pnpm i18n:fork:check` — 10 catálogos, 16.986 mensagens compiladas e cobertura en/pt_BR aprovada.
- `git diff --check` — aprovado antes da rodada final de documentação.

## Gate visual isolado aprovado

O usuário aprovou a execução em GitHub Actions de um gate Playwright descartável e sem credenciais. O workflow `SSO login recovery - isolated visual gate`:

- compila os assets Vite reais do SHA verificado;
- monta o componente real de login e seu cliente de autenticação;
- bloqueia toda rede externa no contexto Chromium e permite apenas loopback;
- usa respostas sintéticas identificadas como tais — não é E2E do Auth real;
- cobre `422`, token inválido `401`, token expirado `410`, `503`, falha de rede, nova tentativa seguida de sucesso, ausência de loop, `return_to` seguro e descarte de open redirect;
- grava resultados estruturados, screenshots e traces por sete dias para inspeção humana.

O resultado e a inspeção humana dos artefatos serão registrados no PR sem alterar o SHA testado.

## Limitações do ambiente

- Specs Rails não iniciaram: o projeto exige Ruby 3.4.4 e Bundler 2.5.16, mas o host expôs apenas Ruby 2.6.10 e não possui `rbenv` no PATH.
- O build Vite de produção permaneceu em `transforming...` sem progresso observável por mais de seis minutos e foi interrompido; nenhum artefato de build foi gerado.
- Não foi executado login em produção, deploy ou uso de credenciais reais.
- A associação ao GitHub Project ficou bloqueada porque a sessão `gh` atual não possui o escopo `read:project`; nenhuma permissão foi ampliada.
