# RED frontend B3/BE-05 — retomada do Builder

Data: 2026-10-07
Escopo: contrato de retomada no cliente para a primeira tela real, sem alterar o produto.

## Base lida

- `docs/agentes-ia-redesign/design/B3.md`, sobretudo §§3.1–3.6, 4 e 5;
- `docs/agentes-ia-redesign/design/F0-mapeamento.md`, sobretudo as dependências B3/BE-05, o guard de
  retomada guiada e a regra de não chamar `start` nem criar thread;
- `AGENTS.md` da worktree e `/Users/rodrigosilva/dev/AGENTS.md`.

## Lacuna que o RED fixa

O cliente existente conhece somente a rota top-level `build_threads` (`create`, `show`, `sendMessage` e
`retryBuild`). A retomada aprovada precisa de um leitor nested account-scoped:

```text
GET /api/v1/accounts/:account_id/autonomia/agents/:agent_id/build_thread
```

Ao retomar, o store deve limpar a projeção local, hidratar o `id`, `agent_id`, `messages` e `state` da
thread retornada e iniciar polling somente quando o status retornado for `processing`. A retomada não pode
chamar `create`, `show` top-level, `sendMessage`, `retryBuild`, `start` ou qualquer POST.

## Specs RED adicionadas

### API client

`app/javascript/dashboard/api/specs/autonomia.spec.js` agora exige `buildThreads.resume(42)` no caminho
nested da conta corrente (`/api/v1/accounts/85/autonomia/agents/42/build_thread`) e confirma que essa
operação não faz POST.

### Store Builder

`app/javascript/dashboard/store/modules/specs/autonomia/buildThreads.spec.js` agora cobre:

1. retomada de uma thread `processing`, preservando ids, mensagens e state, com polling pelo id retornado;
2. retomada de uma thread `ready`, preservando a hidratação sem polling;
3. ausência de `start`, `create`, `show`, `sendMessage` e `retryBuild` durante a retomada.

Os dados de mensagem têm ids explícitos de exemplo para impedir que a implementação substitua o histórico
por uma lista cenográfica ou perca a identidade da thread/agente.

## Estado e validação

Este bloco é RED por construção: `resume` ainda não existe no cliente/API e a action correspondente ainda
não existe no store. Os specs foram escritos após a leitura dos módulos reais; não foram executados por
orientação do principal durante a captura do snapshot. Não houve alteração em `buildThreads.js`,
`autonomiaBuildThreads.js`, API Rails, store de produto, rotas ou banco.

Próxima etapa: o principal implementa o contrato BE-05 no cliente depois de consolidar o snapshot. A execução
dos dois arquivos de spec deve comprovar primeiro a falha específica por ausência de `resume`; só então o
produto pode ser alterado.

## Implementação autorizada após RED

O RED foi executado no snapshot 22 pelo job `m2-3bf3eb66bb3d4f8ab5deca6fe59ab969`. A evidência registrada
em `/tmp/chat2you-agentes-frontend-red22.json` tem SHA-256
`05318f55650d30ac32a919ab9146eba7d625c130b0aa1ac29af945a33f3e85a4`: 38 exemplos executados, 29 aprovados,
9 falhas e 4 suítes não coletadas porque os módulos F0 ainda não existem. Entre as falhas, a API não possui
`buildThreads.resume` e o store não possui a action `resume`, confirmando o RED deste bloco.

Com autorização do principal, a correção fica restrita a `buildThreads.js` e `autonomiaBuildThreads.js`.
`resume` hidrata a thread nested account-scoped e só agenda `poll` para `processing`; `ready`, `open` e
`failed` permanecem hidratados sem chamar `onSettled` diretamente. Nenhum caminho de retomada chama `start`,
`create`, `show`, `sendMessage`, `retryBuild` ou POST de criação. O frontend de produto e a casca de
`PanelTune` continuam fora deste bloco.

Antes de congelar o bloco, a leitura do contrato B3 confirmou que `401`, `404` e `422` devem preservar o
agente e a projeção anterior. Por isso o store limpa a projeção somente depois de um GET bem-sucedido; a falha
mantém thread, mensagens, status e fase anteriores, encerra apenas o estado de carregamento e propaga o erro
para o chamador. O spec do store cobre essa preservação com uma rejeição `404`, além dos estados settled acima.

## Checagem frontend23 — causa registrada antes da correção

O job `m2-3077a4f799ae4abf9e98bb9cf76607f5` executou o JSON `/tmp/chat2you-agentes-frontend-check23.json`,
SHA-256 `3f8204f2f0cc81c2e34d4744147788586f1e197021cf0f5a8fb680998639e162`: 34 exemplos executados, 33
aprovados e uma falha. A falha ocorreu no spec da API, que chamava `buildThreads.create` e depois
`buildThreads.resume` dentro do mesmo exemplo. O `create` fez o POST legítimo
`/api/v1/accounts/85/autonomia/build_threads` para o agente 7; em seguida a asserção global
`axiosMock.post.not.toHaveBeenCalled()` atribuía esse POST anterior à retomada do agente 42.

Essa é uma causa de fixture do teste, não evidência de POST em `resume`. A correção mínima é isolar a
retomada em um exemplo próprio, com o mock limpo pelo `beforeEach`, mantendo a verificação exata do GET
nested e a asserção de que nenhum POST ocorre naquele exemplo. O código de produto continua fora deste
ajuste.
