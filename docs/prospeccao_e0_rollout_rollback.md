# Prospecção E0 (#683): subida e volta

## O que muda

- Chaves do Google e da BigDataCorp passam a ser da plataforma, em `InstallationConfig`:
  `GOOGLE_PLACES_API_KEY` e `BIGDATACORP_PASSWORD`/`BIGDATACORP_USER` (segredos) e `GOOGLE_MAPS_BROWSER_API_KEY`
  (chave pública de navegador, restrita por domínio). Superadmin → Settings → Prospecting.
- A conta não grava mais chave, provider, limites nem `enrichment_enabled` pela API. As colunas ficam no banco e
  deixam de ser lidas.
- Sem trava de consumo: `max_results_per_search`, `daily_limit` e `monthly_limit` deixam de valer. O pedido vai até
  60; o Google Places continua devolvendo no máximo 20 por busca (paginação é da E2).
- Interruptor novo no superadmin, na página da conta: **Prospecting research**
  (`accounts.internal_attributes['autonomia_prospecting_research_enabled']`). O enriquecimento só roda com o módulo
  e a pesquisa ligados.
- A IA da prospecção usa só o hook `crm_kanban_ai` da conta (`Autonomia::Prospecting::AiCredential`). Sem hook,
  sem IA, mesmo com `CAPTAIN_OPEN_AI_API_KEY`. O `Crm::Ai::CredentialResolver` não mudou.
- Defeitos corrigidos: busca que falhou não serve mais de cache; duas buscas no mesmo lugar ao mesmo tempo não
  derrubam uma à outra.

## Duas stacks, cada passo nas duas

Todo passo de produção deste runbook vale para **as duas stacks**, uma de cada vez, cada uma com seu banco, seu
superadmin e sua foto:

| | hub2you | autonomia |
|---|---|---|
| Painel | `chat.hub2you.ai` | `agents.autonomia.site` |
| Conta AWS | `354307071110`, `us-east-1`, perfil CLI `hub2you` | `140023375763`, `us-east-1`, credencial de `~/dev/Appsell/credential.env` |
| Prefixo dos comandos `aws` | `aws <comando> --profile hub2you --region us-east-1` | `bash -c 'set -a; . ~/dev/Appsell/credential.env; set +a; unset AWS_PROFILE; aws <comando> --region us-east-1'` |

As contas e o prefixo da autonomia são os de `docs/rollback-chatwoot-4171.md`. Um passo só está feito quando está
feito nas duas; a evidência de cada passo é guardada separada por stack.

Nos SQL abaixo, `:ids_trocados` e `:hora_do_deploy` são lugares para o valor anotado (a lista de ids da troca e a
hora UTC do deploy daquela stack, entre aspas simples), escrito à mão antes de rodar.

Banco de produção só por `psql` via SSM. O Rails não sobe na EC2 de produção: é regra da casa nunca rodar
`rails runner` nem `rails console` lá (derrubou o Chatwoot em 2026-07-27). Por isso nenhuma volta deste runbook usa
`rails db:migrate:down`.

## Migrations

| Versão | O que faz | Volta |
|---|---|---|
| `20260925100000` | default de `autonomia_prospecting_settings.provider` passa de `mock` para `google_places` | SQL em "Volta do código", passo 2 |
| `20260925100100` | conta com `enrichment_enabled = true` ganha `autonomia_prospecting_research_enabled = true` | não desliga (não separa migração de ação do superadmin); a versão anterior ignora a chave |

Nenhuma das duas apaga coluna ou dado. As duas foram ensaiadas no banco de teste local com rollback de transação.

O horário das duas versões foi combinado em 24/09 com as sessões Cotação e Central de Ajuda, que também tinham
migration na fila. A cabeça anterior do schema é `2026_09_24_150000` (`add_empresarial_specialist_to_quote_agents`),
e as duas da E0 entram logo depois dela.

## Antes de subir (aprovação do Rodrigo)

### 1. Backup do banco de produção

A memória operacional registra que o RDS de produção estava sem backup nem snapshot. Em cada stack, com o
identificador da instância RDS no lugar de `<rds-de-producao>`:

