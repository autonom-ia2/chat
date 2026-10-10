# Runbook — publicar a biblioteca de modelos de e-mail (#1082)

A galeria **Modelos** de Campanhas → E-mail mostra os modelos globais (`email_campaign_templates` com
`account_id IS NULL`), iguais para todas as contas. Os "Meus modelos" de cada conta são linhas com `account_id`
e nunca são tocados por este runbook.

## Como a biblioteca chega à produção

| Parte | Onde mora | Como chega |
|---|---|---|
| 13 desenhos (MJML + HTML compilado) | `db/seeds/email_templates/` (`catalog.json`, `<categoria>/*.mjml`, `*.html`) | Vão na imagem (`COPY . /app`). **O deploy não grava no banco**: o blue-green só roda `db:chatwoot_prepare` (migrations). |
| Linhas da galeria | tabela `email_campaign_templates` | Só pela rake `email_campaign_templates:seed`, rodada **depois** do deploy pelo workflow `ops-email-templates-seed.yml`. |
| 5 fotos | `public/email-templates/biblioteca/*.jpg` | Vão na imagem e são servidas pelo próprio Rails (`RAILS_SERVE_STATIC_FILES`, padrão ligado), com `Cache-Control` de 1 ano. |
| Nomes e categorias na tela | `WORKSPACE.MODELS` e `GALLERY.CATEGORIES` em `campaign.json` (en, pt_BR) | Vão no build do painel, no deploy. |

O seed troca o caminho relativo das fotos (`/email-templates/biblioteca/…`) pelo endereço absoluto da instalação
que roda o seed (`FRONTEND_URL` daquele stack: `chat.hub2you.ai` ou `agents.autonomia.site`). Cliente de e-mail
precisa de URL absoluta; cada stack aponta para si mesmo, sem host de terceiros.

Até 06/10/2026 a produção tinha os 14 modelos em inglês do pacote Mailteorite, gravados uma vez em 01/10 por
SSM (registro em `docs/audit/2026-10-01-release-campaigns-800.md`). O seed novo apaga **só** essas 14 linhas
globais (nomes exatos em `db/seeds/email_templates/retired.json`). Qualquer outra linha global fora do catálogo
aparece como `keep (global outside the catalog)` e fica.

Campanhas criadas a partir dos modelos antigos guardam uma cópia do corpo; não têm vínculo com a tabela e não
mudam.

## O que a rake faz

```sh
bundle exec rails email_campaign_templates:seed          # dry-run: só relata, não grava
APPLY=1 bundle exec rails email_campaign_templates:seed  # grava, numa transação só
```

Saída: uma linha por modelo (`create:` / `update:` / `unchanged:`), uma por linha global removida
(`retire: id=… nome`), a contagem de modelos das contas (`never touched`) e a linha `totals:`. Sem `FRONTEND_URL`
absoluto ela falha antes de ler o banco. Rodar de novo é seguro: o segundo apply sai `unchanged=13`.

Na produção, **nunca** por `rails runner`, console ou `docker exec` manual: só pelo workflow abaixo.

## Passo a passo

**Quando:** depois que o deploy do merge terminar com sucesso nos dois stacks. Fora do horário de pico (a galeria
troca na hora para todas as contas).

1. **SHA em produção** de cada stack:
   ```sh
   gh run list --workflow deploy-hub2you-blue-green.yml --status success -L 1 --json headSha -q '.[0].headSha'
   gh run list --workflow deploy-autonomia-blue-green.yml --status success -L 1 --json headSha -q '.[0].headSha'
   ```
   Tem de ser o merge que contém este PR (ou posterior).
2. **Fotos no ar** (leitura pública; esperado `200` e `content-type: image/jpeg`):
   ```sh
   curl -sI https://chat.hub2you.ai/email-templates/biblioteca/01-boas-vindas.jpg
   curl -sI https://agents.autonomia.site/email-templates/biblioteca/01-boas-vindas.jpg
   ```
   Se não vier 200, **pare**: o seed gravaria modelos com foto quebrada.
