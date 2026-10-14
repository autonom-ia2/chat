# WhatsApp Híbrido no Chat2You — Resumo Funcional

## Objetivo

Permitir que uma mesma caixa de WhatsApp no Chat2You utilize dois transportes no mesmo número:

- **WhatsApp Oficial / Cloud API** como conexão principal.
- **WhatsApp API / WAHA** como conexão auxiliar via QR Code.

Para o atendente, continua existindo **uma única conversa** no Chat2You.

## Como será a conexão

1. O administrador conecta primeiro o **WhatsApp Oficial**.
2. O Chat2You confirma que a Cloud está funcionando, o número está em **Coexistência** e a conta está saudável.
3. Na configuração da própria caixa oficial aparece a nova aba **WhatsApp API**.
4. O administrador clica em **Conectar WhatsApp API**.
5. O Chat2You cria automaticamente uma sessão no **WAHA** usando o mesmo número.
6. O sistema mostra o QR Code.
7. O administrador lê o QR pelo WhatsApp Business.
8. O Chat2You confirma que o número conectado no WAHA é o mesmo número da Cloud.
9. A conexão híbrida é ativada.

Não será necessário criar e administrar uma segunda caixa de atendimento.

## Lógica de funcionamento

| Situação | Transporte |
| --- | --- |
| Cliente envia mensagem | **Cloud / Oficial** |
| Agente responde dentro de 24h | **Cloud / Oficial** |
| Agente responde depois de 24h | **WAHA / WhatsApp Web** |
| Template aprovado | **Cloud / Oficial** |
| WhatsApp Flow, catálogo e recursos Meta | **Cloud / Oficial** |
| Recurso disponível apenas no WhatsApp Web | **WAHA** |
| Cloud falha antes de enviar e a falha é comprovadamente segura | **WAHA como fallback** |
| Não é possível saber se a Cloud chegou a enviar | **Não reenviar automaticamente** |

## Regra principal

A **Cloud é dona da conversa**.

O WAHA é apenas um **segundo transporte de envio**.

Continuam na caixa oficial:

- histórico;
- contato;
- responsável;
- equipe;
- CRM;
- IA/bot;
- automações;
- etiquetas;
- SLA;
- relatórios.

## Exemplo

O cliente escreve às 10h e o Chat2You recebe pela **Cloud Oficial**.

O atendente responde às 11h. Como ainda está dentro da janela de 24 horas, a resposta sai pela **Cloud**.

Dois dias depois, o atendente escreve na mesma conversa. A janela oficial está fechada. O Chat2You percebe isso automaticamente e envia pelo **WAHA**, sem trocar de conversa.

## Interface

Na caixa oficial:

    Configurações
    Colaboradores
    Horário
    CSAT
    Configuração
    Saúde da conta
    WhatsApp API    ← nova aba

Antes de conectar:

    Conexão híbrida

    WhatsApp Oficial    ● Conectado
    Coexistência        ● Ativa

    WhatsApp API        ○ Não conectado

    [ Conectar WhatsApp API ]

Depois:

    WhatsApp Oficial    ● Saudável
    WhatsApp API        ● Conectado

    Roteamento automático

    Dentro de 24h       Oficial
    Fora de 24h         WhatsApp API
    Templates           Oficial
    Fallback seguro     Ativado

## Identificação na conversa

Cada mensagem enviada poderá indicar discretamente o transporte utilizado:

- **Oficial**
- **WhatsApp API**
- **WhatsApp API · fallback**

## Proteção contra duplicidade

Quando uma mensagem for enviada pelo WAHA, a Meta pode devolver essa mesma mensagem para a Cloud por causa da Coexistência.

O Chat2You deverá reconhecer que o envio WAHA e o echo Cloud representam **a mesma mensagem** e manter apenas uma bolha na conversa.

## Segurança do fallback

Não faremos:

    Cloud deu qualquer erro
            ↓
    manda novamente pelo WAHA

O sistema distinguirá:

- **Falha segura:** existe certeza de que a Cloud não enviou → pode tentar WAHA.
- **Falha definitiva:** número inválido, opt-out, bloqueio etc. → não tenta outro transporte.
- **Falha indeterminada:** não sabemos se a Cloud chegou a enviar → **não haverá fallback automático**.

