# bin/demo escolhe a máquina da demo (#2965)

Data: 12/11/2026. Só demo local: nada aqui toca produção.

## Decisões

- **Fonte da medição**: `maccluster status --json`, campos `metrics.load1`, `metrics.memory_available_gb` e
  `metrics.telemetry.swapout_rate` (bytes por segundo, convertido para MiB/s). São os mesmos números que o
  `maccluster status` mostra em texto. Lido com o parser de JSON do Python, sem recortar texto.
- **Limites** (regra do Rodrigo): carga abaixo de 20, memória livre acima de 3 GB, swap-out abaixo de 1 MiB/s
  ("perto de 0"). Valor igual ao limite não serve.
- **Desempate**: mais memória livre; empate exato fica com o `m2`. Motivo: foi memória que faltou no M2 em 12/11.
- **Demo viva**: demo registrada (`demo.env`) com Rails, Vite ou Redis escutando. Redis sozinho conta, porque é o
  primeiro a subir num `up` em andamento. Limite de 1, somando as duas máquinas.
- **Onde a demo está**: não há arquivo novo de estado. O kit procura o `demo.env` da demo nas duas máquinas.
- **Forçar**: variável `DEMO_MAQUINA=m2|m4`, com as mesmas recusas. Não existe opção para furar o limite.
- **Demo no mesmo Mac do `bin/demo`**: roda direto, sem ssh, com ambiente limpo (`env -i`), em cima do snapshot do
  MacCluster, sem cópia.
- **`sync` não religa demo desligada**: senão ele ligaria servidor sem medir a máquina.
- O nome `no_m2.sh` e o marcador `apagado-no-m2` ficaram: demos antigas dependem deles.

## Conferido no M4, só leitura

- Postgres de teste em `127.0.0.1:55432`: servidor 16.15, `fsync=off`, uma role só (`postgres`). Bancos de outras
  frentes presentes: `chatwoot_test`, 67 `chatwoot_test_<algo>` (entre eles `chatwoot_test_2881`), 23
  `chat2you_test_<algo>`, 38 `chatwoot_ag_<algo>` e `chatwoot_frente4`. O kit só cria e apaga
  `chatwoot_kitdemo_<slug>` e a role `kitdemo_<slug>`: nenhum desses nomes colide.
- Já existe no M4 um banco `chatwoot_kitdemo_2776_vitrine` sem demo registrada (não há pasta de demos no M4). O
  kit recusa esse slug ("banco já existe sem demo registrada") e não o apaga. Não mexi nele.
- Redis de teste em `127.0.0.1:56379`: em uso (db 9). O kit não o usa: cada demo sobe o seu, em `57400–57599`.
- Cliente do Postgres: o M4 não tem `maccluster-tools/postgresql-17.11`, só `deps/postgresql-16.15`. O kit passou a
  usar o 16.15 quando o 17.11 não existe. No M2 nada muda.
- Ruby, Node, Redis e corepack do MacCluster existem no M4. `bundle check` com o `Gemfile.lock` da `main`:
  dependências satisfeitas. `pnpm` do corepack, sem rede: 10.2.0, a versão do `package.json`.
- Chrome instalado (os prints usam o canal `chrome`).
- Nenhum snapshot com `node_modules` no M4: o primeiro `pnpm install` de uma demo lá traz tudo.
- Na faixa de portas do kit, neste Mac, estão ocupadas a 5000 (sistema) e túneis ssh antigos (4760, 4762, 5088,
  5090). Slug que cair numa delas é recusado pelo `checar` ("porta ocupada").

## Validação

| O quê | Resultado |
|---|---|
| `bash -n` em `bin/demo`, `no_m2.sh`, `vivas.sh`, `comum.sh` | sem erro |
| `shellcheck -x` nos três arquivos tocados | sem aviso |
| Escolha de máquina com medições e máquinas simuladas (22 casos: desempate, limites exatos, nenhuma serve, máquina muda, outra demo viva, forçada, já registrada) | saída conferida caso a caso |
| `bin/demo maquinas` de verdade (só leitura, nas duas máquinas) | mediu as duas e listou 1 demo viva no M2 (só o Redis) |
| `bin/demo status` de uma demo que existe no M2 e de um slug que não existe | achou a máquina (`MAQUINA=m2`); recusou o que não existe |
| `DEMO_MAQUINA` inválida e forçada na máquina errada | recusou |

## Não verificado (exigiria subir demo, o que a regra proíbe sem OK)

- Um `up` inteiro, em qualquer das duas máquinas, com o kit novo.
- Demo rodando no M4: `pnpm install` do zero, `schema:load`, Rails e Vite em cima do snapshot, prints com o Chrome do
  M4, `sync` e `down --apagar` no caminho sem ssh.
- Se os servidores lançados sem ssh continuam vivos depois que o comando que os lançou termina.
- `sync`, `seed`, `flag`, `prints`, `psql` e `down` depois da troca de `ssh` direto pela função `remoto` (o `status`,
  que usa o mesmo caminho, foi exercitado).

