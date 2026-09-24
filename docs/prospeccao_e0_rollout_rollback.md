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

## Migrations

| Versão | O que faz | Volta |
|---|---|---|
| `20260925100000` | default de `autonomia_prospecting_settings.provider` passa de `mock` para `google_places` | `rails db:migrate:down VERSION=20260925100000` volta o default para `mock`; nenhuma linha é alterada (as criadas depois do deploy, ver "Volta do código") |
| `20260925100100` | conta com `enrichment_enabled = true` ganha `autonomia_prospecting_research_enabled = true` | o `down` não desliga (não separa migração de ação do superadmin); desligar é pelo console, conta a conta |

Nenhuma das duas apaga coluna ou dado. As duas foram ensaiadas no banco de teste local com rollback de transação.

## Antes de subir (aprovação do Rodrigo)

1. **Backup do banco de produção.** Confirmar que existe snapshot recente e backup automático com retenção de 7
   dias ou mais e proteção contra exclusão. A memória operacional registra que o RDS de produção estava sem backup
   nem snapshot: se ainda estiver, este é o primeiro passo, e é decisão de infra.
   O backup só conta depois do ensaio de restauração abaixo.
2. **Foto das contas afetadas**, por `psql` (nunca `rails runner` em produção):

   ```sql
   SELECT s.account_id, s.provider, s.provider_enabled, s.enrichment_enabled,
          a.internal_attributes ->> 'autonomia_prospecting_enabled' AS modulo
   FROM autonomia_prospecting_settings s JOIN accounts a ON a.id = s.account_id
   ORDER BY s.account_id;
   ```

   Guardar a saída no host de produção, no caminho que o runbook de deploy define.
   Anotar também a hora exata do deploy (UTC): ela separa, na volta, as linhas criadas pela versão nova.
3. **Chaves da plataforma** cadastradas no superadmin antes do deploy, para a primeira busca já achar a chave.
   Sem `GOOGLE_PLACES_API_KEY`, a busca com `google_places` responde 422 "Google Places platform API key is not
   configured".

## Ensaio de restauração (antes do deploy)

A issue pede backup com restauração testada, e a prova é o log da restauração. Existir snapshot não prova nada.

1. Restaurar o snapshot do passo 1 numa **instância temporária**, com nome próprio. Nunca por cima da instância de
   produção. O comando exato é do runbook de infra da conta AWS.
2. Na instância restaurada, por `psql`, rodar o mesmo SELECT da foto do passo 2 e mais:

   ```sql
   SELECT COUNT(*) FROM autonomia_prospecting_settings;
   SELECT COUNT(*) FROM autonomia_prospecting_searches;
   SELECT COUNT(*) FROM autonomia_prospecting_leads;
   SELECT COUNT(*) FROM accounts WHERE internal_attributes ? 'autonomia_prospecting_enabled';
   ```

3. Rodar as mesmas consultas em produção e comparar. Diferença só pode vir do que entrou depois do snapshot.
4. Guardar as duas saídas, com a hora e o identificador do snapshot, como **log da restauração**, no mesmo caminho da
   foto do passo 2.
5. Apagar a instância temporária e conferir que ela sumiu da lista.

Sem esse log, não sobe.

## Contas em `mock`

A migration não troca o provider de quem já tem configuração. Conta que comprou Prospecção e está em `mock` continua
recebendo lead fictício até a troca abaixo, que é escrita em produção e exige aprovação. Até a troca, as telas de
configurações e de busca mostram o aviso "Modo de demonstração" (`mock_provider` no GET de settings), e não o selo de
chaves prontas.

**Decisão pendente do Rodrigo:** tornar esta troca passo obrigatório do deploy, logo depois da foto do passo 2, para
toda conta com o módulo ligado, em vez de deixá-la opcional depois.

```sql
-- Troca (uma conta por vez, com o id conferido na foto do passo 2)
UPDATE autonomia_prospecting_settings SET provider = 'google_places', updated_at = NOW()
WHERE account_id = :account_id AND provider = 'mock';

-- Volta
UPDATE autonomia_prospecting_settings SET provider = 'mock', updated_at = NOW()
WHERE account_id = :account_id AND provider = 'google_places';
```

Evidência final, guardada junto da foto do passo 2: a lista das contas trocadas.

```sql
SELECT account_id, provider, updated_at FROM autonomia_prospecting_settings
WHERE account_id IN (:ids_trocados) ORDER BY account_id;
```

## Depois de subir

1. Superadmin → conta de teste → **Enable Autonomia Prospecting** e **Enable Prospecting research**.
2. Busca de 60 com a conta de teste: responde 201 com até 20 leads do Google, sem colar chave.
3. Configurações → Prospecção mostra "chaves da plataforma configuradas" e, sem hook `crm_kanban_ai`, o aviso de IA.
4. Enriquecer um lead com site: conclui com fonte `site` sem hook, e `site_and_autonomia_ai` com hook.

## Volta do código

Não há volta de código sem os três passos abaixo, nesta ordem. A cabeça do schema é compartilhada com outra sessão:
`db:rollback STEP=2` pode desfazer migration que não é da E0, então a volta é por versão.

1. Reverter para a imagem anterior.
2. Voltar as duas migrations pela versão:

   ```sh
   bundle exec rails db:migrate:down VERSION=20260925100100   # não altera dado
   bundle exec rails db:migrate:down VERSION=20260925100000   # default volta para mock
   ```

3. Voltar as linhas que a versão nova criou. Voltar o default não mexe nelas: nasceram com `provider =
   'google_places'`, `provider_enabled = false` e sem chave na conta, e a versão anterior recusa toda busca delas com
   "Google Places provider is disabled for this account". Escrita em produção, com aprovação:

   ```sql
   -- Conferir antes
   SELECT account_id, created_at FROM autonomia_prospecting_settings
   WHERE provider = 'google_places' AND created_at >= :hora_do_deploy AND google_places_api_key IS NULL;

   UPDATE autonomia_prospecting_settings SET provider = 'mock', updated_at = NOW()
   WHERE provider = 'google_places' AND created_at >= :hora_do_deploy AND google_places_api_key IS NULL;
   ```

   As contas trocadas de `mock` para `google_places` na seção anterior voltam pelo SQL "Volta" de lá, uma por vez,
   com a lista da evidência final.

As colunas antigas continuam no banco com o valor que tinham, então a versão anterior volta a ler chave, limites e
`enrichment_enabled` da conta como antes. A chave nova em `internal_attributes` e as linhas de `InstallationConfig`
são ignoradas pela versão anterior.
