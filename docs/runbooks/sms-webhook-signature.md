# Runbook — origem dos callbacks de SMS (Twilio e Bandwidth) · #1027

Os callbacks de SMS herdados do Chatwoot aceitavam qualquer chamada. Com a épica #990, um
callback de status passa a marcar destinatário de campanha como entregue ou falhou, então um
evento forjado vira dado errado de campanha. Este runbook liga a checagem de origem sem
derrubar callbacks verdadeiros.

## O que é checado

| Endpoint | Provedor | Checagem |
|---|---|---|
| `POST /twilio/callback` | Twilio (SMS e WhatsApp recebidos) | `X-Twilio-Signature` |
| `POST /twilio/delivery_status` | Twilio (StatusCallback) | `X-Twilio-Signature` |
| `POST /webhooks/sms/:phone_number` | Bandwidth | HTTP Basic Auth do callback |

Fora do escopo: os callbacks de voz do Enterprise (`/twilio/voice/*`).

**Twilio.** A assinatura é validada pelo `Twilio::Security::RequestValidator` da gem oficial
`twilio-ruby`, com o Auth Token do canal. O canal é encontrado do mesmo jeito que o serviço que
processa o callback: `MessagingServiceSid` e, se não achar, `AccountSid` + nosso número (`To` na
mensagem recebida, `From` no status). A URL comparada é a que a Twilio chamou:

- `request.original_url` — o Rack já respeita `X-Forwarded-Proto` e `X-Forwarded-Host`, então
  atrás do ALB (TLS terminado nele) a URL sai `https://…`;
- `FRONTEND_URL` + caminho — a base que o Chatwoot entrega à Twilio no `status_callback`.

Qualquer uma das duas que bater vale. O validador da gem também testa com e sem a porta padrão.

Canal Twilio autenticado por **API Key** (`api_key_sid` preenchido) guarda o segredo da API Key em
`auth_token`. A Twilio assina com o Auth Token principal da conta, que não temos nesse canal:
resultado `missing_credentials` (ver política abaixo).

**Bandwidth.** A Bandwidth não assina callbacks de mensagem; ela envia usuário e senha em HTTP
Basic Auth, configurados na *application*. A credencial esperada vem de, nesta ordem:

1. `provider_config['callback_username']` e `provider_config['callback_password']` do canal;
2. `BANDWIDTH_CALLBACK_USERNAME` e `BANDWIDTH_CALLBACK_PASSWORD` (uma credencial para todos os canais).

O canal checado é o que o evento atualiza (`to` do primeiro evento), o mesmo que o
`Webhooks::SmsEventsJob` usa.

Como configurar na Bandwidth: Dashboard → **Applications** → a application de mensagens do canal
→ autenticação do callback (usuário e senha) → salvar. Depois, gravar o mesmo par no canal
(console Rails, uma operação por canal, com aprovação do Rodrigo por ser escrita em produção):

```ruby
ch = Channel::Sms.find(<id>)
ch.update!(provider_config: ch.provider_config.merge('callback_username' => '<usuário>', 'callback_password' => '<senha>'))
```

Nunca colar a senha em chat, log ou commit.

## Modos

`SMS_WEBHOOK_SIGNATURE_MODE`:

| Valor | Comportamento |
|---|---|
| `off` | Sem checagem (igual a antes do #1027). |
| `log` (padrão) | Checa e registra o resultado; **sempre processa**. |
| `enforce` | Assinatura/credencial inválida ou ausente → `401` e o evento não é processado. |

`SMS_WEBHOOK_UNVERIFIABLE_POLICY` (só vale em `enforce`) — o que fazer quando **não há como
checar**: canal não encontrado, canal Twilio por API Key, canal Bandwidth sem credencial.

| Valor | Comportamento |
|---|---|
| `allow` (padrão) | Processa e registra `missing_credentials`/`channel_not_found`. |
| `reject` | Responde `401`. |

Decisão: `allow` por padrão. Rejeitar o que não dá para checar derrubaria em silêncio os canais
por API Key e todo Bandwidth sem credencial configurada. Canal não encontrado não muda nada mesmo
quando processado (o serviço descarta). Passar para `reject` só depois que o log mostrar zero
`missing_credentials` em tráfego legítimo.

## Log

Uma linha por callback, sem número de telefone, SID, assinatura, credencial ou texto:

```
[SmsWebhookSignature] provider=twilio endpoint=delivery_status mode=log result=invalid_signature channel_id=12 action=processed
```

`result`: `valid`, `invalid_signature`, `missing_signature`, `missing_credentials`, `channel_not_found`.
`action`: `processed` ou `rejected`. `valid` sai em `info`; o resto em `warn`.

Contagem (os logs do Rails vão para o stdout do container; confirmar o destino do stdout na
stack antes de rodar — o nome do grupo de logs não está neste repositório):

```sh
# logs em arquivo/stdout capturado
grep -F '[SmsWebhookSignature]' <arquivo> | awk '{for(i=1;i<=NF;i++) if(index($i,"result=")==1 || index($i,"provider=")==1) printf "%s ", $i; print ""}' | sort | uniq -c
```

CloudWatch Logs Insights (se o stdout for para o CloudWatch):

```
fields @timestamp, @message
| filter @message like '[SmsWebhookSignature]'
| parse @message 'provider=* endpoint=* mode=* result=* channel_id=* action=*' as provider, endpoint, mode, result, channel_id, action
| stats count(*) by provider, endpoint, result, channel_id
```

Canais Twilio por API Key (consulta só leitura, para saber quem ficará `missing_credentials`):

```sql
SELECT id, account_id, medium FROM channel_twilio_sms WHERE api_key_sid IS NOT NULL AND api_key_sid <> '';
```

## Plano de ativação

Mudança de autenticação em webhook: **cada passo em produção exige OK do Rodrigo.**

1. **Deploy com `log`** (padrão; nenhuma variável nova). Nada muda para quem chama.
2. **Observar 7 dias** com a consulta acima. Critério para seguir: em tráfego real,
   `invalid_signature` e `missing_signature` = 0 por canal. Se aparecer em canal legítimo,
   investigar a URL (proxy, host, `FRONTEND_URL`) antes de seguir — não ligar `enforce`.
   Anotar os canais com `missing_credentials` (API Key, Bandwidth sem credencial).
3. **Ligar `enforce`**, no mesmo procedimento do release #990:
   1. backup do parâmetro SSM `/chatwoot/prod/env` de cada stack (versão anterior anotada +
      cópia fora do SSM);
   2. acrescentar **uma** chave: `SMS_WEBHOOK_SIGNATURE_MODE=enforce`;
   3. conferir a contagem de chaves (+1, nada removido);
   4. rodar de novo o deploy no **mesmo SHA** para as instâncias lerem o `.env`;
   5. validar: `/health`, um SMS de teste por canal Twilio (entrada e status) e o log mostrando
      `result=valid action=processed`; nenhum `action=rejected` em canal legítimo.
4. (Opcional, depois) `SMS_WEBHOOK_UNVERIFIABLE_POLICY=reject` quando não houver mais canal
   `missing_credentials` legítimo. Mesmo procedimento (+1 chave).

## Rollback

| Problema | Ação | Tempo |
|---|---|---|
| Callback legítimo recusado (`action=rejected`) | Trocar no SSM para `SMS_WEBHOOK_SIGNATURE_MODE=log` (ou restaurar a versão anterior do parâmetro) e rodar o deploy no mesmo SHA | ~15 min |
| Qualquer problema no código novo | `SMS_WEBHOOK_SIGNATURE_MODE=off` pelo mesmo procedimento | ~15 min |
| Problema geral após o deploy | Workflow de deploy da stack com `action=rollback`, `confirm_production=true` | ~5 min |

Abortar e executar o rollback se: `/health` falhar, a contagem de chaves do SSM cair, ou aparecer
`action=rejected` em canal legítimo.

Não conte com reenvio de callback recusado (Twilio e Bandwidth não garantem): um status perdido
na janela deixa a mensagem no estado anterior, e uma mensagem recebida recusada pode não chegar —
por isso o critério do passo 2 é zero inválido antes do `enforce`.