Essa regra evita mensagem duplicada para o cliente.

## Contato sem telefone utilizável

A Cloud pode operar com identificadores próprios da Meta, como BSUID.

Se não houver telefone resolvível de forma segura:

- a Cloud continua funcionando;
- o WAHA não será usado;
- fora das 24h será necessário template oficial.

Nunca tentaremos descobrir telefone por nome ou aproximação.

## O que já temos

O Chat2You já possui grande parte das peças:

- WhatsApp Cloud;
- Embedded Signup;
- Coexistência;
- janela de 24 horas;
- templates;
- echoes da Meta;
- sincronização de histórico;
- saúde da conta;
- WAHA;
- QR Code;
- reconexão;
- GOWS;
- normalização de números brasileiros.

O desenvolvimento novo é principalmente a camada que decide **qual transporte usar por mensagem** e garante que Cloud e WAHA representem a mesma conversa.

## Primeiro passo técnico

Antes da implementação completa precisamos provar:

> Quando uma mensagem sai pelo WAHA, conseguimos relacionar de forma inequívoca o ID dessa mensagem com o echo/wamid devolvido pela Meta?

Fluxo a validar:

    Chat2You Message
          ↓
    WAHA Message ID
          ↓
    WhatsApp
          ↓
    Meta Cloud Echo / wamid
          ↓
    mesma Message no Chat2You

Só depois dessa correlação estar comprovada avançaremos para o roteamento automático completo.

## Resultado esperado

Para o atendente:

> **Uma caixa. Uma conversa. Um botão de enviar.**

Para o Chat2You:

> Cloud e WAHA trabalhando juntos, escolhendo automaticamente o transporte mais adequado para cada mensagem.

A Cloud continua sendo a conexão principal e oficial. O WAHA adiciona uma segunda capacidade de transporte sem dividir o atendimento em duas caixas.

## Proxy por número (WAHA comum e Híbrido, #1516)

Toda sessão de WhatsApp não oficial no motor sai por um IP da Webshare. Vale igual nas duas stacks (Hub2You e
Autonom.ia). Regra decidida em 14/10/2026:

- **O tipo do número escolhe o plano.** Híbrido → Static Residential (`proxy_subtype` `isp`); WAHA comum → Proxy
  Server (datacenter, `proxy_subtype` `default`). O plano `residential` (rotativo) nunca é usado, nem modo `-rotate`.
- **Sempre IP do Brasil.** Sem IP brasileiro livre no plano, o número fica sem proxy (log de erro); nunca outro país.
- **Um IP por conta, até N números por IP** (`WHATSAPP_PROXY_MAX_NUMBERS_PER_IP`, padrão 3). Número novo reaproveita o
  IP da conta (mesmo plano) que ainda tem vaga; senão pega um IP livre (São Paulo primeiro). Duas contas nunca no mesmo
  IP. A conta vem da caixa (Híbrido: conexão da caixa Cloud; WAHA: canal API `provider=waha`).
- **Cada stack usa só a sua fatia** de cada plano (`WEBSHARE_ISP_PROXY_ADDRESSES`, `WEBSHARE_DATACENTER_PROXY_ADDRESSES`).
  Fatia vazia = nenhum IP (log de erro). Nunca pega IP fora da fatia. Se um IP da fatia some do plano (a Webshare
  trocou), o log avisa alto que a fatia precisa ser atualizada.
- **Número importado** (proxy posto à mão antes do código) só muda de plano ou de conta sozinho com
  `WHATSAPP_PROXY_AUTO_MIGRATE=true`; IP morto ou credencial trocada se corrigem sempre (o número já está quebrado).

**Variáveis de ambiente**

