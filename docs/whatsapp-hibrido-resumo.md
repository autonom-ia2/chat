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
  gravado. Sessão que já estava fora de WORKING (IP morto): basta o PUT aceito e o proxy gravado conferido no GET; não
  espera WORKING e nunca volta (voltar para o IP morto não ajuda) — falhou, conta a falha e mantém o IP novo. Antes do
  PUT, o IP que o motor usa (se for conhecido da lista) fica guardado para a volta; sem estado guardado, a volta mantém
  o IP atual e só conta a falha. Falhou: a configuração anterior volta no motor, a atribuição volta inteira ao estado anterior (IP, plano,
  conta, origem), conta uma falha e entra em **recuo** (10 min, 30 min, 2 h, 6 h, 24 h) — job repetido que já estava na
  fila sai sem fazer nada; alerta `troca_desfeita` na primeira falha e ao chegar no recuo máximo. Se nem a volta der
  certo (`volta_falhou`, urgente), o motor é relido e a tabela fica exatamente como ele mostra (proxy novo, antigo, ou
  — ilegível — sem credencial e com o anterior guardado, para a convergência resolver). Confirmação sem PUT (o motor já
  tinha o proxy) só zera o recuo se ele já tinha vencido.
- **Convergência: o motor é a fonte da verdade.** A cada rodada a reconciliação compara o proxy que o motor usa
  (host:porta e credencial) com a tabela. Mesmo IP: a tabela registra a credencial do motor (credencial mascarada:
  nada é regravado nem reaplicado, alerta `credencial_mascarada` uma vez). IP diferente com a sessão WORKING num IP
  oferecível do plano da sessão (na lista, válido, BR, na fatia, sem quarentena, não reservado), sem outro número de
  fora da conta nele no motor e dentro do limite por IP: a **tabela** passa a ser o motor (sem PUT, sem reinício).
  Atribuição importada cujo motor passou a usar proxy fora da Webshare: vira externa (o código para de gerenciar e
  nunca sobrescreve; alerta `proxy_manual_detectado` uma vez). Qualquer outro IP diferente, ou sessão fora de WORKING:
  troca normal para o IP da tabela. Motor sem proxy: reaplica. Não compara troca agendada há menos de 30 min nem
  sessão com troca em andamento (trava).
- Híbrido: a atualização da aba nunca grava proxy na requisição — só agenda o ApplyJob, e só para sessão que já tem
  atribuição, fora do recuo, no máximo uma vez por hora (Redis fora = não agenda). Reconectar grava junto o IP
  atribuído, também só com atribuição e só com a trava livre; trava ocupada ou Redis fora: grava só o webhook que
  faltava, sem mexer no proxy (a convergência resolve depois). O envio de mensagem nunca mexe no proxy.
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
  `falha_geral_fim`, `falha_geral_perdida`, `sessao_fora_24h`, `motor_indisponivel`, `credencial_mascarada`,
  `proxy_manual_detectado`, `teto_de_quarentena`,
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

## Pausar sem desvincular e avisos da aba (#1487)

- **Pausar WhatsApp API** (com confirmação) para a sessão no motor (`POST /api/sessions/{nome}/stop`), sem logout: o
  aparelho continua vinculado. A pausa fica em `whatsapp_hybrid_connections.paused_at`.
