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
| `WHATSAPP_PROXY_ENABLED` | sim, para ligar | Só `true` liga. Desligada (padrão): sessão nasce sem proxy, nenhuma troca, reconciliação parada — mesmo com a chave da Webshare no ambiente. O que muda mesmo desligada está na lista logo abaixo da tabela. |
| `WEBSHARE_API_KEY` | sim | Chave da API da Webshare. É a única coisa que a importação precisa. |
| `WEBSHARE_ISP_PROXY_ADDRESSES` | sim | IPs (vírgula) do plano isp que esta stack pode usar. Vazia = nenhum IP isp. |
| `WEBSHARE_DATACENTER_PROXY_ADDRESSES` | sim | Idem para o plano datacenter. |
| `WHATSAPP_PROXY_AUTO_MIGRATE` | não | `true` deixa a reconciliação mover número importado de plano/conta. Padrão desligado. |
| `WEBSHARE_RESERVED_PROXY_ADDRESSES` | não | IPs (vírgula) da Webshare usados por outra integração, que nunca são dados a número de WhatsApp, mesmo dentro da fatia. Ex.: `104.165.153.115` (plano ISP), reservado para o Instagram. O registro das reservas fica fora do código, com as credenciais de operação (`webshare_reservas.json`). |
| `WHATSAPP_PROXY_MAX_NUMBERS_PER_IP` | não | Números da mesma conta por IP. Padrão 3. |
| `WEBSHARE_ISP_PLAN_ID` / `WEBSHARE_DATACENTER_PLAN_ID` | **não use** | O id do plano muda quando a assinatura é editada na Webshare (14/10/2026: 11408796 → 14564104). Sem elas, vale o plano ativo do subtipo (`isp` / `default`), descoberto em `/api/v2/subscription/plan/` e registrado no log. Se estiverem definidas com id que não é plano ativo daquele subtipo, o código alerta e usa a descoberta. |
| `WHATSAPP_PROXY_ALERT_ACCOUNT_ID` | sim | Conta da PLATAFORMA (ex.: 1 na Hub2You) cujos administradores recebem os alertas do proxy como aviso do Guia (conversa, sino, push e e-mail quando urgente). Nunca a conta de um cliente. Sem ela, os alertas ficam só no log (as duas stacks não têm `SENTRY_DSN`). |
| `SENTRY_DSN` | não | Se um dia existir, os alertas também vão para o Sentry. |

**Com `WHATSAPP_PROXY_ENABLED` desligada** (o estado do deploy), muda só isto em relação a antes do #1516:

- a regravação da configuração da sessão do Híbrido (webhook faltando, reconectar) mescla sobre a configuração do motor
  — o proxy que a sessão já tem fica — e o PUT não leva mais `apps: null` (a chave `apps` é omitida; o motor mantém os
  apps);
- erros do motor nunca levam usuário/senha de proxy (pedido ou resposta) e JSON inválido vira erro só com a classe;
- apagar a caixa WAHA ou a conexão Híbrida apaga a atribuição de proxy da sessão (com o recurso desligado não há
  nenhuma);
- nenhuma chamada à Webshare, nenhum proxy na criação, nenhuma troca, reconciliação e contagem de quedas desligadas.
  A rake de importação funciona (precisa só da chave).

**Como funciona**

- A atribuição fica na tabela `whatsapp_proxy_assignments` (sessão, conta, plano, origem `assigned`/`imported`,
  endereço, porta, id da Webshare, IP anterior, falhas). Usuário e senha do proxy nunca são gravados: vêm da API na
  hora de configurar a sessão e só vão no corpo do pedido ao motor. A tabela guarda apenas um HMAC da credencial.
- Caixa WAHA nova e conexão Híbrida nova nascem com proxy. IP livre é o da fatia que não está na tabela, nem em uso por
  outra sessão do próprio motor (`GET /api/sessions?all=true`, só o host), nem reservado, nem em quarentena. Webshare
  fora na criação: a caixa nasce sem proxy, a atribuição fica **pendente** (alerta `caixa_sem_proxy`) e a reconciliação
  tenta de novo, com recuo.
- Sessão que já existe sem atribuição **nunca** ganha proxy sozinha (nem abrindo a aba, nem reconectando): só pela
  importação ou por `bundle exec rails "autonomia:whatsapp_proxy:migrar[SESSAO]"` — uma por vez, com a mesma trava do
  ApplyJob (ocupada, recusa), confere o `/timelock` antes e recusa com restrição ativa ou sem conseguir conferir;
  qualquer fim que não seja a troca aplicada (desfeita, recusada, erro, Ctrl-C) apaga a atribuição.