3. **Leitura antes** (consulta só de leitura da seção Verificação, por psql via SSM): anotar `globais`, `antigos`
   e a impressão digital dos modelos das contas.
4. **Snapshot dos globais** (é o rollback de dados). Leitura, gravada no host, permissão 0600, mesmo padrão de
   `/opt/chatwoot/backups/email800/`:
   ```sql
   \copy (SELECT json_agg(t) FROM (SELECT id, name, category, thumbnail_url, body_mjml, body_html, created_at, updated_at FROM email_campaign_templates WHERE account_id IS NULL ORDER BY id) t) TO '/tmp/globals-before.json'
   ```
   Copiar para `/opt/chatwoot/backups/email1082/<sha12>/globals-before.json` e conferir o checksum. Não exportar
   linhas de contas.
5. **DRY-RUN** nos dois stacks:
   ```sh
   gh workflow run ops-email-templates-seed.yml --ref main \
     -f stack=both -f mode=dry_run -f expected_sha=<sha> -f confirm_production=false
   ```
   Esperado: `create=13 update=0 unchanged=0 retire=14 unknown_kept=0` (ou `retire` menor, se algum antigo já
   não existir). Qualquer `keep (global outside the catalog)` é linha que ninguém esperava: investigar antes.
6. **APPLY** (com OK do Rodrigo):
   ```sh
   gh workflow run ops-email-templates-seed.yml --ref main \
     -f stack=both -f mode=apply -f expected_sha=<sha> -f confirm_production=true
   ```
   Se os dois stacks estiverem em SHAs diferentes, rodar um de cada vez com `-f stack=hub2you` / `autonomia`.
7. **Verificação** (seção abaixo) e conferência visual na conta 16: galeria com 13 modelos em português, 8
   categorias, prévia Desktop/Mobile com as fotos, "Usar modelo" abre o editor. Não enviar campanha real.
8. Rodar o DRY-RUN de novo: esperado `unchanged=13 retire=0`.

O workflow só roda a partir do `main`, no environment `production`, na fila de concorrência do deploy do stack,
aborta se `/app/.git_sha` não for o `expected_sha` e grava a saída completa em `/var/log/chatwoot-ops/` na
instância (detalhes em `ops-contacts-merge-ninth-digit.md`, seção "Limite da saída").

## Verificação (somente leitura)

Por SSM → `docker exec chatwoot-web sh -c 'psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f /tmp/q.sql'` (SQL
enviado em base64), conforme `docs/processo-de-release.md`.

```sql
SELECT count(*) AS globais,
       count(*) FILTER (WHERE name IN ('Boas-vindas', 'Novidade / lançamento', 'Pré-lançamento',
         'Convite para evento ou encontro ao vivo', 'Newsletter', 'Oferta com cupom', 'Reengajamento',
         'Pesquisa de satisfação (NPS)', 'Lembrete de vencimento ou renovação', 'Pós-atendimento e avaliação',
         'Aniversário do cliente', 'Comunicado importante', 'Conteúdo educativo')) AS novos,
       count(*) FILTER (WHERE name IN ('Abandoned Cart with Benefits Breakdown',
         'Welcome & Account Activation for Donors', 'Welcome & Email Verification (Security-Focused)',
         'Webinar Thank You & Review Request', 'Weekly Newsletter with Data Analysis',
         'Productivity Newsletter - Quarterly Edition', 'New Product Launch - Simple Hero',
         'Product Launch Teaser - Mystery Reveal', 'Post-Purchase Review Request',
         'Re-engagement Breakup (Final Notice)', 'Company Anniversary Celebration', 'Win-Back with Anonymous Poll',
         'Card Shipped Confirmation', 'Order Bump with Future Discount')) AS antigos,
       count(*) FILTER (WHERE body_html LIKE '%{{ unsubscribe_url }}%' AND body_mjml LIKE '%footer-locked%') AS com_rodape,
       count(*) FILTER (WHERE body_mjml LIKE '%src="/email-templates/%' OR body_html LIKE '%src="/email-templates/%') AS foto_relativa,
       count(*) FILTER (WHERE body_html LIKE '%/email-templates/biblioteca/%') AS com_foto
FROM email_campaign_templates WHERE account_id IS NULL;

-- Impressão digital dos modelos das contas: tem de ser idêntica antes e depois.
SELECT count(*) AS modelos_das_contas,
       md5(string_agg(id || ':' || md5(coalesce(body_mjml, '')) || md5(coalesce(body_html, '')) || name
                      || coalesce(category, '') || coalesce(thumbnail_url, '') || updated_at::text, ',' ORDER BY id)) AS impressao
FROM email_campaign_templates WHERE account_id IS NOT NULL;
```