- Enquanto pausada: o roteador nunca escolhe o WhatsApp API (`Connection#routable?` e `Router#web_allowed_for?`
  respondem não). Para o follow-up do CRM é o mesmo que conexão caída (`MessagingWindow#hybrid_web_available?` responde
  não): o que for compor depois de 24 horas vai como modelo, e o toque já previsto para sair como texto livre pelo
  WhatsApp API falha com `whatsapp_api_unavailable` (o executor recompõe). `ensure_session!` não cria nem religa a
  sessão; `refresh!` só lê (não grava configuração nem proxy, o que reiniciaria a sessão); a parada não vira alerta de
  queda nem sinal de IP ruim, mesmo que o aviso do motor chegue com o estado ainda "conectado". Sessão STOPPED continua
  intocada pela automação de proxy (#1516). O Guia mostra "pausado pelo administrador" como informação, não como queda.
- Pausar lê o motor antes (só 404 conta como "sem sessão"; outra falha recusa e nada é gravado), grava a pausa e só
  então pede o stop; recusa do motor desfaz a pausa; sem resposta, consulta de novo e mantém a pausa só se a sessão
  aparecer parada. Pausar e retomar usam a mesma trava por sessão da troca de proxy (ocupada: "tente de novo").
- **Retomar** faz `start` da mesma sessão, sem QR. Se o WhatsApp desvinculou o aparelho nesse meio-tempo, o motor pede
  QR e a aba mostra o fluxo de reconectar normal. Só recria a sessão quando o motor responde que ela não existe (404);
  falha do motor mantém a pausa, sem recriar nada (recriar soltaria o IP da sessão). Gerar novo QR Code também desfaz
  a pausa.
- **Desconectar** uma conexão pausada: o `TeardownSessionJob` religa a sessão parada e espera ela subir antes do logout
  (logout em sessão parada pode não tirar o aparelho do celular); se não subir a tempo, faz logout e exclusão assim
  mesmo.
- Avisos (só informam, nada bloqueia): a ordem de conexão antes do QR (oficial conectada → app aberto → QR); lembrete
  fixo de abrir o app WhatsApp Business ao menos a cada 14 dias (o motor não informa quando o app foi aberto); e o
  mesmo número ligado em outra caixa WhatsApp API comum (WAHA) da mesma conta, só quando a sessão dessa caixa está viva
  no motor (conectada, subindo ou com QR; uma consulta à lista de sessões, guardada por 1 minuto; motor fora = sem
  aviso). O número vem do aparelho da sessão quando o motor informa, senão do nome da sessão; celular brasileiro com e
  sem o 9 (antes de 6 a 9) é o mesmo número (`WhatsappHybrid::SameNumberInboxes`).

## Mensagem rica nativa pelo WhatsApp API (#1709, fase 1)

Atrás da flag por conta `whatsapp_rich_native` ("Mensagens ricas nativas pelo WhatsApp API (Híbrido e WAHA)"),
desligada por padrão; ligar é com a Orquestração. Sem a flag, nada muda: opções, localização e contato saem como texto
pelo WhatsApp API, com a marca "Enviado como texto" (#1555).

Com a flag, quando a mensagem sai pelo WhatsApp API (rota direta ou plano B do 131047):

| Formato do painel (`rich_message`) | Sai pelo motor | Observação |
|---|---|---|
| `options` | `sendList` (lista) | Sempre lista, mesmo com até 3 opções sem descrição: o motor GOWS não tem botões (`sendButtons` = 501). Botão padrão "Ver opções" (i18n, idioma da conta) quando falta `button`. |
| `location` | `sendLocation` | Nome e endereço vão juntos no título (o motor só tem título); sem os dois, "Localização". |
| `contact` | `sendContactVcard` | `wa_id` vai como `whatsappId` só quando veio. |
| `link_button`, `location_request`, `flow`, `link_preview` | texto, como antes | |

**Limites da lista** (não cabe: sai texto, como antes): título da linha até 24, descrição até 72, botão até 20, no
máximo 10 linhas, tudo em uma linha só. O título da lista é o cabeçalho; sem cabeçalho, é o corpo, que então precisa
caber em 60 caracteres e numa linha só.

**`rowId` com referência.** Cada linha leva `<id da opção>|<id da mensagem no Chatwoot>` (separador fixo `|`, só quando
cabe nos 200 do `rowId`; senão, só o id da opção). Lista com algum id de opção que tem `|` não sai nativa: sai texto,
como antes; assim todo `rowId` nativo com `|` é nosso, com a referência numérica no fim. O `list_reply.id` da Meta volta igual
ao `rowId` enviado (teste de 16/10/2026: veio "manha", o `rowId` mandado). Na volta, o recebimento separa pelo último
`|` (sem regex) e grava `selected_option.id` SEMPRE com o id ORIGINAL da opção (o robô lê o mesmo de antes), confira
ou não a referência (ex.: lista de uma conversa anterior), com ou sem a flag. `in_reply_to` = a mensagem referida, se
ela é lista nativa desta conversa (uma consulta por id; vale até com a flag desligada depois do envio). Senão, com a
flag, `in_reply_to` = a última lista nativa da conversa com uma opção de `id` igual ao da opção (comparação exata; 50
últimas mensagens nossas). Sem a flag, não há busca. Resposta que aponta uma mensagem (`context`) nunca passa por isso.

**Resultado do envio.**
- Saiu nativa: `rich_message_sent_as: 'native'` (a bolha mostra o formato) e nenhuma marca de texto. A marca e o
  `source_id` são gravados sem as validações do modelo (a de rajada recusaria numa conversa movimentada); falha nessa
  gravação vai para o log e o tracker, sem derrubar o envio.
- Id físico: `source_id` e Redis guardam o id curto (`3EB0...`), o mesmo formato do texto, que é o que o ack do webhook
  híbrido procura. `sendLocation` e `sendContactVcard` levam o id gerado antes. O `sendList` não aceita id antes: vale o
  da resposta (`id._serialized` termina no id físico, conferido no teste real de 16/10/2026).
- Recusa explícita do motor (4xx ou 501), em que nada saiu: vai UMA vez o texto de sempre, com a marca 'text'. As
  recusas do WhatsApp que o envio já trata (463, 475) seguem como hoje. Se o `source_id` não voltar ao id gerado antes
  do texto, nada sai: a mensagem fica `failed` com o motivo próprio e resultado 'failed' (gravados sem validação), o
  erro vai ao tracker, a sessão é relida (como depois de todo erro do motor) e a campanha recebe a queda (manda o
  modelo, como em toda falha certa). Se nem essa gravação passar (banco fora), o erro original é relançado e o job
  falha à vista (Sidekiq e tracker); o `source_id` provisório impede um novo envio pelo motor.
- 5xx, conexão fechada ou sem resposta: pode ter saído. Fica incerto, com o aviso de conferir no celular, sem texto por
  cima.
- Antes do pedido da lista, o `source_id` recebe um valor provisório e único (`waha-native-pending-<id da mensagem>`):
  com `source_id`, um novo SendReplyJob não reenvia a mensagem se algo quebrar depois do pedido. A resposta troca pelo
  id físico; na recusa explícita, volta o id gerado, que o texto leva ao motor. Nem o ack (Redis pelo id físico) nem a
  ligação da resposta (id da mensagem no `rowId`) leem o provisório.
- **Limitação aceita:** a lista sem resposta (incerta) ou com resposta sem id fica com o `source_id` provisório; o ack
  dela não a encontra (o log traz a classe da resposta e o id da mensagem). Como a Meta não ecoa lista enviada pelo
  aparelho, não há eco que a duplique.

**O que a tela e o código consultam.**
- A conversa traz `whatsapp_api_rich_native` (lista de tipos) ao lado de `whatsapp_api_reply`, no JSON e no evento ao
  vivo. Duas linhas no core, no mesmo padrão do `whatsapp_api_reply` (jbuilder da conversa e
  `Conversations::EventDataPresenter`), que calculam o `whatsapp_api_reply?` uma vez e o reaproveitam. Vazia sem a flag,
  dentro da janela, com a conexão pausada ou caída. Sem consulta por conversa: a flag é lida da conta já carregada ou
  da conta do request (`Current.account`).
- `RichMessages.delivery_mode` responde `:native` só com `message:` (argumento opcional novo) e a mesma regra do envio
  (roteador `route_for` com a origem da mensagem, e tradutor). Sem a mensagem, o modo de antes (`:text`), para qualquer
  tipo. Quem consulta hoje: só o aviso de agendamento (`Crm::BookingV2::Notices::Button`, com `link_button`).

**Chaves de `content_attributes`:** `rich_message` (pedido, não muda), `rich_message_sent_as` ('native' ou 'text'),
`in_reply_to` (id numérico da lista respondida), `selected_option` (`{ id, title }`, id original da opção) e as
`whatsapp_transport*` do WebTransport (não mudam).

**Código.** `Waha::RichNative` (flag, marca, referência do `rowId`, `types_for`; comum à fase 2, caixa WAHA comum),
`Waha::RichPayload` (tradução, independente do Híbrido), `Waha::Client#send_list`/`#send_location`/
`#send_contact_vcard`, e `WhatsappHybrid::RichNative` (prepends em `WhatsappHybrid::WebTransport`, `RichMessages` e
`Whatsapp::IncomingMessageBaseService`, em `config/initializers/whatsapp_rich_native.rb`). `web_transport.rb` e o
`echo_reconciler` não foram editados. Decisão e validação: `docs/audit/2026-10-16-1709-ricas-waha-fase1.md`.

## Mensagem rica nativa na caixa WAHA comum (#1709, fase 2)

Na caixa WAHA comum (`Channel::Api` com provider `waha`), quem envia é o **conector do WAHA** (customizado por outro
construtor). O chat2you não chama o motor: decide na criação, entrega o pedido no webhook da caixa e lê a volta.

**Decisão única, na criação** (`before_create`, `Waha::RichNative::ApiInboxDecision`). A mensagem é nativa só se
todas valerem; senão, `rich_message_sent_as: 'text'`, como hoje:
- flag `whatsapp_rich_native` na conta;
- o `webhook_url` da caixa começa (`start_with?`, com a barra final) pela URL de um motor listado em
  `WAHA_RICH_NATIVE_ENGINES` (URLs separadas por vírgula; vazia por padrão = tudo em texto);
- o motor declara o tipo em `GET /api/server/version`, campo `autonomia.rich_native` (ex.:
  `{ patch: 'c2y-rich-1', rich_native: ['options','location','contact'], list_reply: true }`); `options` só com
  `list_reply: true`. Quem lê o motor é o `Waha::EngineCapabilitiesRefreshJob` (cron a cada minuto, no segundo 25),
  que guarda por 10 min; a criação de mensagem e a lista de conversas só leem esse cache, nunca chamam o motor. Sem
  valor no cache (motor nunca lido, ou falhando há mais de 10 min) = nenhum tipo. Todos os motores da lista usam a
  mesma chave (`WAHA_API_KEY`); 401/403 vai ao rastreador de erros com o nome do motor. O webhook da caixa sempre tem
  caminho (`<motor>/webhooks/chatwoot/...`): `webhook_url` igual à raiz do motor não casa e fica em texto;
- o tradutor monta o pedido (`Waha::RichPayload.build`, com o `content` cru);
- e as travas de sempre da caixa API: vai ao canal, caixa com webhook, conversa sem trava de transmissão, formato sem
  erro.

**Saída (contrato `waha_native`).** Mensagem marcada `native`, no `message_created` do webhook da caixa:
`content_attributes.waha_native = { kind: 'sendList' | 'sendLocation' | 'sendContactVcard', payload: {...} }`, sem
`session` e `chatId` (o conector os põe). Na lista, `rowId` = `<id da opção>|<id da mensagem>`. O `content` continua o
texto de reserva (corpo + versão em texto): motor sem o conector customizado manda o texto completo. A entrega lê só a
marca: se a capacidade do motor mudar entre a criação e a entrega, marca e pedido seguem iguais. O `message_updated`
não leva o pedido.

**Entrada (contrato `waha_list_reply`).** O conector cria a mensagem RECEBIDA com
`content_attributes.waha_list_reply = { row_id, title }`. Na criação (`Waha::RichNative::ListReply`, só com a flag), a
chave SEMPRE sai. Ela só vira escolha se uma lista NATIVA nossa da MESMA conversa e caixa ofereceu essa opção: com
referência, a lista citada; sem referência, a última lista nativa da conversa com esse id. Aí grava
`selected_option = { id original da opção, title }` (separado pelo último `|`, sem regex) e `in_reply_to` = a lista
(se o conector não preencheu; `in_reply_to_external_id` só com o id físico, nunca o provisório). Sem lista que confira
(forja, lista de outra conversa), a mensagem fica como texto comum.

**Forja.** Pela API de mensagens, com ou sem a flag: `waha_native` e `rich_message_sent_as` saem sempre;
`waha_list_reply` só fica em mensagem recebida (é como o conector cria), e mesmo assim só vira escolha com uma lista
nativa conferida.

**Reenvio.** O reenvio sai pelo `message_updated`, que não leva o pedido ao motor: o cliente recebe o texto, e a marca
da mensagem passa de 'native' a 'text'.

**Tela e consultas.** `whatsapp_api_rich_native` da conversa e `RichMessages.delivery_mode(message:)` respondem também
pela caixa WAHA, com as mesmas condições (os tipos que o motor declara). Na lista de conversas, sem consulta ao banco
(caixa e canal já carregados; conta do request). Sem migration. Decisão e validação:
`docs/audit/2026-10-16-1709-ricas-waha-fase2.md`.
