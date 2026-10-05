# #931 — convite: falha pré-transporte e escrita ambígua

Implementação local do achado P2. Fontes lidas: `tmp/instagram-931/brief.md`,
`review-seguranca.md`, `audit-qa-crosscheck.md` e código atual da worktree.
Sem sessão real, credenciais, rede, sockets, banco ou serviços externos.

## Decisão e contrato interno

- O claim `unknown` continua persistido antes de qualquer envio.
- `Client#invite(target_id)` aceita um bloco opcional, executado após a leitura
  da sessão e preparação das opções, imediatamente antes de `HTTParty.post`.
  Chamadas existentes sem bloco continuam com o mesmo resultado e erros.
- `Invitation` remove apenas seu claim quando esse sinal não ocorreu,
  inclusive em cancelamento anterior ao transporte. A comparação continua
  sendo feita pelo valor inteiro `unknown:<geração>` via WATCH/MULTI existente.
- Depois do sinal, timeout, cancelamento e erros HTTP 401/403/407 conservam
  `unknown` por até 24 horas; mensagem ou código público não autoriza liberar.
- A rejeição booleana explícita `payload.success == false`, em documento
  validado sem erros, recebe `Error#write_rejected = true`. Esse dado interno
  preserva a possibilidade existente de tentativa deliberada após rejeição.
  O simples código `invite_rejected` não recebe essa permissão.
- `InvitationOutcome#rejected!` passa a se chamar `release_claim!`, pois a
  operação atende também falhas comprovadas antes do transporte. Busca dos
  chamadores confirmou uso restrito a `Invitation`.
- Falhas de Redis na gravação/leitura/limpeza continuam sendo reportadas como
  `invite_unknown`, com causa sanitizada. Não são ignoradas para simular sucesso.
- Os códigos e status HTTP públicos permanecem iguais. O controller continua
  renderizando somente `error_code`; o estado interno não contém segredo.

## Arquivos alterados pelo especialista INVITE

- `app/services/instagram/testers/client.rb`
- `app/services/instagram/testers/error.rb`
- `app/services/instagram/testers/invitation.rb`
- `app/services/instagram/testers/invitation_outcome.rb`
- `spec/services/instagram/testers/client_spec.rb`
- `spec/services/instagram/testers/invitation_spec.rb`
- `spec/services/instagram/testers/invitation_outcome_spec.rb`

Não foram editados SessionStore, OAuth, UI ou arquivos de outros especialistas.

## Evidência executada

Fixture: `tmp/instagram-931/invite-regression.rb`. Carrega métodos reais de
Client, Invitation, InvitationOutcome, parser e CoordinationRedis; substitui
somente configuração/snapshot, seleção de conexão, Redis em memória e HTTParty.
Não inicializa Rails/Bundler nem usa um Redis real.

```sh
env -i PATH=/usr/bin:/bin /Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby --disable-gems tmp/instagram-931/invite-regression.rb --baseline
env -i PATH=/usr/bin:/bin /Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby --disable-gems tmp/instagram-931/invite-regression.rb
```

- Baseline HEAD: 19 cenários, 11 aprovados e 8 falhando, exit 1. Os cenários de
  sessão expirada/invalidada observam zero POST de convite e claim retido. As
  oito falhas incluem a ausência do novo sinal de transporte, não oito bugs
  independentes. Log: `tmp/instagram-931/invite-regression-before.json`.
- Código corrigido: **19 cenários aprovados, zero falhas**, exit 0. Log:
  `tmp/instagram-931/invite-regression-after.json`.
- Após erro pré-transporte: zero POST e claim removido; restaurar snapshot
  permite um convite; repetir com papel ainda ausente não gera segundo POST.
- Resposta perdida/cancelamento no transporte: um POST e `unknown` conservado;
  tentativa posterior não repete. TTL inicial observado: 86400 segundos.
- Gerações novas `unknown` e `pending` sobrevivem à limpeza da tentativa antiga.
- Falhas sintéticas na persistência, leitura e limpeza do Redis são reportadas.
- Rejeição booleana explícita permite nova tentativa; código isolado e payload
  contendo erros não removem a proteção. Chamada direta sem bloco preservada.
- Compilação sintática Ruby dos sete arquivos de código/spec: aprovada via
  `RubyVM::InstructionSequence.compile_file` com Ruby 3.4.4 e gems desativadas.
- `git diff --check` para esses sete arquivos: aprovado.

## Limites e entrega

RSpec/Rails, RuboCop e testes com Redis real não executados nesta rodada. O
brief reserva banco/socket ao coordenador. Specs foram adicionados para sua
execução isolada: `client_spec.rb`, `invitation_spec.rb` e
`invitation_outcome_spec.rb`; `client_spec.rb` também contém testes preexistentes
de proxy loopback. Não afirmar equivalência entre fixture e Redis/Meta reais.

Implementação entregue para review independente e integração pelo coordenador.
Sem commit, push, merge ou deploy. Não é declaração de produção pronta.

## Atualização — correção do lint informado pelo coordenador

Lido `tmp/instagram-931/ruby-lint.log`. Corrigidos apenas `client.rb`
(forwarding anônimo `&` na assinatura e na chamada) e `invitation_spec.rb`
(alinhamento de `.and_raise`). Nenhuma supressão ou configuração alterada.
O diff após autoformat foi lido: sinal imediatamente anterior a HTTParty,
proteção das gerações e `write_rejected` permanecem iguais.

Validações via `tmp/instagram-931/run-local.sh`, usando dependências existentes:

```sh
tmp/instagram-931/run-local.sh bundle exec rubocop -a --cache false --only Naming/BlockForwarding,Layout/MultilineMethodCallIndentation app/services/instagram/testers/client.rb spec/services/instagram/testers/invitation_spec.rb
tmp/instagram-931/run-local.sh bundle exec rubocop --cache false app/services/instagram/testers/client.rb app/services/instagram/testers/error.rb app/services/instagram/testers/invitation.rb app/services/instagram/testers/invitation_outcome.rb spec/services/instagram/testers/client_spec.rb spec/services/instagram/testers/invitation_spec.rb spec/services/instagram/testers/invitation_outcome_spec.rb
tmp/instagram-931/run-local.sh ruby --disable-gems tmp/instagram-931/invite-regression.rb
```

- Autoformat restrito: dois arquivos inspecionados, três ocorrências corrigidas,
  exit 0. Diferença deste ajuste: duas linhas de forwarding e um alinhamento.
- RuboCop completo da propriedade: **sete arquivos, nenhuma infração**, exit 0.
- Regressões depois do ajuste: **19 aprovadas, zero falhas**, exit 0.
- `git diff --check` nos dois arquivos corrigidos: aprovado.
- O coordenador informou que os specs passaram no RSpec parent. Essa execução
  não foi repetida pelo especialista nesta correção de lint.

Nenhum socket ou teste de snapshot executado nesta atualização. Sem alterações
em arquivos de outros especialistas, rede externa, commit, push ou deploy.