| Variável | Obrigatória | Para quê |
|---|---|---|
| `WHATSAPP_PROXY_ENABLED` | sim, para ligar | Só `true` liga. Desligada (padrão), o comportamento é o de antes: sessão nasce sem proxy, nenhuma regravação de proxy e a reconciliação não roda — mesmo com a chave da Webshare no ambiente. |
| `WEBSHARE_API_KEY` | sim | Chave da API da Webshare. É a única coisa que a importação precisa. |
| `WEBSHARE_ISP_PROXY_ADDRESSES` | sim | IPs (vírgula) do plano isp que esta stack pode usar. Vazia = nenhum IP isp. |
| `WEBSHARE_DATACENTER_PROXY_ADDRESSES` | sim | Idem para o plano datacenter. |
| `WHATSAPP_PROXY_AUTO_MIGRATE` | não | `true` deixa a reconciliação mover número importado de plano/conta. Padrão desligado. |
| `WHATSAPP_PROXY_MAX_NUMBERS_PER_IP` | não | Números da mesma conta por IP. Padrão 3. |
| `WEBSHARE_ISP_PLAN_ID` / `WEBSHARE_DATACENTER_PLAN_ID` | **não use** | O id do plano muda quando a assinatura é editada na Webshare (14/10/2026: 11408796 → 14564104). Sem elas, vale o plano ativo do subtipo (`isp` / `default`), descoberto em `/api/v2/subscription/plan/` e registrado no log. Se estiverem definidas com id que não é plano ativo daquele subtipo, o código alerta e usa a descoberta. |
| `WHATSAPP_PROXY_ALERT_ACCOUNT_ID` | sim | Conta da PLATAFORMA (ex.: 1 na Hub2You) cujos administradores recebem os alertas do proxy como aviso do Guia (conversa, sino, push e e-mail quando urgente). Nunca a conta de um cliente. Sem ela, os alertas ficam só no log (as duas stacks não têm `SENTRY_DSN`). |
| `SENTRY_DSN` | não | Se um dia existir, os alertas também vão para o Sentry. |

**Como funciona**

- A atribuição fica na tabela `whatsapp_proxy_assignments` (sessão, conta, plano, origem `assigned`/`imported`,
  endereço, porta, id da Webshare).
  Usuário e senha do proxy nunca são gravados: vêm da API na hora de configurar a sessão e só vão no corpo do pedido ao
  motor. A tabela guarda apenas um HMAC da credencial, para notar quando a Webshare a troca.
- Caixa WAHA nova e conexão Híbrida nova nascem com proxy. IP livre é o da fatia que não está na tabela nem em uso por
  outra sessão do próprio motor (`GET /api/sessions?all=true`, só o host do proxy; motor fora = nada atribuído).
- Toda regravação de configuração mescla sobre a do motor (chaves desconhecidas e webhook ficam) e nunca manda a chave
  `apps` (o motor mantém os apps da sessão).
- Trocar o proxy de sessão existente (`WhatsappProxy::ApplyJob` + `SessionUpdater`): um job por sessão de cada vez;
  se o motor já tem o proxy e a credencial, nada; senão cópia da configuração → PUT → espera WORKING (até ~3 min) com o
  mesmo número (`me.id`), os mesmos apps e o proxy gravado; falhou, volta a configuração anterior e registra.
- Híbrido: regravar o webhook preserva o proxy que a sessão já tem; a atualização da aba nunca grava proxy na
  requisição — só agenda o ApplyJob (no máximo uma vez por hora por sessão; Redis fora = não agenda); reconectar confere
  se o IP continua valendo e grava junto. O envio de mensagem nunca mexe no proxy.
- Proxy posto à mão sem registro na tabela não é trocado pelo código.
- Sem IP livre, API fora ou sem chave (com o recurso ligado): a sessão é criada sem proxy (não trava o cliente) e o
  log avisa (`[whatsapp_proxy] plano ... sem IP do Brasil livre na fatia desta stack`).
- `WhatsappProxy::ReconcileJob` (a cada 10 minutos): busca cada plano e a lista do motor uma vez; sessão cujo IP saiu
  da lista ou da fatia, ficou inválido, mudou de credencial, é de outro plano (número que trocou de tipo, WAHA ↔
  Híbrido) ou de outra conta é reatribuída e a troca é agendada, no máximo 5 sessões por rodada. IP que sumiu da lista
  é urgente (o número já está fora do ar — visto ao ligar o "High IP Reputation" em 14/10/2026): vai primeiro e sem
  espera; as demais trocas saem com 2 minutos entre elas. Sessão em STARTING/FAILED com IP sumido ou em quarentena é
  reparada; sessão pedindo QR (SCAN_QR_CODE) nunca. Sessão que o motor não tem fica de fora; atribuição sem caixa no
  banco é apagada. Se mais da metade dos IPs sumiu de uma vez, alerta (troca em massa).
