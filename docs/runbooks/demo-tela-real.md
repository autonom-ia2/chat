# Demo em tela real (`bin/demo`)

O Rodrigo aprova cada tela vendo o painel de verdade: os componentes Vue do próprio fork, atrás de uma flag e com
dados de um adaptador falso, rodando no M2. Este kit sobe esse painel a partir da worktree em um comando, tira os
prints por jornada e limpa tudo no fim. Substitui as cópias de `env.sh`/`sync.sh` que cada sessão montava à mão (#2140).

Só demo local. Nada aqui fala com produção, AWS, SSM ou banco de produção. Nenhum segredo fica no kit: as chaves
da demo (`SECRET_KEY_BASE`, chaves do Active Record Encryption) são geradas na hora, ficam só no M2, dentro da
pasta da demo, e somem no `down --apagar`. A senha do login vem do `db/seeds.rb` do próprio repositório.

## Resumo

Rode no **M4**, de dentro da worktree da entrega:

```sh
bin/demo up 2079-instagram          # snapshot, banco, seed, Rails + Vite no M2 (1a vez: ~3 a 5 min)
bin/demo flag 2079-instagram crm      # liga a flag na conta 1 (ou: ... <flag> <conta>)
bin/demo seed 2079-instagram docs/x/seed_demo.rb   # dados do caso (rails runner no banco da demo)
bin/demo tunnel 2079-instagram      # comando de túnel e URL para abrir no M4
bin/demo sync 2079-instagram        # depois de editar: leva só o que mudou
bin/demo prints 2079-instagram docs/x/jornadas.json   # PNGs em 1440 e 390 em docs/<pasta>/
bin/demo down 2079-instagram        # desliga os servidores (banco e snapshot ficam)
bin/demo down 2079-instagram --apagar   # apaga banco, snapshot (M2 e M4) e a pasta da demo
```

Outros: `bin/demo status <slug>` (portas, banco, snapshot) e `bin/demo psql <slug> "SQL"` (roda um SQL só no banco da demo, sem `psqlrc`; meta-comando como `\c` ou `\!` é recusado).

O **slug** usa minúsculas, dígitos e hífen (até 30 caracteres). Use o número da Issue e um nome curto.

## O que cada comando faz

| Comando | Onde | O que faz |
|---|---|---|
| `up` | M4 → M2 | Confere que banco e portas da demo estão livres. Tira o snapshot da worktree no M4 (`maccluster workspace snapshot --local-only`). No M2, clona (APFS, custo ~0) o snapshot chat2you mais recente e leva só a diferença com `rsync --checksum --delete`; depois confere que ficou igual. Grava `demo.env`, gera as chaves, sobe um Redis próprio, roda `pnpm install`, `db:create db:schema:load db:seed`, o `Seeders::AccountSeeder` na conta 1 e põe conta e John em pt-BR. Sobe Vite e Rails e espera o login responder. Rodar de novo só religa. |
| `sync` | M4 → M2 | Copia o que difere do commit do snapshot (alterados, novos, não rastreados) e apaga o que a worktree apagou. Mudou `.rb`, `config/*.yml` ou `lib/`: reinicia só o Rails. Mudou migration: roda `db:migrate` no banco da demo e reinicia. Mudou `pnpm-lock.yaml`: refaz o `pnpm install`. Mudou `Gemfile`: para e pede demo nova. Front puro: o Vite recarrega sozinho. |
| `flag` | M2 | `Account#enable_features!` na conta (1 por padrão). Flag que não existe falha. |
| `seed` | M2 | Copia o `.rb` para a pasta da demo e roda com `rails runner`. `ENV['DEMO_PASTA']` aponta a pasta da demo no M2 (para mídia, por exemplo). |
| `tunnel` | — | Imprime o `ssh -L` das duas portas (Rails e Vite) e a URL. |
| `prints` | M2 → M4 | Roda `script/demo/prints.cjs` com o Playwright do snapshot e o Chrome do M2, contra o painel local. Traz só os PNGs para `docs/<pasta>/` da worktree; o `relato.json` (URLs locais e erros) fica no M2, na pasta da demo. Recusa `pasta` que já tenha arquivo versionado. |
| `down` | M2 (e M4) | Desliga Rails, Vite e Redis da demo, conferindo que o processo roda dentro do snapshot dela. Com `--apagar`: confere o snapshot do M4 (caminho, marcador, `lsof +D`) sem apagar. No M2 confere que só os servidores da demo usam o snapshot **antes** de desligá-los; então desliga, faz `dropdb` do banco e apaga o snapshot, deixando o marcador `apagado-no-m2` e o `demo.env`. Depois apaga o snapshot do M4 e, por último, a pasta da demo no M2. Se o M2 recusar, nada é desligado nem apagado. Se o M4 recusar depois do M2, repetir `down --apagar` termina. |

## Isolamento: o que é de cada demo

- **Pasta**: `/Users/Shared/chat2you-demos/<slug>/` no M2 (`demo.env`, chaves, logs, Redis, `storageState`, prints).
- **Banco**: `chatwoot_kitdemo_<slug>` (hífen vira `_`) no Postgres de teste do M2 (`127.0.0.1:55432`). O `up` recusa
  se o banco já existir sem demo registrada: nunca reaproveita banco de outra demo. Os scripts Ruby do kit recusam
  qualquer banco fora do prefixo `chatwoot_kitdemo_`.
- **Portas**: derivadas do slug (`cksum`): Rails `4400–5196`, Vite = Rails + 2, Redis `57400–57599`. Ficam longe das
  de teste (55432, 56379) e das demos feitas à mão (3301–4025, 56xxx). Se dois slugs caírem na mesma porta, o `up`
  avisa: troque o slug.
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
- **Postgres**: o `127.0.0.1:55432` do M2 é o cluster de teste do MacCluster
  (`/Users/Shared/maccluster-test-services/postgres-chat2you`, com `fsync=off`). Só tem bancos de teste e de demo.
- **`demo.env`**: lido como dado (chave=valor, só chaves conhecidas), nunca executado com `source`.

## Abrir no M4 (túnel)

```sh
bin/demo tunnel <slug>
# imprime algo como:
ssh -f -N -L 5028:127.0.0.1:5028 -L '5030:[::1]:5030' m2
# abrir http://localhost:5028/app/login   (john@acme.inc, senha em db/seeds.rb)
```

As duas portas precisam do túnel: o Rails serve a página e o Vite serve os módulos e o recarregamento. O Vite
escuta em `[::1]` (IPv6), o Rails em `127.0.0.1`.

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
| **Snapshot não chega ao M2** ("réplica pendente: remote_mode") | Com o M2 fora de casa, o MacCluster não replica snapshot (transferência grande). | O kit tira o snapshot só no M4 e monta o do M2 por clone APFS + `rsync` da diferença (em geral poucos MB). |
| **Vite demora na 1a página** | A primeira visita compila o painel. | O `up` espera até 15 min pelo login; o `prints` dá até 5 min por página (`DEMO_TIMEOUT_MS`). |
| **Gem nova** | O Ruby do MacCluster tem as gems do `Gemfile.lock` da `main`. | O `sync` recusa mudança de `Gemfile`; demo que precisa de gem nova não é caso deste kit. |

## Checagem de uso (`lsof +D`)

Antes de apagar um snapshot, o kit confere com `lsof -w -t +D` quem tem arquivo aberto nele (`script/demo/comum.sh`,
o mesmo arquivo nos dois Macs). Indexador do Spotlight e buscas de disco abrem arquivo de passagem: só conta como
em uso se continuar assim em 5 leituras, com 3 s entre elas. Erro do `lsof` (stderr ou saída diferente de 0/1)
para tudo sem apagar; o `lsof` 4.91 do macOS sai com 1 tanto sem nada aberto quanto achando processos.
Medido em 23/10: ~3 s por leitura num snapshot com `node_modules` (89 mil arquivos) no M2, ~2 s no M4.

## Limpeza (obrigatória)

Ao fim da aprovação, na mesma etapa da limpeza da entrega:

```sh
bin/demo down <slug> --apagar
```

Apaga só o que é da demo, pelo nome exato: o banco `chatwoot_kitdemo_<slug>`, o snapshot gravado no `demo.env`
(no M2 e no M4, com `lsof +D` antes, recusa se estiver em uso ou se faltar o marcador do MacCluster) e a pasta
`/Users/Shared/chat2you-demos/<slug>/`. Os PNGs em `docs/` da worktree ficam.

## Arquivos

- `bin/demo` — comando (M4).
- `script/demo/no_m2.sh` — lado M2; o `bin/demo` copia `script/demo/` para a pasta da demo a cada comando.
- `script/demo/comum.sh` — `em_uso` (checagem com `lsof +D`), carregado pelos dois lados.
- `script/demo/preparar_conta.rb`, `ligar_flag.rb` — `rails runner` no banco da demo.
- `script/demo/senha_do_seed.rb` — lê a senha do John no `db/seeds.rb` (parser Prism) para o login dos prints.
- `script/demo/prints.cjs` — prints com Playwright; `exemplo-jornadas.json` — jornada de exemplo.
