# #1741 — Roteiro para ligar o piloto (contas 16 e 18, stack hub2you)

Preparado em 18/10/2026, **só com leitura** em produção (SELECT em transação `READ ONLY`, `GET` no motor, leitura do
SSM sem imprimir valores). Nada foi gravado nem reiniciado. Quem executa é a Orquestração, **depois do deploy do
#1741** (PR autonom-ia2/chat#1741), e cada passo precisa do OK do Rodrigo. A conta 1
fica para depois.

## Estado lido em 18/10 (linha de base)

| Item | Valor |
|---|---|
| Instância hub2you no ar | `i-0d1e75d25b4158b3d` (muda a cada deploy) |
| `WAHA_API_URL` / `WAHA_PUBLIC_URL` | `https://wa-hub.autonomia.site` |
| `WAHA_RICH_NATIVE_ENGINES` | **ausente** no SSM e no container |
| SSM `/chatwoot/prod/env` (us-east-1, perfil `hub2you`) | versão **597**, 96 chaves |
| Motor wa-hub `GET /api/server/version` (do container web, com `WAHA_API_KEY`) | HTTP 200, `2026.9.2` PLUS, `autonomia.patch = c2y-rich-5`, `rich_native = options, location, contact, poll, link_button, event`, `list_reply`, `poll_vote`, `reactions`, `edit`, `event_response`, `view_once_notice` = true |
| Cache `cache:waha/engine_capabilities*` no Redis | vazio (esperado: o job ainda não existe em produção) |
| Contas com a posição 34 (bit 33, `8589934592`) de `feature_flags_ext_1` | 0 |
| `feature_flags_ext_1` hoje | conta 16 = `8589934583`, conta 18 = `8589901815` (posição 34 desligada nas duas) |
| Conexões do Híbrido nas contas 16 e 18 | nenhuma (a flag só muda a caixa WAHA comum nelas) |

Caixas WAHA (`Channel::Api`, `provider = waha`) das contas 16 e 18:

| Conta | Caixa (inbox) | Nome | `channel_api.id` | Sessão | `kind` | Motor (início do `webhook_url`) | `secret` | `account_token_owner_user_id` hoje |
|---|---|---|---|---|---|---|---|---|
| 16 | 69 | HUBBER COMUNIDADE | 44 | 5511965720256 | human | `https://wa-hub.autonomia.site` | sim | **23** |
| 18 | 56 | 5511941010656 | 36 | 5511941010656 | ai | `https://wa-hub.autonomia.site` | sim | **1** |

---

## (1) `WAHA_RICH_NATIVE_ENGINES`

**Formato** (`app/services/waha/engine_capabilities.rb`):
- URLs base dos motores, separadas por vírgula. Espaços e vazios são ignorados.
- O código tira a barra final e põe uma de volta (`"#{url.chomp('/')}/"`), então tanto faz escrever com ou sem barra.
- `engine_for(webhook_url)` devolve o primeiro motor em que `webhook_url.start_with?("<motor>/")`. O webhook das caixas é
  `https://wa-hub.autonomia.site/webhooks/chatwoot/<sessão>/<app_id>`, então casa.

**Valor para as contas 16 e 18:**

```
WAHA_RICH_NATIVE_ENGINES=https://wa-hub.autonomia.site
```

As duas caixas usam o wa-hub, o motor que já roda a c2y-rich-5 desde o canário de 17/10. Este roteiro não põe o
wa-autonomia na lista, e a variável **não** vai para a stack Autonom.ia.

**Processos:** web **e** worker. O web lê na lista de conversas, nos campos `whatsapp_api_rich_native` e
`whatsapp_api_message_actions` e na criação de mensagem. O worker roda o cron `Waha::EngineCapabilitiesRefreshJob` e
os envios. Os dois sobem com o mesmo `--env-file /opt/chatwoot/.env`, então basta uma mudança.

**Onde se configura e o que exige:**
- No parâmetro SSM `/chatwoot/prod/env` (SecureString, us-east-1, conta AWS da hub2you). A instância green copia esse
  parâmetro para `/opt/chatwoot/.env` no boot.
- O passo "Ensure Hub2You campaign runtime flags" do deploy preserva as chaves que não estão na lista dele, então a linha
  nova sobrevive aos deploys seguintes.
- **Só vale com uma instância nova:** o deploy blue-green (`deploy-hub2you-blue-green.yml`), pelo push na main ou por
  `workflow_dispatch` com `action=deploy` no mesmo SHA, como no runbook `docs/runbooks/sms-webhook-signature.md`.