- Toda regravação de configuração mescla sobre a do motor e nunca manda a chave `apps`. O motor guarda só as chaves de
  configuração que conhece (descarta as outras).
- Trocar o proxy de sessão existente (`WhatsappProxy::ApplyJob` + `SessionUpdater`): um job por sessão (trava com token,
  solta só por quem pegou); se o motor já tem o proxy e a credencial, nada; sessão pedindo QR ou parada (STOPPED)
  nunca é tocada; senão cópia → PUT → espera WORKING (até ~3 min) com o mesmo número (`me.id`), os mesmos apps e o proxy
  gravado. Falhou: a configuração anterior volta no motor, a atribuição volta inteira ao estado anterior (IP, plano,
  conta, origem), conta uma falha e entra em **recuo** (10 min, 30 min, 2 h, 6 h, 24 h) — job repetido que já estava na
  fila sai sem fazer nada; alerta `troca_desfeita` na primeira falha e ao chegar no recuo máximo. Se nem a volta der
  certo (`volta_falhou`, urgente), o motor é relido e a tabela fica exatamente como ele mostra (proxy novo, antigo, ou
  — ilegível — sem credencial e com o anterior guardado, para a convergência resolver). Confirmação sem PUT (o motor já
  tinha o proxy) só zera o recuo se ele já tinha vencido.
- **Convergência: o motor é a fonte da verdade.** A cada rodada a reconciliação compara o proxy que o motor usa
  (host:porta e credencial) com a tabela. Mesmo IP: a tabela registra a credencial do motor. IP diferente com a sessão
  WORKING num IP válido da lista, da mesma conta e plano: a **tabela** passa a ser o motor (sem PUT, sem reinício).
  IP do motor sumido, inválido ou de outra conta, ou sessão fora de WORKING: troca normal para o IP da tabela. Motor sem
  proxy: reaplica. Troca agendada há menos de 30 min é esperada (não conta como divergência).
- Híbrido: a atualização da aba nunca grava proxy na requisição — só agenda o ApplyJob, e só para sessão que já tem
  atribuição, fora do recuo, no máximo uma vez por hora (Redis fora = não agenda). Reconectar grava junto o IP
  atribuído, também só com atribuição e só com a trava livre (outra troca em andamento: não grava; a convergência
  resolve depois). O envio de mensagem nunca mexe no proxy.
- Proxy posto à mão sem registro na tabela não é trocado pelo código.
- `WhatsappProxy::ReconcileJob` (a cada 10 minutos; decisão em `WhatsappProxy::Triage`): lê o motor e cada plano uma
  vez. Nunca toca sessão que o motor não tem, parada (STOPPED) ou pedindo QR; sessão em recuo espera (e não ocupa
  vaga). No máximo 5 trocas por rodada:
  - **IP sumido da lista**: urgente (sem espera) se a sessão também está fora de WORKING — visto ao ligar o "High IP
    Reputation" em 14/10/2026; se está WORKING, só depois de duas leituras seguidas, sem urgência;
  - **plano ou conta errados** (número que trocou de tipo) e **credencial trocada**: só com a sessão WORKING; número
    importado só muda de plano/conta com `WHATSAPP_PROXY_AUTO_MIGRATE=true`;
  - **pendente**: com a sessão WORKING, atribui e aplica; sem IP ainda, conta falha (recuo);
  - um plano com erro na Webshare não para o outro (sai da rodada inteira, uma contagem por rodada); erro em duas
    rodadas seguidas gera `webshare_indisponivel` (a contagem só zera quando a lista do plano respondeu de fato); se
    mais da metade dos IPs sumiu de uma vez, `troca_em_massa`.
- **IP instável** (a Webshare chama de válido, mas a sessão fica caindo — visto em 14/10/2026 na
  hybrid-551142155355): só conta a sessão que **caiu** — estava WORKING na rodada anterior; FAILED antiga não conta e
  não queima IP bom. Fora de WORKING em 2 rodadas seguidas, ou 3 quedas avisadas pelo webhook do Híbrido em 30 min, o
  número troca de IP no mesmo plano e fatia e o IP vai para quarentena por 24 h (tabela `whatsapp_proxy_quarantines`) —
  mas só se houver para onde mover — checado antes do corte das vagas, só leitura; sem destino nem põe quarentena e
  avisa `quarentena_sem_destino` (ou `motor_indisponivel`, se o motor não respondeu) uma vez por dia. No máximo uma troca dessas por sessão por dia (`sessao_instavel_de_novo`,
  uma vez por dia) e 3 quarentenas por plano em 24 h (`teto_de_quarentena`). Os números irmãos (mesma conta, mesmo IP) não saem
  à força: trocam se eles próprios caírem; WORKING, trocam sem urgência, um por rodada. A quarentena expira sozinha;
  para soltar antes: `bundle exec rails "autonomia:whatsapp_proxy:liberar_quarentena[IP]"`.
