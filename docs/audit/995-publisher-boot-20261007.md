# #995 / PR #1112 — boot do publisher Instagram

Registro da medição de transporte e da correção mínima do processo Ruby do
publisher. As execuções foram diagnósticos de leitura, sem publicação de
sessão, alteração de banco, mudança de infraestrutura ou instalação de
release.

## Medição

As três execuções usaram o mesmo alvo CURRENT, conta financeira, tags, comando
`AWS-RunShellScript`, container e bootstrap `session/bootstrap`. O resultado
remoto foi sanitizado para SHA do runtime, tempos e presença booleana da versão.

| Execução | Rails boot | executor + bootstrap | versão presente |
|---|---:|---:|---|
| Baseline | 9.958,109 ms | 7,468 ms | não |
| Controle baseline | 10.172,046 ms | 7,340 ms | não |
| Candidato publisher sem eager load | 5.210,030 ms | 23,271 ms | não |

O controle posterior limita a hipótese de que só aquecer o processo/cache
explique a melhoria; três medições não garantem latência universal. O candidato
reduziu o boot em aproximadamente 4,75 s contra o baseline inicial e 4,96 s
contra o controle. O custo do executor continuou na ordem de dezenas de
milissegundos; o ganho está no eager load da aplicação.

Recibos sanitizados:

- `.codex/rails-phases-baseline-20261007.json` — SHA-256
  `d75e45409fb8384d7e04578704a02fdeab6e1f6b1520487a79fd0d833329cdb8`;
- `.codex/rails-phases-baseline-control-20261007.json` — SHA-256
  `6123e2b3e9aae412fe6f862b8ccd72684ef10e8d9887f47c703983d778d50326`;
- `.codex/rails-phases-eager-off-20261007.json` — SHA-256
  `c19fb50d36a9889d3afdbec72589e95430e4c916cb1b923b336242365d225e34`.

O runtime medido foi o mesmo SHA público
`7aaa19ce04dec6aef3310ec4b4e77b76d7c00d01`. Nenhum recibo contém identidade,
ID de instância, payload, saída Rails, credencial ou resposta de cliente.

## Correção

Rails/Railties `7.2.3.1` está fixado em `Gemfile.lock`. A fonte local de
Railties documenta o ciclo `before_initialize` antes do inicializador
`eager_load!`; o finisher só chama `Zeitwerk::Loader.eager_load_all` quando
`config.eager_load` é verdadeiro.

`scripts/instagram_testers/session_publisher.rb` agora carrega
`config/application`, registra `Rails.application.config.before_initialize` e
define `app.config.eager_load = false` somente nesse processo. Em seguida ele
carrega o `config/environment` normal e mantém `load_runner`,
`executor.wrap`, o protocolo stdin e a supressão de stdout/stderr existentes.
`production.rb`, ENV global, cache, daemon, retry, TTL, CPU e wrapper forçado
permanecem sem alteração.

## Validação local

O teste focal `tests/instagram_testers/session-publisher-stdio.test.mjs`
passou com 19/19 casos. Ele mantém as coberturas de stdin, JSON, limite de
2 MiB, erros de boot/runner/executor/serviço, serialização e logs tardios, e
acrescenta a comprovação de que o toggle ocorre antes da inicialização e não
usa ENV global. `ruby -c scripts/instagram_testers/session_publisher.rb`
também passou.

Esta evidência mede o processo curto e não comprova publicação de sessão,
renovações, persistência após reinício ou conexão do painel. Merge, deploy e
execução produtiva continuam sob aprovação e execução do coordenador.