- Não editar o `/opt/chatwoot/.env` da instância à mão com `systemctl restart`. Isso derruba o único web atrás do ALB e
  diverge do SSM.
- **Recomendado:** gravar no SSM **antes** do deploy do #1741, para a green já subir com a variável. É seguro com a
  flag desligada: `types_for_inbox` e `actions_for_inbox` devolvem `[]` sem a flag, e o job não faz HTTP enquanto
  nenhuma conta tiver `whatsapp_rich_native`. Se o deploy já tiver passado, gravar e rodar um deploy no mesmo SHA.

**Passos** (procedimento de `docs/production-env-secrets.md`: mudança cirúrgica, +1 chave):
1. Backup: anotar a versão atual do parâmetro (597 em 18/10) e salvar uma cópia em
   `/tmp/chatwoot-hub2you_ssm-env_<timestamp>.env` com `umask 077`. Não imprimir a cópia e apagá-la no fim da operação.
2. Acrescentar **uma** linha: `WAHA_RICH_NATIVE_ENGINES=https://wa-hub.autonomia.site`.
3. Conferir as chaves: 96 → 97, e o diff do conjunto de nomes tem só `WAHA_RICH_NATIVE_ENGINES`. Se cair, abortar.
4. `aws ssm put-parameter --name /chatwoot/prod/env --type SecureString --value file://… --overwrite`.
5. Deploy blue-green (o do #1741, ou o mesmo SHA de novo).

**Conferir depois do (1):**
- nos dois containers, `chatwoot-web` e `chatwoot-worker`, a variável existe: `sh -c 'echo "${WAHA_RICH_NATIVE_ENGINES:-<ausente>}"'`;
- web e worker na imagem do SHA, `/api` 200, as duas stacks conferidas como sempre (`verifica-stack.sh`);
- o cache **continua vazio**, e isso é o esperado: o job só consulta o motor quando alguma conta tem a flag (ver o (3)).

**Tempo do cache:** o cron roda a cada 5 min (`*/5 * * * *`, fila `scheduled_jobs`, `config/schedule.yml`) e o valor
dura 10 min (`CACHE_TTL`). Ele só preenche **depois do (3)**: até 5 min depois de ligar a flag. Até lá, as caixas
mandam tudo em texto e não mostram Reagir/Editar.
- Para forçar sem `rails runner`: Super Admin → `/monitoring/sidekiq` → aba Cron →
  `waha_engine_capabilities_refresh_job` → "Enqueue Now".
- Conferir no Redis, de dentro do container web (`bundle exec ruby` com a gem `redis`, sem subir o Rails):
  - `cache:waha/engine_capabilities/https://wa-hub.autonomia.site/`, com os 6 tipos;
  - `cache:waha/engine_capabilities/actions/https://wa-hub.autonomia.site/`, com `react` e `edit`.

**Rollback do (1)** (passo 0 do README do conector):
1. Restaurar a versão anterior do SSM (ou tirar a linha; chaves 97 → 96) e rodar o deploy no mesmo SHA.
2. Apagar o cache, sem imprimir a senha do Redis:
   `redis-cli -u "$REDIS_URL" DEL "cache:waha/engine_capabilities/https://wa-hub.autonomia.site/" "cache:waha/engine_capabilities/actions/https://wa-hub.autonomia.site/"`
   (precisa responder 2; 0 quer dizer que a chave não estava lá).
3. Se for urgente e não der para esperar o deploy, desligar a flag (rollback do (3)). O efeito é imediato e não
   precisa de deploy.

---

## (2) `account_token_owner_user_id`

O nome diz "coluna", mas o dado é uma chave do JSON `channel_api.additional_attributes`. O `Waha::InboxProvisioner`
grava ali o `Current.user.id` quando cria a caixa pelo painel (`waha_inboxes_controller`, token do `current_user`).

**Prova do dono, sem expor token:**
- de dentro do container web, `GET <motor>/api/apps?session=<sessão>`;
- o sha256 do `config.accountToken` do app `chatwoot` foi comparado com `sha256(access_tokens.token)` no banco, em
  transação READ ONLY, e só o prefixo de 16 caracteres foi impresso:

| Caixa | App `chatwoot` no wa-hub | sha256 do token (16) | Dono do token no banco | Gravado na caixa | Confere |
|---|---|---|---|---|---|
| 69 (conta 16) | accountId 16, inboxId 69, `https://chat.hub2you.ai` | `2dca76d4dbe64823` | User 23, Lucas Vargas (admin na 16) | 23 | **sim** |
| 56 (conta 18) | accountId 18, inboxId 56, `https://chat.hub2you.ai` | `55248a6d6a977e1b` | User 1, Chat2You Admin (admin na 16 e na 18) | 1 | **sim** |

**Conclusão: o (2) já está feito nas contas 16 e 18. Não há UPDATE a rodar.** A consulta oficial de "caixas sem dono"
(`docs/1709-escopo-e-aceite.md`, seção E), com `account_id IN (16, 18)`, já devolve 0 linhas. Rodar de novo
imediatamente antes do (3), porque uma caixa WAHA nova criada no intervalo também nasceria com dono pelo
provisionador:

```sql
BEGIN TRANSACTION READ ONLY;
SELECT i.account_id, i.id AS inbox_id, c.id AS channel_api_id
FROM inboxes i
JOIN channel_api c ON c.id = i.channel_id
WHERE i.channel_type = 'Channel::Api'
  AND i.account_id IN (16, 18)
  AND c.additional_attributes ->> 'provider' = 'waha'
  AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = ''
ORDER BY i.account_id, i.id;
ROLLBACK;
-- precisa voltar 0 linhas
```

**Se** aparecer uma caixa sem dono, o UPDATE com trava fica assim. Ele **não** deve ser rodado nas caixas 69 e 56, que
já estão certas. O `<USER>` só se escreve depois da prova de hash acima para aquela caixa.

```sql
-- backup antes (guardar a saída)
SELECT c.id, c.additional_attributes FROM channel_api c
JOIN inboxes i ON i.channel_id = c.id AND i.channel_type = 'Channel::Api'
WHERE c.id IN (<CHANNEL_API_IDS>) AND i.account_id IN (16, 18);

BEGIN;
DO $$
DECLARE n int;
BEGIN
  UPDATE channel_api c
     SET additional_attributes = c.additional_attributes || jsonb_build_object('account_token_owner_user_id', <USER>),
         updated_at = NOW()
    FROM inboxes i
   WHERE i.channel_id = c.id AND i.channel_type = 'Channel::Api'
     AND c.id IN (<CHANNEL_API_IDS>)
     AND i.account_id IN (16, 18)
     AND c.additional_attributes ->> 'provider' = 'waha'
     AND COALESCE(c.additional_attributes ->> 'account_token_owner_user_id', '') = '';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> <N_ESPERADO> THEN RAISE EXCEPTION 'esperava <N_ESPERADO> linhas, afetou %', n; END IF;
END $$;
COMMIT;

-- rollback (só nas linhas que esta operação preencheu)
UPDATE channel_api SET additional_attributes = additional_attributes - 'account_token_owner_user_id', updated_at = NOW()
 WHERE id IN (<CHANNEL_API_IDS>) AND additional_attributes ->> 'account_token_owner_user_id' = '<USER>';
```

Notas:
- O valor gravado pelo provisionador é número no JSON. O `from_connector?` compara com `to_s`, então tanto faz número
  ou texto.
- Para a expansão depois do piloto: na hub2you, **33 das 39** caixas WAHA ainda estão sem dono. Cada conta nova precisa
  da prova de hash por caixa antes da flag.
- Para a expansão depois do piloto: no SSO (`Autonomia::Sso::Provisioner`), o token entregue ao motor é o de
  `invited_by_user_id`, mas a caixa grava `Current.user&.id`. Nessas caixas, o dono gravado pode **não** ser o dono do
  token. A prova é sempre por hash, nunca só pelo valor gravado. Isso não afeta as caixas 69 e 56, já conferidas.

---

## (3) A flag `whatsapp_rich_native`

Coluna `feature_flags_ext_1`, posição 34, valor `8589934592` (`1 << 33`). A posição foi conferida no
`config/features.yml` do head do PR, onde a flag é a 34ª com `column: feature_flags_ext_1`. A main de hoje tem 33
flags nessa coluna e termina em `whatsapp_hybrid_recovery`. **Antes de gravar**, conferir a posição na imagem no ar:
`git show <sha_no_ar>:config/features.yml`, procurando o nome, nunca o número.

```sql
-- conferência / backup antes (guardar a saída)
SELECT id, feature_flags_ext_1, (feature_flags_ext_1 & 8589934592) <> 0 AS rich_native
FROM accounts WHERE id IN (16, 18) ORDER BY id;
-- esperado hoje: 16 = 8589934583 f ; 18 = 8589901815 f

BEGIN;
DO $$
DECLARE n int;
BEGIN
  UPDATE accounts SET feature_flags_ext_1 = feature_flags_ext_1 | 8589934592
   WHERE id IN (16, 18) AND (feature_flags_ext_1 & 8589934592) = 0;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 2 THEN RAISE EXCEPTION 'esperava 2 contas, afetou %', n; END IF;
END $$;
COMMIT;
-- depois: as duas com rich_native = t; 16 = 17179869175, 18 = 17179836407 (se os valores de antes não mudaram)

-- rollback (coluna feature_flags_ext_1, NUNCA feature_flags)
UPDATE accounts SET feature_flags_ext_1 = feature_flags_ext_1 & ~8589934592 WHERE id IN (16, 18);
-- esperado: UPDATE 2; efeito imediato. O cache do motor expira sozinho em até 10 min e é inofensivo sem a flag.
```

---

## Ordem recomendada e o que conferir depois de cada passo

| # | Passo | Conferir depois |
|---|---|---|
| 1 | `WAHA_RICH_NATIVE_ENGINES` no SSM, de preferência **antes** do deploy do #1741, que leva a variável na green | Variável presente no web e no worker; web e worker na imagem do SHA; `/api` 200 nas duas stacks; nada mudou nas caixas, porque a flag está desligada e o cache vazio |
| 2 | Dono do token. **Já está gravado e provado** nas caixas 69 e 56: só rodar a consulta de "sem dono" | 0 linhas para as contas 16 e 18 |
| 3 | Flag nas contas 16 e 18 | (a) até 5 min depois, ou na hora com "Enqueue Now", as duas chaves de cache do wa-hub preenchidas; (b) na caixa 69 e na 56, recarregar o painel: o menu da mensagem mostra **Reagir** e, na nossa mensagem de texto, **Editar**; (c) uma mensagem do cliente chega como antes (texto, mídia, tiques). Os POSTs do conector em `/api/v1/accounts/{16,18}/conversations/…/messages` continuam 2xx no log do web. O worker não mostra erro de webhook para `wa-hub.autonomia.site`; (d) `docker logs chatwoot-web --since 15m 2>&1 \| grep "connector keys dropped"` volta vazio; (e) um teste de reação e de edição pelo painel chega ao celular |

A ordem 1 → 2 → 3 é obrigatória. Com a flag ligada e sem o (1), não acontece nada de errado, só o envio nativo fica de
fora (o cache fica vazio, e Reagir/Editar não aparecem). Com a flag ligada e o (2) faltando, os eventos do conector
são descartados (ver abaixo).

## O que NÃO fazer

- **Não ligar a flag antes do (2) conferido** (0 linhas). Com a flag, a caixa sem dono rejeita as chaves `waha_*` de
  todos, inclusive administrador (`Inbound.from_connector?` → `warn_missing_owner`). Reação, edição, voto, apagada e
  resposta a evento chegariam como texto comum, e só sobraria um log por caixa por hora.
- **Não ligar `c2yViewOnceNotice`** nos apps do wa-hub sem OK separado do Rodrigo. Hoje ele está ausente nos dois apps
  `chatwoot` (69 e 56). O procedimento está no `infra/waha-c2y/README.md`.
- **Não ligar a conta 1** neste roteiro, nem as contas 17, 20, 43 e 44.
- **Não pôr** `WAHA_RICH_NATIVE_ENGINES` na stack Autonom.ia nem incluir o wa-autonomia na lista.
- **Não usar** `rails runner` nem `rails console` em produção, nem para forçar o cron ou ler o cache. Usar a UI do
  Sidekiq e o `psql`.
- **Não editar** o `/opt/chatwoot/.env` da instância nem dar `systemctl restart` no web para "pegar" a variável. O
  caminho é SSM + deploy.
- **Não reescrever** o `/chatwoot/prod/env` do zero. É +1 linha, com a contagem de chaves conferida.
- **Não gravar** o bit em `feature_flags`. A coluna é `feature_flags_ext_1`.
- **Não confiar** no `account_token_owner_user_id` gravado sem a prova de hash numa caixa de conta nova, sobretudo nas
  criadas pelo SSO.
- **Não trocar** a imagem do motor (rollback do wa-hub) sem fazer antes o passo 0 do (1): tirar o motor da lista e
  apagar o cache.