## Bloqueios

Nenhum para o PR. Para um `up`: há uma demo viva no M2 (`2198-criar`, só o Redis) e, na hora da medição, as duas
máquinas estavam fora do limite.

## Revisão independente (12/11/2026)

Revisor leu os arquivos inteiros. Nenhum achado crítico ou alto.

Ajustado neste PR:

- descarte do snapshot de um `up` falho, com a demo neste Mac, só acontece se a demo não ficou registrada;
- `USER` ausente no ambiente não derruba o comando;
- runbook: o `sync` com a demo desligada ainda roda `pnpm install` e `db:migrate` (tarefas que terminam), mas não
  liga servidor; "recusa" no lugar de "avisa" na colisão de porta; de onde o snapshot é tirado; qual snapshot o
  `down --apagar` apaga.

Conferido: `swapout_rate` é bytes por segundo (`memory_stats.py` do MacCluster).

Já existia antes deste PR e ficou de fora (candidato a Issue própria):

- snapshot do MacCluster sobra se o `up` falha entre a criação e o registro para descarte (`criar_snapshot`);
- `clonar-base` que falha antes do rsync deixa o `clone-pendente` preso, e o `up` seguinte da mesma demo recusa;
- o snapshot do Mac que chamou o `up` só é apagado por um `down --apagar` rodado nesse mesmo Mac;
- `SNAP` do `demo.env` entra entre aspas simples num comando remoto do `sync`.

Limite conhecido, coberto pela regra do OK da Orquestração: dois `up` disparados ao mesmo tempo. A demo só conta
como viva quando o Redis dela sobe; antes disso (snapshot, cópia) o segundo `up` não a vê.

Mudança de dependência: todo comando passou a chamar `maccluster node` para saber em qual Mac está. Antes, só o
`up` dependia do MacCluster.

## Primeiro `up` real no M4 e o conserto (12/11/2026)

O primeiro `up` com o kit novo foi no M4 (demo `2881-modelos`, relato da Orquestração Deploy). Passou por
snapshot, `pnpm install`, banco e Rails, e parou no Vite: `bundler: command not found: vite`.

**Causa raiz.** O Ruby compartilhado do MacCluster guarda um lançador por executável de gem em `ruby-3.4.4/bin`.
Medido em 12/11: 27 arquivos no M4, 79 no M2. As gems estão instaladas no M4 (o `bundle check` passa), mas sem os
lançadores; faltam, entre outros, `vite`, `puma` e `rackup`. O `bundle exec vite` procura o lançador no `PATH` e não
acha. Mesmo mecanismo conferido com outro lançador que falta: `bundle exec puma --version` devolve
`bundler: command not found: puma`.

**Por que a conferência só por leitura não pegou.** O `bundle check` confere gems instaladas, não lançadores.

**Mitigação que já aconteceu** (autorizada pela Orquestração a outra frente): `gem pristine vite_ruby
--only-executables` no M4. O lançador `vite` apareceu às 17:20 (horário local); os outros continuam faltando.

**Conserto no kit** (este PR):

- Rails e Vite sobem por `ruby bin/rails` e `ruby bin/vite`, os binstubs do próprio app, em vez de
  `bundle exec rails|vite`. O binstub carrega o Bundler e acha o executável dentro da gem. O kit deixa de depender
  de qualquer lançador de gem. Dentro de um app, o lançador `rails` já termina executando o `bin/rails`.
- `script/demo/ferramentas.sh`: um lugar só para os caminhos das ferramentas que o kit executa, com a lista das que
  faltam. O `maquinas` e o `up` conferem cada máquina e não mandam demo para onde falta ferramenta.
- O kit **não** gera lançador no Ruby compartilhado: esse Ruby também serve aos testes do MacCluster, e mexer nele
  é do instalador do MacCluster.

**Validação.**

| O quê | Resultado |
|---|---|
| `bash -n` e `shellcheck -x` em `bin/demo`, `no_m2.sh`, `vivas.sh`, `ferramentas.sh` | sem erro e sem aviso |
| Releitura do diff | pegou um erro da troca em lote (`bin/railsdb:schema:load`, sem espaço) que `bash -n` e `shellcheck` não acusam; corrigido |
| M4, ambiente igual ao da demo: `ruby bin/rails --version` | `Rails 7.2.3.1` |
| M4, ambiente igual ao da demo: `ruby bin/vite --help` | lista os comandos do Vite |
| `ferramentas.sh` pelo stdin, no M4 e no M2 | nenhuma falta nas duas |
| `bin/demo maquinas` de verdade | mediu as duas, ferramentas completas, 1 demo viva no M4 |
| Escolha de máquina com faltas simuladas (9 casos, com regressão dos anteriores) | saída conferida caso a caso |

**Não verificado** (exigiria subir demo): `ruby bin/rails s`, `db:schema:load`, `runner` e `ruby bin/vite dev` de
verdade, em qualquer das duas máquinas. No M2 nem o `--version` foi rodado: os snapshots de lá são de outras
frentes e o comando grava cache dentro deles.