```sh
# Estado atual: retenção de backup e proteção contra exclusão
aws rds describe-db-instances --profile hub2you --region us-east-1 \
  --db-instance-identifier <rds-de-producao> \
  --query 'DBInstances[0].[BackupRetentionPeriod,DeletionProtection]'

# Snapshot manual antes do deploy
aws rds create-db-snapshot --profile hub2you --region us-east-1 \
  --db-instance-identifier <rds-de-producao> \
  --db-snapshot-identifier <rds-de-producao>-pre-prospeccao-e0-<AAAAMMDD>

aws rds wait db-snapshot-available --profile hub2you --region us-east-1 \
  --db-snapshot-identifier <rds-de-producao>-pre-prospeccao-e0-<AAAAMMDD>

# Backup automático de 7 dias e proteção contra exclusão
aws rds modify-db-instance --profile hub2you --region us-east-1 \
  --db-instance-identifier <rds-de-producao> \
  --backup-retention-period 7 --deletion-protection --apply-immediately
```

Na autonomia, os mesmos comandos com o prefixo da tabela acima. Depois do `modify`, repetir o `describe` e guardar a
saída: tem que mostrar `7` e `true`. Segundo a documentação da AWS, passar a retenção de 0 para um valor maior que 0
causa uma parada curta da instância: fazer em janela combinada. É decisão de infra, com aprovação.

A restauração de um snapshot segue o comando de `docs/rollback-chatwoot-4171.md:203`
(`aws rds restore-db-instance-from-db-snapshot`), sempre para uma instância com nome novo. O backup só conta depois
do ensaio de restauração abaixo.

### 2. Foto inicial

Em cada stack, por `psql`:

```sql
-- Contas com prospecção
SELECT s.account_id, s.provider, s.provider_enabled, s.enrichment_enabled,
       a.internal_attributes ->> 'autonomia_prospecting_enabled' AS modulo
FROM autonomia_prospecting_settings s JOIN accounts a ON a.id = s.account_id
ORDER BY s.account_id;

-- Contas com chave própria gravada: só o id e se a chave existe, NUNCA o valor da coluna
SELECT account_id,
       google_places_api_key IS NOT NULL AS tem_chave_places,
       google_maps_browser_api_key IS NOT NULL AS tem_chave_mapa
FROM autonomia_prospecting_settings
WHERE google_places_api_key IS NOT NULL OR google_maps_browser_api_key IS NOT NULL
ORDER BY account_id;
```

Guardar a saída no host de produção, no caminho que o runbook de deploy define. A segunda lista diz quem hoje busca
no Google com chave própria: depois do deploy essa chave deixa de ser lida, e essas contas dependem da chave da
plataforma (ver "Janela entre o deploy e as chaves").

Anotar também a hora exata do deploy de cada stack (UTC): ela separa, na volta, as linhas criadas pela versão nova.

## Ensaios (antes do deploy)

### Ensaio de restauração

A issue pede backup com restauração testada, e a prova é o log da restauração. Existir snapshot não prova nada.

1. Restaurar o snapshot do passo 1 numa **instância temporária**, com nome próprio (por exemplo
   `<rds-de-producao>-ensaio-e0-<AAAAMMDD>`), pelo comando de `docs/rollback-chatwoot-4171.md:203` trocando
   `--db-instance-identifier` pelo nome temporário e `--db-snapshot-identifier` pelo snapshot do passo 1. Nunca por
   cima da instância de produção.
2. Na instância restaurada, por `psql`, rodar as duas consultas da foto do passo 2 e mais:

   ```sql
   SELECT COUNT(*) FROM autonomia_prospecting_settings;
   SELECT COUNT(*) FROM autonomia_prospecting_searches;
   SELECT COUNT(*) FROM autonomia_prospecting_leads;
   SELECT COUNT(*) FROM accounts WHERE internal_attributes ? 'autonomia_prospecting_enabled';
   ```

3. Rodar as mesmas consultas em produção e comparar. Diferença só pode vir do que entrou depois do snapshot.
4. Guardar as duas saídas, com a hora e o identificador do snapshot, como **log da restauração**, no mesmo caminho da
   foto do passo 2.

### Ensaio da troca das contas `mock`

Ainda na instância restaurada, antes de apagá-la, rodar a troca e a volta da seção "Troca das contas `mock`" do
jeito que vão rodar em produção:

1. O SELECT "Antes" da troca: a lista tem que bater com as contas `mock` e módulo ligado da foto do passo 2.
2. O UPDATE da troca: o número de linhas alteradas tem que ser igual ao tamanho dessa lista.
3. O SELECT "Depois": as mesmas contas, agora em `google_places`.
4. O UPDATE da volta, com os ids trocados, e o SELECT de novo: tem que voltar a ser igual à foto.

Guardar as quatro saídas junto do log da restauração. Depois, apagar a instância temporária, conferindo antes que o
identificador é o do ensaio e não o de produção:

```sh
aws rds delete-db-instance --profile hub2you --region us-east-1 \
  --db-instance-identifier <rds-de-producao>-ensaio-e0-<AAAAMMDD> --skip-final-snapshot
aws rds describe-db-instances --profile hub2you --region us-east-1 --query 'DBInstances[].DBInstanceIdentifier'
```

A instância do ensaio tem que ter sumido da lista. Sem o log da restauração e o da troca, nas duas stacks, não sobe.

## Subida, nesta ordem, em cada stack

O grupo **Prospecting** só aparece no superadmin depois do deploy, porque é a versão nova que o cria. Não dá para
cadastrar as chaves antes.

1. **Deploy** pelo runbook do projeto. Anotar a hora (UTC).
2. **Cadastro imediato das chaves**, logo que o healthcheck passar: Superadmin → Settings → Prospecting,
   `GOOGLE_PLACES_API_KEY` e `GOOGLE_MAPS_BROWSER_API_KEY` (e as da BigDataCorp, se já houver). Cada stack tem o seu
   superadmin e o seu banco: cadastrar nas duas.
3. **Troca das contas `mock`** (seção abaixo), passo obrigatório.
4. **Busca de prova** (seção "Depois de subir").

### Janela entre o deploy e as chaves

Entre o passo 1 e o passo 2, a plataforma não tem chave do Google:

- conta em `google_places` sem chave de plataforma recebe **422** "Google Places platform API key is not
  configured" em toda busca. Isso inclui as contas da lista de chave própria da foto do passo 2, porque a versão
  nova não lê mais a chave da conta;
- o mapa da tela de busca não aparece (falta `GOOGLE_MAPS_BROWSER_API_KEY`);
- conta ainda em `mock` continua recebendo lead fictício, sem erro.

Por isso o passo 2 vem colado no 1, e a troca do passo 3 só depois dele: trocar uma conta para `google_places` antes
das chaves só a leva para o 422.

## Troca das contas `mock`

**Passo obrigatório do deploy**, para **toda conta com o módulo ligado** que esteja em `mock`, nas duas stacks. A
migration não troca o provider de quem já tem configuração: sem este passo, conta que comprou Prospecção continua
recebendo lead fictício, e as telas mostram o aviso "Modo de demonstração" (`mock_provider` no GET de settings) no
lugar do selo de chaves prontas.

É escrita em produção: **aguarda o OK final do Rodrigo no momento do deploy**, depois do cadastro das chaves.

```sql
-- Antes: quem vai ser trocado. Guardar a lista de ids (é a :ids_trocados da volta)
SELECT s.account_id, s.provider, s.updated_at
FROM autonomia_prospecting_settings s JOIN accounts a ON a.id = s.account_id
WHERE s.provider = 'mock' AND a.internal_attributes ->> 'autonomia_prospecting_enabled' = 'true'
ORDER BY s.account_id;

-- Troca
UPDATE autonomia_prospecting_settings s SET provider = 'google_places', updated_at = NOW()
FROM accounts a
WHERE a.id = s.account_id AND s.provider = 'mock'
  AND a.internal_attributes ->> 'autonomia_prospecting_enabled' = 'true';

-- Depois: as mesmas contas, agora em google_places
SELECT account_id, provider, updated_at FROM autonomia_prospecting_settings
WHERE account_id IN (:ids_trocados) ORDER BY account_id;
```

O número de linhas do UPDATE tem que ser igual ao tamanho da lista "Antes". As três saídas ficam junto da foto do
passo 2: são a evidência da troca.

## Depois de subir

1. Superadmin → conta de teste → **Enable Autonomia Prospecting** e **Enable Prospecting research**.
2. Busca de 60 com a conta de teste: responde 201 com até 20 leads do Google, sem colar chave.
3. Configurações → Prospecção mostra "chaves da plataforma configuradas" e, com a pesquisa ligada e sem hook
   `crm_kanban_ai`, o aviso de IA. Com a pesquisa desligada, o aviso de IA não aparece.