- **IP instável** (a Webshare chama de válido, mas a sessão fica caindo — visto em 14/10/2026 na
  hybrid-551142155355): a reconciliação lê o status de cada sessão no motor. Fora de WORKING (STARTING/FAILED) em 2
  rodadas seguidas (~40 min), ou 3 quedas avisadas pelo webhook do Híbrido em 30 min, o IP vai para quarentena por 24 h
  (tabela `whatsapp_proxy_quarantines`; ninguém recebe esse IP) e o número troca de IP no mesmo plano e fatia. No
  máximo uma troca dessas por sessão por dia; se continuar instável, só alerta (o problema não é o proxy).
  SCAN_QR_CODE é aparelho desvinculado: nunca troca, só alerta (uma vez por dia).
- **Falha geral não é IP ruim.** Se mais de 30% dos IPs em uso de um plano (com pelo menos 2) têm sessão fora de
  WORKING na mesma rodada, ou se as sessões SEM proxy do mesmo motor também estão caindo (mais de 30%, pelo menos 2),
  é falha da Webshare, do WhatsApp ou do motor: nenhuma quarentena, nenhuma troca por instabilidade, a contagem zera
  (inclusive as quedas do webhook do Híbrido, ignoradas por 20 min) e sai o alerta `falha_geral` (uma vez por hora).
  IP que sumiu da lista continua sendo reparado (é fato da Webshare).
- **Teto de quarentena:** no máximo 3 IPs por plano em 24 h; acima disso, alerta `teto_de_quarentena` e para de
  quarentenar. A quarentena expira sozinha em 24 h; para soltar antes:
  `bundle exec rails "autonomia:whatsapp_proxy:liberar_quarentena[IP]"`.
- **Alertas**: sempre no log `[whatsapp_proxy][alerta]`; como aviso do Guia para os administradores da conta da
  plataforma (`WHATSAPP_PROXY_ALERT_ACCOUNT_ID`), em pt_BR/en, só com nº de caixa e de conta, plano e IP mascarado
  (`10.20.x.x`) — nunca telefone, nome ou credencial, e nunca para a conta do cliente; e no Sentry, se houver
  `SENTRY_DSN`. Um alerta por código e assunto por hora. Códigos: `plano_esgotado`, `fatia_vazia`,
  `ip_da_fatia_sumiu`, `troca_desfeita`, `volta_falhou`, `sessao_instavel_trocada`, `sessao_instavel_de_novo`,
  `ip_em_quarentena`, `aparelho_desvinculado`, `troca_em_massa`, `plano_configurado_inexistente`, `falha_geral`,
  `teto_de_quarentena` (os de erro chegam como aviso urgente).
- Excluir a conexão Híbrida ou a caixa WAHA tira o número do IP; apagar a conta apaga as atribuições dela.

**Implantação**

1. Deploy com a migration, com `WHATSAPP_PROXY_ENABLED` ausente (nada muda, mesmo com a chave já no ambiente).
2. Em cada stack, importar as atribuições postas à mão, só as do próprio motor:
   `bundle exec rails "autonomia:whatsapp_proxy:importar[/caminho/webshare_assignments.json,hubsegs]"` (Hub2You) ou
   `[...,autonomia]` (Autonom.ia). Idempotente; funciona com o recurso desligado, exige só `WEBSHARE_API_KEY`. A conta
   sai da sessão no banco e o plano do campo `plano` do arquivo; linha cuja sessão não existe na stack, de plano
   desconhecido, cujo IP já é de outra conta ou cujo motor não respondeu é pulada e listada. Só lê o motor (GET): a
   credencial fica marcada como aplicada apenas quando o motor usa de fato aquele IP com a credencial da lista.
3. Definir as fatias das duas stacks (sem IP em comum), `WHATSAPP_PROXY_ALERT_ACCOUNT_ID` e só então ligar
   `WHATSAPP_PROXY_ENABLED=true`. Não definir `WEBSHARE_*_PLAN_ID`. Sessão importada
   num plano que não bate com o tipo (ex.: Híbrido num IP de datacenter) é trocada pela reconciliação.
