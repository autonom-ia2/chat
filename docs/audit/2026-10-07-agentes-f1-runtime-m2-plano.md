# F1 — plano de runtime local isolado no M2

Data: 2026-10-07
Escopo: preparação read-only do runtime para a primeira tela real; nenhum serviço, banco, autenticação,
seed, build, teste ou navegador foi executado nesta etapa.

## Fonte da checagem

A primeira checagem usou o PATH de login e encontrou somente Ruby 2.6.10/Bundler 1.17. Essa leitura era
insuficiente para o piloto. A checagem remota explícita no M2 confirmou os binários compartilhados usados
pelos testes oficiais:

| Recurso | Caminho fixado | Versão confirmada no M2 |
|---|---|---|
| Ruby | `/Users/Shared/maccluster-tools/ruby-3.4.4/bin/ruby` | 3.4.4 |
| Bundler | `/Users/Shared/maccluster-tools/ruby-3.4.4/bin/bundle` | 2.6.7 |
| Node | `/Users/Shared/maccluster-tools/node-v24.11.0/bin/node` | 24.11.0 |
| pnpm/Corepack | `/Users/Shared/maccluster-tools/node-v24.11.0/bin/pnpm`, `corepack` | pnpm 10.2.0, Corepack 0.34.0 |
| PostgreSQL | `/Users/Shared/maccluster-tools/deps/postgresql-16.15/bin` | major 16.15 |
| Redis | `/Users/Shared/maccluster-tools/deps/redis-8.10.2/bin` | 8.10.2 |

O runtime não usa `rbenv`, o PATH de login, Bundler do sistema, Ruby do sistema ou instalação automática.
O `COREPACK_HOME` fica fixado em `/Users/Shared/maccluster-tools/corepack`; Ruby usa
`GEM_HOME`/`GEM_PATH` em `/Users/Shared/maccluster-tools/ruby-3.4.4/lib/ruby/gems/3.4.0`.
Essa confirmação é compatível com o receipt M2 `m2-7d5b51ddbf604f0cb3c13dfaf19ca407` informado para a captura 27;
os caminhos foram conferidos novamente com `maccluster exec --node m2` nesta preparação.

## Runner preparado

`.codex/preview/run-m2.sh` recebe o caminho do snapshot e valida o manifesto que fica ao lado de `src`.
O chamador fornece `EXPECTED_HEAD` e `EXPECTED_CONTENT_SHA`; o runner não presume que o snapshot contenha
`.git` (a captura normal o exclui). Ele:

1. aceita apenas `/Users/Shared/maccluster-workspaces/chat2you/*/src`;
2. exige o arquivo irmão `.maccluster-workspace.json`, valida `snapshot_id`, `source_branch`, `source_head`
   e `content_sha256` contra os valores esperados e, quando passadas, réplicas com o mesmo manifesto;
3. fixa `59720` Rails, `59721` Vite, `59722` PostgreSQL e `59723` Redis, falhando se alguma porta estiver
   ocupada;
4. cria PostgreSQL/Redis e logs em `.codex/runtime-m2-*` ao lado do `src`, nunca dentro dele;
5. usa `/usr/bin/env -i` com somente o ambiente local necessário;
6. deixa `--prepare-db` e `--seed` explícitos. O primeiro banco novo recebe exatamente `rails db:schema:load`
   e cria o marcador externo `.schema-loaded`; um banco existente só é reutilizado quando esse marcador existe,
   sem `db:prepare`, migration implícita ou reset automático. O seed só roda com `RAILS_ENV=development`, pelo
   guard já existente em `.codex/preview/seed-agents.rb`; como o arquivo é ignorado pelo Git, o runner aceita
   `PREVIEW_SEED_PATH` apontando para a cópia temporária encaminhada ao M2;
7. usa Overmind somente se já houver um binário local; sem ele, acompanha apenas Rails e Vite como processos
   filhos e encerra ambos junto com PostgreSQL/Redis. Rails recebe PID e `--log-to-stdout`, e os logs são
   redirecionados para o runtime externo ao snapshot;
8. não escolhe outra porta, não copia checkout, não inicia worker, não acessa produção, não lê AWS real e não
   habilita IA paga.

O ambiente isolado fixa `POSTGRES_DATABASE=chat2you_agentes_ia_prd`, `POSTGRES_USERNAME=chat2you_dev`,
`AWS_EC2_METADATA_DISABLED=true`, arquivos AWS em `/dev/null`,
`AUTONOMIA_AGENTS_ENABLED=true`, `AUTONOMIA_AGENTS_REDESIGN=true` e
`AI_INSTRUCTION_AUTO_REFRESH=false`.

## Execução futura coordenada

Depois de o root capturar SRC27 e conferir as duas réplicas, a execução deve fornecer o SHA e os caminhos
das réplicas. O primeiro passo seguro é a validação sem serviços:

```sh
EXPECTED_HEAD=<SHA_DO_SRC27> \
EXPECTED_CONTENT_SHA=<CONTENT_SHA_DO_MANIFESTO> \
  .codex/preview/run-m2.sh \
  /Users/Shared/maccluster-workspaces/chat2you/<snapshot>/src \
  --check-only
```

Para preparar o banco local e as fixtures, a execução posterior deve ser explícita:

```sh
EXPECTED_HEAD=<SHA_DO_SRC27> \
EXPECTED_CONTENT_SHA=<CONTENT_SHA_DO_MANIFESTO> \
  .codex/preview/run-m2.sh \
  /Users/Shared/maccluster-workspaces/chat2you/<snapshot>/src \
  /Users/Shared/maccluster-workspaces/chat2you/<replica>/src \
  --prepare-db --seed
```

Quando o seed não estiver dentro do snapshot, acrescente `PREVIEW_SEED_PATH=/caminho/temporario/seed-agents.rb`
ao mesmo comando. O arquivo temporário deve ser o seed revisado da worktree, sem segredos.

Esses comandos representam o contrato do runner; não foram executados nesta preparação. A sessão principal
deve invocar o arquivo a partir do snapshot correspondente ou transportar somente esse script aprovado para
o M2, sem copiar o checkout Git ativo.

## Limites

O runner não substitui autenticação local nem prova a tela. O seed cria apenas as fixtures sintéticas
descritas em `docs/audit/2026-10-07-agentes-f1-fixtures-locais.md`; o usuário deve conferir o fluxo de login
local e o payload real antes das capturas. Nenhuma credencial, token, senha, dado de cliente, provedor real,
fila de merge, produção ou migration foi tocado.
