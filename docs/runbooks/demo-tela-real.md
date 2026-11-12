# Demo em tela real (`bin/demo`)

O Rodrigo aprova cada tela vendo o painel de verdade: os componentes Vue do próprio fork, atrás de uma flag e com
dados de um adaptador falso, rodando no `m2` ou no `m4`. Este kit sobe esse painel a partir da worktree em um
comando, tira os prints por jornada e limpa tudo no fim. Substitui as cópias de `env.sh`/`sync.sh` que cada sessão
montava à mão (#2140). Desde a #2965 ele escolhe a máquina pela carga, na hora do `up`.

Só demo local. Nada aqui fala com produção, AWS, SSM ou banco de produção. Nenhum segredo fica no kit: as chaves
da demo (`SECRET_KEY_BASE`, chaves do Active Record Encryption) são geradas na hora, ficam só na máquina da demo,
dentro da pasta da demo, e somem no `down --apagar`. A senha do login vem do `db/seeds.rb` do próprio repositório.

## Antes de subir: OK da Orquestração Deploy e escolha da máquina

**Regra do Rodrigo (12/11/2026): antes de qualquer `bin/demo up`, em qualquer máquina, pergunte à sessão
"Orquestração Deploy" e espere o OK dela.** Ela cuida da fila e das máquinas. Em 12/11/2026 uma demo subiu no M2 sem
ninguém ler a carga, e o M2 travou. Leve a ela a saída de `bin/demo maquinas` (só leitura: mede as duas máquinas,
lista as demos vivas e diz para onde um `up` iria).

O kit não substitui essa conversa. Ele só recusa o que a regra já proíbe:

- **Qual máquina.** O `up` lê `maccluster status --json` e só sobe numa máquina **dentro do limite**: carga (load
  de 1 minuto) abaixo de 20, memória livre (a `available` do MacCluster) acima de 3 GB e swap-out abaixo de 1 MiB/s.
  Os três limites ficam no topo do `bin/demo` (`CARGA_MAX`, `RAM_MIN_GB`, `SWAP_MAX_MIB_S`).
- **Ferramentas.** Máquina em que falta alguma ferramenta que o kit executa (Ruby, Node, `pnpm`, cliente do
  Postgres, Redis) não recebe demo, mesmo dentro do limite: o `up` pararia no meio, com banco e snapshot já
  criados. O `maquinas` e o `up` dizem o caminho que falta. A lista fica em `script/demo/ferramentas.sh`.
- **Desempate.** Se `m2` e `m4` servem, ganha a que tem **mais memória livre**: foi memória que faltou em 12/11.
  Empate fica com o `m2` (a comparação usa o número do MacCluster, que vem com uma casa decimal).
- **Nenhuma serve.** O `up` recusa e mostra o que mediu em cada máquina. Não há opção para passar por cima do limite.
- **No máximo 1 demo viva, somando as duas máquinas.** Viva é a demo registrada que tem Rails, Vite ou Redis
  escutando. O `up` recusa se já houver outra e diz qual é, onde está e o que dela está ligado. Redis esquecido
  ligado conta: desligue com `bin/demo down <slug>`. Religar a própria demo não esbarra nela mesma, mas passa pelo
  limite da máquina onde ela mora.
- **As duas máquinas têm de responder no `up`.** Sem falar com uma delas, o kit não tem como afirmar que não há
  demo viva, e recusa.
- **Demo que já existe não muda de máquina.** Banco e pasta moram onde ela nasceu. Para trocar: `down --apagar` e
  `up` de novo.
- **Os outros comandos acham a máquina sozinhos**: procuram o `demo.env` da demo nas duas. `bin/demo status <slug>`
  mostra `MAQUINA=`. Se uma máquina não responde e a demo está na outra, o comando avisa e segue.
- **Forçar a máquina**: `DEMO_MAQUINA=m2 bin/demo up <slug>` (ou `m4`). As mesmas recusas valem: limite da máquina
  e 1 demo viva. Nos outros comandos, `DEMO_MAQUINA` faz o kit olhar só aquela máquina.
- **O `sync` não religa demo desligada.** Ele leva os arquivos, roda `pnpm install` e `db:migrate` se o que mudou
  pedir (tarefas que terminam) e avisa. Servidor nenhum sobe: quem liga é o `up`, que mede a máquina. Com o painel
  ligado, o `sync` reinicia Rails e Vite da própria demo, sem nova medição.

O que o kit **não** vê, e por isso a conversa com a Orquestração continua obrigatória: demo feita à mão (fora de
`/Users/Shared/chat2you-demos`), dois `up` disparados ao mesmo tempo e o que mais está para rodar nas máquinas.

## Resumo

Rode de dentro da worktree da entrega (hoje as sessões ficam no M4):

```sh
bin/demo maquinas                   # só leitura: carga das duas máquinas, demos vivas, para onde o up iria
bin/demo up 2079-instagram          # depois do OK: escolhe m2 ou m4; snapshot, banco, seed, Rails + Vite
bin/demo flag 2079-instagram crm      # liga a flag na conta 1 (ou: ... <flag> <conta>)
bin/demo seed 2079-instagram docs/x/seed_demo.rb   # dados do caso (rails runner no banco da demo)
bin/demo tunnel 2079-instagram      # URL para abrir (e o comando de túnel, se a demo está no outro Mac)
bin/demo sync 2079-instagram        # depois de editar: leva só o que mudou
bin/demo prints 2079-instagram docs/x/jornadas.json   # PNGs em 1440 e 390 em docs/<pasta>/
bin/demo down 2079-instagram        # desliga os servidores (banco e snapshot ficam)
bin/demo down 2079-instagram --apagar   # apaga banco, snapshot (o da demo e o deste Mac) e a pasta da demo
```

Outros: `bin/demo status <slug>` (portas, banco, snapshot e a máquina) e `bin/demo psql <slug> "SQL"` (roda um SQL no banco da demo **como a role da demo**, sem superuser e sem `CREATEDB`: ela não cria nem apaga outro banco e não altera role; sem `psqlrc`; meta-comando como `\c` ou `\!` é recusado).

O **slug** usa minúsculas, dígitos e hífen (até 30 caracteres). Use o número da Issue e um nome curto.

## O que cada comando faz

"Este Mac" é o Mac de onde o `bin/demo` é chamado; "a demo" é a máquina onde ela roda (`m2` ou `m4`). As duas
podem ser a mesma. Os textos abaixo que dizem "no M2" valem para a máquina da demo, qualquer que seja.

| Comando | Onde | O que faz |
|---|---|---|
| `maquinas` | este Mac e as duas máquinas | Só leitura. Mede `m2` e `m4`, confere as ferramentas do kit em cada uma, lista as demos vivas e diz para onde um `up` iria (ou por que seria recusado). |
| `up` | este Mac → a demo | Escolhe a máquina (seção acima) e recusa se houver outra demo viva ou se nenhuma máquina servir. Confere que banco e portas da demo estão livres. Tira o snapshot da worktree neste Mac (`maccluster workspace snapshot --local-only`). Se a demo roda em outro Mac: lá, clona (APFS, custo ~0) o snapshot chat2you mais recente e leva só a diferença com `rsync --checksum --delete`; depois confere que ficou igual. Se roda neste Mac: usa o snapshot no lugar, sem cópia, e o `pnpm install` traz as dependências. Grava `demo.env`, gera as chaves, sobe um Redis próprio, roda `pnpm install`, `db:create db:schema:load db:seed`, o `Seeders::AccountSeeder` na conta 1 e põe conta e John em pt-BR. Sobe Vite e Rails e espera o login responder. Rodar de novo só religa. |
| `sync` | este Mac → a demo | Copia o que difere do commit do snapshot (alterados, novos, não rastreados) e apaga o que a worktree apagou. Mudou `.rb`, `config/*.yml` ou `lib/`: reinicia só o Rails. Mudou migration: roda `db:migrate` no banco da demo e reinicia. Mudou `pnpm-lock.yaml`: refaz o `pnpm install`. Mudou `Gemfile`: para e pede demo nova. Front puro: o Vite recarrega sozinho. Com a demo desligada, leva os arquivos (e roda `pnpm install`/`db:migrate`, se for o caso) e não liga servidor nenhum. |
| `flag` | a demo | `Account#enable_features!` na conta (1 por padrão). Flag que não existe falha. |
| `seed` | a demo | Copia o `.rb` para a pasta da demo e roda com `rails runner`. `ENV['DEMO_PASTA']` aponta a pasta da demo na máquina dela (para mídia, por exemplo). |
| `tunnel` | — | Demo em outro Mac: imprime o `ssh -L` das duas portas (Rails e Vite) e a URL. Demo neste Mac: só a URL, sem túnel. |
| `prints` | a demo → este Mac | Roda `script/demo/prints.cjs` com o Playwright do snapshot e o Chrome da máquina da demo, contra o painel local. Traz só os PNGs para `docs/<pasta>/` da worktree; o `relato.json` (URLs locais e erros) fica na máquina da demo, na pasta da demo. Recusa `pasta` que já tenha arquivo versionado, que passe por link simbólico (ela ou qualquer ancestral até a worktree) ou cujo caminho real saia da worktree. |
| `down` | a demo (e este Mac) | Desliga Rails, Vite e Redis da demo **pela identidade**: cada servidor sobe num grupo de processos próprio; o PGID fica em `pids/<nome>.pgid` e o instante em que o líder nasceu (`ps -o lstart`) em `pids/<nome>.inicio`. O grupo só recebe sinal se o líder ainda existe, nasceu nesse instante e o comando dele é exatamente `/bin/bash <kit>/no_m2.sh _<nome> <slug>` (PGID reaproveitado depois de reboot ou morte não confere: ninguém recebe sinal). Registro que não confere nunca dá OK sozinho: sem mandar sinal, o kit conta os processos vivos do PGID gravado; com zero, apaga o registro e a porta decide; com algum, falha e pede conferência à mão. O `ps` do início roda com `LC_ALL=C TZ=UTC`, ao gravar e ao conferir. Quem escuta na porta fora desse grupo faz o comando falhar sem mexer. Derruba o grupo inteiro e confere, com 30 s de prazo, que a porta parou de escutar e que nenhum processo do grupo sobrou; se não, falha. Com `--apagar`: confere o snapshot do M4 sem apagar; no M2 (a) desce de forma verificada, (b) roda a checagem de uso no snapshot **sem exceção nenhuma** e, se algo ainda o segura, para com "demo parada, nada apagado" (reversível: `up` de novo); (c) só então faz `dropdb` e apaga o snapshot, deixando o marcador `apagado-no-m2` e o `demo.env`. Depois apaga o snapshot do M4 e, por último, a pasta da demo no M2. Com o marcador, todo comando que não seja `down --apagar` ou `status` responde "demo em remoção: rode down --apagar"; repetir `down --apagar` termina. |

## Isolamento: o que é de cada demo

- **Pasta**: `/Users/Shared/chat2you-demos/<slug>/` na máquina da demo (`demo.env`, chaves, logs, Redis,
  `storageState`, prints). É o `demo.env` dessa pasta que diz em qual máquina a demo está.
- **Banco**: `chatwoot_kitdemo_<slug>` (hífen vira `_`) no Postgres de teste da máquina da demo (`127.0.0.1:55432`).
  O `up` recusa se o banco já existir sem demo registrada: nunca reaproveita banco de outra demo. Os scripts Ruby do
  kit recusam qualquer banco fora do prefixo `chatwoot_kitdemo_`.
- **Bancos dos outros (M2 e M4)**: o mesmo Postgres guarda o `chatwoot_test` de uso comum e os bancos isolados de
  outras frentes (`chatwoot_test_<algo>`, `chat2you_test_<algo>`, `chatwoot_ag_<algo>`). O kit não lê, não usa e não
  apaga nenhum deles: só cria e apaga o banco `chatwoot_kitdemo_<slug>` e a role `kitdemo_<slug>` da própria demo,
  pelo nome exato. O Redis de teste (`127.0.0.1:56379`) também fica de fora: cada demo sobe o seu, em porta própria.
- **Role**: `kitdemo_<slug>` (hífen vira `_`), `LOGIN` sem `SUPERUSER`, `CREATEDB` nem `CREATEROLE`, dona do banco da
  demo. O Rails, os `rails runner` e o `bin/demo psql` entram com ela. Só o kit usa o `postgres`: cria a role, o banco
  (`createdb -O`) e as extensões do `db/schema.rb` (algumas exigem superuser; o `schema:load` depois só acha "já
  existe"), e no `down --apagar` faz `dropdb` e `DROP ROLE`. Antes de apagar qualquer coisa, o `apagar` confere que a
  role, se existir, não tem superuser, `CREATEDB` nem `CREATEROLE`; senão para sem apagar nada. O `up` recusa se a
  role já existir sem demo registrada.
- **Portas**: derivadas do slug (`cksum`): Rails `4400–5196`, Vite = Rails + 2, Redis `57400–57599`. Ficam longe das
  de teste (55432, 56379) e das demos feitas à mão (3301–4025, 56xxx). Se dois slugs caírem na mesma porta, o `up`
  recusa: troque o slug.
- **Snapshot**: um por demo, em `/Users/Shared/maccluster-workspaces/chat2you/<id>/src`, com o mesmo caminho no M2 e
  no M4. O `sync` reaproveita; snapshot novo só com outro `up` (outra demo). Cada `maccluster workspace snapshot` cria
  um diretório novo (o id leva data, hora, HEAD, hash do conteúdo e um uuid); o `up` confere no manifesto que o
  snapshot é desta worktree, e o `down --apagar` só apaga o caminho gravado no `demo.env`.
- **Sem segredo no snapshot**: o snapshot do MacCluster leva os arquivos versionados e os não rastreados que o
  `.gitignore` não ignora (`git ls-files` + `git ls-files -o --exclude-standard`), e tira os sensíveis (`.env`,
  `.env.*`, pastas `secrets`/`credentials`, chaves). Ignorados não entram. O clone base do M2 perde `.env*`,
  `config/credentials*` e `config/master.key` antes de qualquer boot (o `dotenv-rails` leria um `.env` herdado), e
  o `preparar` confere de novo e recusa subir se achar um.
- **Ambiente**: `env -i` com Ruby e Node de `/Users/Shared/maccluster-tools`, `RAILS_ENV=development`,
  `DISABLE_MINI_PROFILER=1`. Nada sai para fora: `WHATSAPP_CLOUD_BASE_URL` e o SMTP (`SMTP_ADDRESS=127.0.0.1`,
  `SMTP_PORT=9`) apontam para uma porta morta. Sem `SMTP_ADDRESS` o Rails usaria `sendmail`, que entrega de verdade.
  O Sidekiq não roda na demo: job enfileirado não executa.
- **Postgres**: o `127.0.0.1:55432` de cada Mac é o cluster de teste do MacCluster
  (`/Users/Shared/maccluster-test-services/postgres-chat2you`, servidor 16.15, com `fsync=off`). Só tem bancos de
  teste e de demo. O cliente (`psql`, `createdb`, `dropdb`) é o 17.11 no M2 e o 16.15 no M4, que não tem o 17.11
  (medido em 12/11/2026); o kit usa o que achar, nessa ordem.
- **Demo no mesmo Mac do `bin/demo`** (hoje, o M4): não há cópia nem túnel. A demo roda em cima do snapshot que o
  MacCluster acabou de tirar, e o `down --apagar` apaga esse snapshot uma vez só. O primeiro `up` de verdade no M4
  (12/11/2026) passou por snapshot, `pnpm install`, banco e Rails, e parou no Vite: ver "Lançador de gem que falta"
  nos tropeços. `sync`, prints e `down --apagar` neste caminho ainda não foram exercitados.
- **Rails e Vite pelos binstubs do app**: o kit sobe os dois com `ruby bin/rails` e `ruby bin/vite`, de dentro do
  snapshot, e não com `bundle exec rails|vite`. O binstub carrega o Bundler e acha o executável dentro da gem; o
  `bundle exec` procura o lançador da gem no `bin/` do Ruby compartilhado, que pode não ter todos.
- **`demo.env`**: lido como dado (chave=valor, só chaves conhecidas), nunca executado com `source`. Portas têm de
  ser numéricas e `SNAP` tem de ser `/Users/Shared/maccluster-workspaces/chat2you/<id>/src`; senão todo comando para.
- **Chaves**: `SECRET_KEY_BASE` e as três do Active Record Encryption ficam em `chaves/` (0600) e nunca passam pelo
  argv (que qualquer usuário vê no `ps`): um `bash` intermediário lê cada arquivo e exporta no próprio ambiente, que
  o Rails herda. Arquivo ausente ou vazio para tudo.
- **Clone pendente**: o `clonar-base` grava `clone-pendente` com o caminho do snapshot que está criando no M2. Se o
  `up` falhar antes de registrar a demo, o `descartar-snapshot` só apaga esse mesmo caminho, e só se o marcador do
  MacCluster dele tiver `snapshot_id` igual ao nome do diretório (o `apagar` e o M4 conferem o mesmo marcador). Um
  clone pendente por demo: o `clonar-base` recusa se já houver outro.
- **Up que falha no meio**: qualquer falha depois de o snapshot ser criado e antes de a demo ficar registrada
  (clone, `rsync`, conferência, lista do sync, `iniciar`) descarta o snapshot nos dois Macs, pelo mesmo caminho.
- **Senha do login**: lida do `db/seeds.rb`, gravada em `chaves/senha_seed` (0600) e lida pelo `prints.cjs` desse
  arquivo; nunca vai no argv nem no ambiente.
- **Caminhos**: todo caminho de snapshot tem de ser `/Users/Shared/maccluster-workspaces/chat2you/<id>`, com `<id>`
  sem `/` e sem começar por `.` (nem `.` nem `..`); a `pasta` dos prints não pode ter componente começando por `.`.
- **Prints**: chegam do M2 num temporário; só arquivo comum e pasta passam (link, socket etc. param o comando), e
  só são copiados para `docs/<pasta>` se não houver link simbólico nela, nos ancestrais nem dentro dela.

## Abrir o painel (túnel)

```sh
bin/demo tunnel <slug>
# demo no outro Mac: imprime algo como
ssh -f -N -L 5028:127.0.0.1:5028 -L '5030:[::1]:5030' m2
# abrir http://localhost:5028/app/login   (john@acme.inc, senha em db/seeds.rb)
```

As duas portas precisam do túnel: o Rails serve a página e o Vite serve os módulos e o recarregamento. O Vite
escuta em `[::1]` (IPv6), o Rails em `127.0.0.1`. Com a demo no mesmo Mac, o comando imprime só a URL: não há túnel.
Túnel antigo esquecido aberto ocupa a porta neste Mac; se a demo nova cair na mesma porta, o `up` avisa "porta
ocupada". Feche o túnel (`pkill -f 'ssh -f -N -L <porta>:'`) e repita.

## Prints por jornada

`bin/demo prints <slug> <jornadas.json>`. Exemplo pronto em `script/demo/exemplo-jornadas.json` (login → caixa de
entrada → todas as conversas):

```json
{
  "pasta": "docs/2079-instagram/prints",
  "conta": 1,
  "larguras": [1440, 390],
  "temas": ["light"],
  "jornadas": [
    {
      "nome": "entrar-e-caixa",
      "etapas": [
        { "nome": "login", "url": "/app/login", "sem_login": true, "esperar": "input[type=\"password\"]" },
        { "nome": "caixa-de-entrada", "url": "/app/accounts/{conta}/dashboard", "esperar": ".conversations-list-wrap", "pausa": 4000 },
        { "nome": "todas-as-conversas", "passos": [{ "clicar": "a:has-text(\"Todos\")" }], "pausa": 3000 }
      ]
    }
  ]
}
```

- `pasta` precisa começar com `docs/` e não pode ter arquivo versionado. Os PNGs saem em
  `docs/<pasta>/<jornada>/<NN>-<etapa>-<tema>-<largura>.png`. O `relato.json` fica no M2
  (`/Users/Shared/chat2you-demos/<slug>/relato.json`): tem URL local e erro, não vai para o repositório público.
- `larguras`: só `1440` e `390`. `temas`: só `light` e `dark`.
- Etapa: `url` (opcional; `{conta}` é trocado), `passos` (`clicar`, `preencher: [seletor, texto]`, `tecla`,
  `esperar`, `pausa`), `esperar` (seletor que precisa aparecer), `pausa` (ms, padrão 1500), `sem_login` (aba
  anônima, para a tela de login ou página pública) e `pagina_inteira`.
- Etapas da mesma jornada continuam na mesma aba: dá para encadear cliques.
- Nomes de jornada e etapa: minúsculas, dígitos e hífen.
- O relato lista, por etapa, respostas `>= 400`, erros de página e rolagem lateral. Etapa que falha (seletor que
  não apareceu, clique que não deu) ou que recebe resposta 5xx faz o comando sair com erro.
- Olhe **todos** os PNGs antes de mandar ao Rodrigo.

## Tropeços conhecidos e a solução

| Tropeço | Por quê | Solução no kit |
|---|---|---|
| **Login repetido dá 409** e o `waitForURL` estoura | O fork limita sessões por usuário; cada login novo de navegador abre o seletor de sessões (409). | O `prints` loga **uma vez** e guarda o `storageState` em `estado-<usuario>.json` na pasta da demo; as rodadas seguintes reaproveitam (o log diz "reaproveitando"). Se ainda assim travar: `bin/demo psql <slug> "DELETE FROM user_sessions"` (só no banco da demo) e rode de novo. |
| **Áudio sem arquivo dá 500** em `audio_metadata` | O recebimento real sempre anexa o arquivo; seed que cria `Attachment` de áudio só com `external_url` quebra a leitura da conversa. | No seed da demo, anexe o arquivo de verdade (`attachment.file.attach(io: File.open(...), filename:, content_type:)`). Ponha a mídia em `ENV['DEMO_PASTA']` no M2. O `prints` acusa o 5xx. |
| **Miniatura quebra sem vips** | `representations`/variantes do Active Storage precisam do libvips, que o M2 não tem. | Não use `thumbUrl` como fonte principal da imagem no protótipo; use a URL do arquivo e deixe a miniatura como melhoria. Não instale vips só para a demo. |
| **Selo do rack-mini-profiler nos prints** | Em development o profiler injeta o selo no canto da tela. | A demo sobe com `DISABLE_MINI_PROFILER=1` (o initializer respeita). O `prints` ainda injeta CSS que esconde `.profiler-results`. |
| **`?demo=vazio`** | O protótipo usa um adaptador falso de dados; o Rodrigo precisa ver também a tela sem dados. | Convenção do adaptador: `?demo=vazio` na URL devolve a lista vazia. Faça uma etapa para cada estado (`/app/accounts/{conta}/minha-tela` e `...?demo=vazio`). A flag só liga rota e menu. |
| **Snapshot não chega ao M2** ("réplica pendente: remote_mode") | Com o M2 fora de casa, o MacCluster não replica snapshot (transferência grande). | O kit tira o snapshot só no Mac de onde é chamado e monta o do outro por clone APFS + `rsync` da diferença (em geral poucos MB). |
| **Vite demora na 1a página** | A primeira visita compila o painel. | O `up` espera até 15 min pelo login; o `prints` dá até 5 min por página (`DEMO_TIMEOUT_MS`). |
| **Lançador de gem que falta** ("bundler: command not found: vite") | O Ruby compartilhado do MacCluster guarda um lançador por executável de gem em `ruby-3.4.4/bin`. Em 12/11/2026 o do M4 tinha 27 e o do M2, 79: as gems estavam instaladas no M4, mas sem os lançadores (entre eles `vite`, `puma`, `rackup`). O `bundle exec vite` não achou o comando. | O kit não usa mais lançador de gem: chama `ruby bin/rails` e `ruby bin/vite` do próprio app. Os lançadores que faltam no M4 são assunto do instalador do MacCluster, não do kit. |
| **Gem nova** | O Ruby do MacCluster tem as gems do `Gemfile.lock` da `main`. | O `sync` recusa mudança de `Gemfile`; demo que precisa de gem nova não é caso deste kit. |

## Checagem de uso (`lsof +D`)

Antes de apagar um snapshot, o kit confere com `lsof -t +D` quem tem arquivo aberto nele (`script/demo/comum.sh`,
o mesmo arquivo nos dois Macs). "Livre" exige **5 leituras vazias seguidas**, com 1 s entre elas; leitura com PID
(indexador do Spotlight, busca de disco) zera a contagem. Passando de 20 leituras sem a sequência limpa, é "em uso".
O `lsof` roda **sem `-w`** (nenhum aviso escondido): qualquer linha no stderr conta como "em uso" (e, na checagem de
porta, como "porta ocupada"); saída acima de 1 ou falha do `mktemp` para tudo. Nunca vira "livre". O `lsof` 4.91 do
macOS sai com 1 tanto sem nada aberto quanto achando processos, por isso quem decide é saída vazia com stderr vazio.

Medição de 23/10 com os mounts atuais (os dois Macs: 11 volumes `apfs` locais, 1 `autofs`, 1 `devfs`; nenhum
volume de rede ou externo):

| Mac | Alvo | Código | stderr |
|---|---|---|---|
| M2 | `+D` snapshot chat2you com `node_modules` | 1 | 0 bytes |
| M2 | `+D` pasta vazia | 1 | 0 bytes |
| M2 | porta ocupada (55432) / livre (5999) | 0 / 1 | 0 bytes |
| M4 | `+D` `node_modules` da worktree (~1,6 s) | 1 | 0 bytes |
| M4 | `+D` pasta vazia | 1 | 0 bytes |
| M4 | porta ocupada (55432) / livre (5999) | 0 / 1 | 0 bytes |

Sem aviso benigno a tolerar. O que costuma fazer o `lsof` avisar é volume que não responde (rede caída, disco
externo ejetado à força, `autofs` pendurado). Se o kit parar com "lsof avisou" ou "lsof falhou ou avisou na porta":

```sh
/usr/sbin/lsof -t +D <caminho> ; echo "saída $?"   # veja o aviso inteiro (ou -iTCP:<porta> -sTCP:LISTEN)
/sbin/mount                                       # ache o volume citado no aviso
diskutil unmount force <volume>                   # só volume externo/de rede que você reconhece; nunca o do sistema
```

Repita o comando do kit depois que o `lsof` sair sem stderr. Não contorne com `-w`.

**Outros usuários.** O `lsof` sem root só enxerga processos do próprio uid. Levantamento de 23/10: no M2 e no M4 há
um único usuário humano (uid 501: `rodrigovictor` no M2, `rodrigosilva` no M4); os outros uids com processo são
contas de sistema (`_spotlight`, `_mdnsresponder` etc.) e root. Em `/Users/Shared`, os processos com caminho no
comando são do uid 501, mais 3 `login` de root no M2 que só abrem sessão para o mesmo usuário (demos feitas à mão).
Por isso o kit exige, antes de apagar, que o snapshot seja **do usuário atual e com modo 700** (o `up` fecha o do M4
em 700 e o `rsync -a` leva o modo ao M2): nenhum outro uid comum abre arquivo lá dentro. Root não é provável sem
`sudo` e fica fora da checagem; se houver dúvida (Time Machine, antivírus), espere o processo de root terminar.

## Demo de kit antigo

Demo subida por uma versão anterior do kit não tem `pids/<nome>.pgid` (kit antes do grupo de processos) ou tem o
`.pgid` sem `pids/<nome>.inicio` (kit antes da conferência do início). O kit não tem como provar que o processo é
dela e **recusa** `down`, `up` e `reiniciar-*` com a mensagem "versão anterior do kit". Para parar à mão, no M2
(`ssh m2`), com as portas do `demo.env` (`/Users/Shared/chat2you-demos/<slug>/demo.env`):

```sh
lsof -nP -iTCP:<RAILS_PORT> -sTCP:LISTEN    # PID do Rails; repita com VITE_PORT
ps -o pid,pgid,lstart,command -p <pid>      # confira que o comando roda dentro do snapshot da demo (SNAP)
kill -TERM <pid>                            # e espere a porta parar de escutar (lsof sem saída)
rm /Users/Shared/chat2you-demos/<slug>/pids/<nome>.pgid   # se existir
```

Depois, `bin/demo up <slug>` religa já no formato novo, e `bin/demo down <slug> --apagar` apaga normalmente.

## Limpeza (obrigatória)

Ao fim da aprovação, na mesma etapa da limpeza da entrega:

```sh
bin/demo down <slug> --apagar
```

Apaga só o que é da demo, pelo nome exato: o banco `chatwoot_kitdemo_<slug>`, o snapshot gravado no `demo.env`
(no M2 e no M4, com `lsof +D` antes, recusa se estiver em uso ou se faltar o marcador do MacCluster) e a pasta
`/Users/Shared/chat2you-demos/<slug>/`. Os PNGs em `docs/` da worktree ficam.

## Arquivos

- `bin/demo` — comando (roda neste Mac, de dentro da worktree).
- `script/demo/no_m2.sh` — lado da máquina da demo (`m2` ou `m4`; o nome é de quando só havia o M2); o `bin/demo`
  copia `script/demo/` para a pasta da demo a cada comando.
- `script/demo/vivas.sh` — lista as demos vivas de uma máquina (só leitura); vai pelo stdin, sem deixar pasta nela.
- `script/demo/ferramentas.sh` — onde ficam as ferramentas que o kit executa e a lista das que faltam; o `no_m2.sh`
  carrega, e o `bin/demo` manda pelo stdin para conferir cada máquina.
- `script/demo/comum.sh` — `em_uso` (checagem com `lsof +D`), carregado pelos dois lados.
- `script/demo/preparar_conta.rb`, `ligar_flag.rb` — `rails runner` no banco da demo.
- `script/demo/senha_do_seed.rb` — lê a senha do John no `db/seeds.rb` (parser Prism) para o login dos prints.
- `script/demo/extensoes.rb` — lista as extensões do `db/schema.rb`, que o kit cria como `postgres`.
- `script/demo/prints.cjs` — prints com Playwright; `exemplo-jornadas.json` — jornada de exemplo.