- **Falha geral não é IP ruim** (`WhatsappProxy::Outage`). Mede queda recente: só conta a sessão que estava WORKING na
  rodada anterior (status guardado no Redis por 30 min) e agora está fora. Se, entre essas, mais de 30% dos IPs de um
  plano caíram (pelo menos 2), ou mais de 30% das sessões sem nenhum proxy do motor caíram (pelo menos 2, e só com pelo
  menos 5 sessões sem proxy que estavam WORKING), é falha da Webshare, do WhatsApp ou do motor: nenhuma quarentena,
  nenhuma troca por instabilidade, contagem zerada (inclusive as quedas do webhook). Alerta `falha_geral` no começo e
  `falha_geral_fim` no fim, um de cada por episódio, e `falha_geral_em_curso` a cada 6 h enquanto durar (duração e
  quantos números seguem fora). Dura (sem prazo) enquanto as que caíram seguem fora acima do mesmo
  limite: falha longa não vira "IP instável" por tempo. Quando a maioria volta, termina; as que seguem fora só podem
  virar "instáveis" depois de voltar a WORKING ao menos uma vez (até lá, nada de quarentena; fora há mais de 24 h,
  `sessao_fora_24h` uma vez por dia). Na rodada em que um episódio termina não se abre outro. O episódio fica 24 h no
  Redis, renovado a cada rodada; se sumir sem terminar, `falha_geral_perdida`. Sem a rodada anterior (primeira rodada, Redis vazio) só observa. IP sumido
  continua sendo reparado.
- **Alertas**: sempre no log `[whatsapp_proxy][alerta]`; como aviso do Guia para os administradores da conta da
  plataforma (`WHATSAPP_PROXY_ALERT_ACCOUNT_ID`), em pt_BR/en, só com nº de caixa e de conta, plano e IP mascarado
  (`10.20.x.x`) — nunca telefone, nome ou credencial, e nunca para a conta do cliente; e no Sentry, se houver
  `SENTRY_DSN`. Um alerta por código e assunto por hora; `aparelho_desvinculado` é um resumo por dia (quantas sessões
  pediram QR no dia anterior). Códigos: `plano_esgotado`, `fatia_vazia`, `ip_da_fatia_sumiu`, `troca_desfeita`,
  `volta_falhou`, `sessao_instavel_trocada`, `sessao_instavel_de_novo`, `ip_em_quarentena`, `quarentena_sem_destino`,
  `aparelho_desvinculado`, `troca_em_massa`, `plano_configurado_inexistente`, `falha_geral`, `falha_geral_em_curso`,
  `falha_geral_fim`, `falha_geral_perdida`, `sessao_fora_24h`, `motor_indisponivel`, `teto_de_quarentena`,
  `webshare_indisponivel`, `caixa_sem_proxy`, `atribuicao_invalida` (os de erro chegam como aviso urgente).
- A lista da Webshare vem inteira ou dá erro (nunca parcial: com lista parcial, IP em uso pareceria sumido).
- Excluir a conexão Híbrida ou a caixa WAHA tira o número do IP; apagar a conta apaga as atribuições dela.

**Implantação**

1. Deploy com a migration, com `WHATSAPP_PROXY_ENABLED` ausente (só as diferenças listadas acima). No blue-green a
   migration roda (`db:chatwoot_prepare`) antes de o código novo subir, então a tabela já existe quando ele roda.
2. Em cada stack, importar as atribuições postas à mão, só as do próprio motor:
   `bundle exec rails "autonomia:whatsapp_proxy:importar[/caminho/webshare_assignments.json,hubsegs]"` (Hub2You) ou
   `[...,autonomia]` (Autonom.ia). Idempotente; funciona com o recurso desligado, exige só `WEBSHARE_API_KEY`. A conta
   sai da sessão no banco e o plano do campo `plano` do arquivo; linha cuja sessão não existe na stack, de plano
   desconhecido, cujo IP já é de outra conta ou cujo motor não respondeu é pulada e listada. Só lê o motor (GET): a
   credencial fica marcada como aplicada apenas quando o motor usa de fato aquele IP com a credencial da lista.
3. Definir as fatias das duas stacks (sem IP em comum), `WHATSAPP_PROXY_ALERT_ACCOUNT_ID` e só então ligar
   `WHATSAPP_PROXY_ENABLED=true`. Não definir `WEBSHARE_*_PLAN_ID`. Sessão importada
   num plano que não bate com o tipo (ex.: Híbrido num IP de datacenter) é trocada pela reconciliação.