4. Enriquecer um lead com site: conclui com fonte `site` sem hook, e `site_and_autonomia_ai` com hook.
5. Uma busca numa conta da lista de chave própria da foto do passo 2: tem que responder 201 com a chave da
   plataforma.

## Volta do código

Não há volta de código sem os três passos abaixo, nesta ordem, em cada stack. A volta do banco é por SQL, via
`psql`: a imagem anterior não tem os arquivos das migrations da E0, então `rails db:migrate:down` não acha o que
desfazer, e o Rails não roda na EC2 de produção de qualquer jeito. A cabeça do schema é compartilhada com outras
sessões, então nada de `db:rollback STEP=2`: a volta é por versão.

1. **Voltar o tráfego para a versão anterior**, pelo procedimento de `docs/rollback-chatwoot-4171.md` (Opção A,
   blue parado; ou Opção B, imagem etiquetada), com os IDs registrados para este release.
2. **Desfazer as migrations por SQL.** Escrita em produção, com aprovação:

   ```sql
   -- Conferir antes
   SELECT column_default FROM information_schema.columns
   WHERE table_name = 'autonomia_prospecting_settings' AND column_name = 'provider';
   SELECT version FROM schema_migrations WHERE version IN ('20260925100000', '20260925100100');

   BEGIN;
   ALTER TABLE autonomia_prospecting_settings ALTER COLUMN provider SET DEFAULT 'mock';
   DELETE FROM schema_migrations WHERE version IN ('20260925100000', '20260925100100');
   COMMIT;

   -- Conferir depois: default 'mock'::character varying e nenhuma das duas versões
   SELECT column_default FROM information_schema.columns
   WHERE table_name = 'autonomia_prospecting_settings' AND column_name = 'provider';
   SELECT version FROM schema_migrations WHERE version IN ('20260925100000', '20260925100100');
   ```

   O `DELETE` tem que apagar 2 linhas. A `20260925100100` não tem o que desfazer: a chave de pesquisa em
   `internal_attributes` fica e é ignorada pela versão anterior. Sem as duas versões em `schema_migrations`, um novo
   deploy da E0 roda as duas de novo; a `20260925100100` volta a ligar a pesquisa de quem tem `enrichment_enabled`.
3. **Voltar as linhas de provider.** Voltar o default não mexe nas linhas existentes. Escrita em produção, com
   aprovação.

   a. Linhas criadas pela versão nova: nasceram com `provider = 'google_places'`, `provider_enabled = false` e sem
      chave na conta, e a versão anterior recusa toda busca delas com "Google Places provider is disabled for this
      account".

   ```sql
   -- Conferir antes
   SELECT account_id, created_at FROM autonomia_prospecting_settings
   WHERE provider = 'google_places' AND created_at >= :hora_do_deploy AND google_places_api_key IS NULL;

   UPDATE autonomia_prospecting_settings SET provider = 'mock', updated_at = NOW()
   WHERE provider = 'google_places' AND created_at >= :hora_do_deploy AND google_places_api_key IS NULL;

   -- Conferir depois: a mesma consulta não traz mais nenhuma linha
   SELECT account_id, created_at FROM autonomia_prospecting_settings
   WHERE provider = 'google_places' AND created_at >= :hora_do_deploy AND google_places_api_key IS NULL;
   ```

   b. Contas trocadas de `mock` para `google_places` na seção "Troca das contas `mock`", com a lista de ids guardada
      como evidência da troca:

   ```sql
   -- Conferir antes: todas em google_places
   SELECT account_id, provider, updated_at FROM autonomia_prospecting_settings
   WHERE account_id IN (:ids_trocados) ORDER BY account_id;

   UPDATE autonomia_prospecting_settings SET provider = 'mock', updated_at = NOW()
   WHERE account_id IN (:ids_trocados) AND provider = 'google_places';

   -- Conferir depois: todas em mock, igual à foto do passo 2
   SELECT account_id, provider, updated_at FROM autonomia_prospecting_settings
   WHERE account_id IN (:ids_trocados) ORDER BY account_id;
   ```

As colunas antigas continuam no banco com o valor que tinham, então a versão anterior volta a ler chave, limites e
`enrichment_enabled` da conta como antes. A chave nova em `internal_attributes` e as linhas de `InstallationConfig`
são ignoradas pela versão anterior.