Esperado depois do apply: `globais=13 novos=13 antigos=0 com_rodape=13 foto_relativa=0 com_foto=5` (mais as
eventuais linhas `unknown_kept` do dry-run) e a mesma impressão digital das contas.

## Rollback

O deploy em si não muda dados; o apply é que troca a galeria. Rollback, do mais barato ao mais caro:

1. **Corrigir para frente** (preferido para ajuste de texto/foto): PR novo mudando o MJML, `rails
   email_campaign_templates:compile`, merge, deploy e o mesmo workflow (sai `update=N`). Foto nova entra com
   **nome novo**: o `Cache-Control` de 1 ano faz clientes de e-mail guardarem a antiga pelo nome.
2. **Voltar os dados** (galeria antiga de volta; prod write, só com OK do Rodrigo), numa transação, por psql via
   SSM, a partir do snapshot do passo 4:
   ```sql
   -- snapshot copiado para /tmp/globals-before.json dentro do container (docker cp); o psql lê o arquivo
   \set snapshot `cat /tmp/globals-before.json`
   BEGIN;
   DELETE FROM email_campaign_templates WHERE account_id IS NULL AND name IN (<os 13 nomes novos>);
   INSERT INTO email_campaign_templates (id, account_id, name, category, thumbnail_url, body_mjml, body_html, created_at, updated_at)
   SELECT id, NULL, name, category, thumbnail_url, body_mjml, body_html, created_at, updated_at
   FROM json_populate_recordset(NULL::email_campaign_templates, :'snapshot'::json)
   ON CONFLICT (id) DO NOTHING;
   COMMIT;
   ```
   Rodar a verificação: `antigos=14 novos=0`.
3. **Voltar o código**: `git revert -m 1 <merge do PR>` → PR → merge → deploy, ou o rollback do blue-green
   (`workflow_dispatch` com `action=rollback`, `confirm_production=true`) para a imagem anterior. Atenção: o
   revert sozinho **não** volta a galeria — a rake antiga não apaga os 13 nem existe no runner de ops depois do
   revert — e a imagem antiga não tem `public/email-templates/`, então as fotos dos 13 dariam 404. Código antigo
   só junto com o passo 2.

Nenhum dos três toca modelos das contas nem campanhas.

## Desenvolvimento

- Mudou um `.mjml`? `bundle exec rails email_campaign_templates:compile` (precisa de `pnpm install`): recompila
  com mjml-browser em validação **strict**, roda o `EmailCampaigns::QualityGate` e só grava os `.html` se tudo
  passar.
- No CI, `spec/services/email_campaigns/quality_gate_library_spec.rb` roda o mesmo gate em cada modelo e falha se
  algum `.html` versionado estiver diferente da recompilação, se o rodapé não for idêntico nos 13 ou se faltar
  nome/categoria em `en` ou `pt_BR`.
- Modelo novo: entrada em `catalog.json` (`key`, `name`, `path`, `category`), MJML em `<categoria>/`, foto em
  `public/email-templates/biblioteca/` (≤ 200 KB, `alt`), nome em `WORKSPACE.MODELS.<key>` e, se a categoria for
  nova, `GALLERY.CATEGORIES.<categoria>` (en + pt_BR). Modelo retirado: tirar do catálogo e pôr o nome em
  `retired.json`.
