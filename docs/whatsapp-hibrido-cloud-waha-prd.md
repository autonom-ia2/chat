# PRD — WhatsApp Híbrido: Cloud/Coexistência + WAHA no Chat2You

**Status:** Proposto para implementação  
**Data:** 2026-10-05  
**Base avaliada:** Chat2You sobre Chatwoot 4.18.0 (v4.18.0-1221-gf5c001261c)  
**Repositório avaliado:** /Users/rodrigosilva/dev/chat2you  
**Escopo:** produto, arquitetura, UX, roteamento, idempotência, observabilidade, testes, rollout e rollback.  
**Fora de escopo:** implementação, merge e deploy.

---

## 0. Decisões do Rodrigo — 2026-10-06

Estas decisões prevalecem sobre o texto original das seções 35, 36, 37 e 48.

### D1 — Risco aceito por opt-in explícito

A rota WAHA só liga depois que um administrador marca, na aba **WhatsApp API**, um toggle de aceite do risco:

> "Entendo que o WhatsApp API usa um transporte não oficial e que o número oficial pode sofrer restrição ou banimento pela Meta."

- Sem o toggle marcado, a conexão pode existir, mas o roteador nunca escolhe WAHA.
- Gravar quem marcou, quando e de qual IP (auditoria). Desmarcar desliga a rota na hora.

### D2 — Humano, bot, automação, follow-up e campanha juntos

Não haverá fase "só humano". Todas as origens de envio podem usar WAHA fora das 24h desde o primeiro piloto; a medição é na prática.

Salvaguardas obrigatórias, que não bloqueiam a decisão mas permitem medir e reagir:

- **Origem registrada em cada tentativa:** `human`, `bot`, `automation`, `crm_follow_up`, `campaign`. Todas as métricas da seção 34 ganham o rótulo `origin`.
- **Liga/desliga por origem** na aba (todas ligadas por padrão). Permite cortar uma origem sem desligar o híbrido inteiro.
- **Limite de vazão por conexão** para envios WAHA (mensagens/minuto, configurável). Campanha não sai em rajada pelo WhatsApp Web.
- Campanha em conexão híbrida usa o mesmo roteador por destinatário: dentro de 24h → Cloud; fora → WAHA (se elegível) ou template.

### D3 — Piloto na conta 1

O spike F0 e o piloto rodam na conta 1. A caixa oficial em Coexistência a usar ainda precisa ser confirmada.

### Lacunas adicionadas à análise original

1. **Gate zero do spike:** comprovar que um número em Coexistência aceita sessão WhatsApp Web (aparelho vinculado) via WAHA e que ela permanece estável. Se não aceitar, o projeto para.
2. **Eco antes da resposta do WAHA:** a tentativa é gravada com o ID pré-gerado (`new_message_id`) **antes** do POST. Eco que chegar com tentativa pendente e sem prova de correlação volta para a fila com atraso curto, em vez de virar mensagem nova.
3. **Fonte dos ✓✓:** quando a mensagem saiu pelo WAHA, o status exibido vem do ACK WAHA até o eco Cloud ser reconciliado; daí em diante prevalece o status mais avançado entre os dois, sem regredir.
4. **Sessão auxiliar sem App Chatwoot do WAHA:** o App instalado por `Waha::InboxProvisioner` criaria uma segunda caixa com todo o inbound. Proibido na sessão híbrida.

---

## 1. Resumo executivo

O Chat2You deve permitir que uma caixa **WhatsApp Oficial / Cloud API em Coexistência** use o **WAHA/WhatsApp Web como transporte auxiliar do mesmo número**, mantendo **uma única conversa operacional, pertencente à Cloud**.

Experiência desejada:

1. O administrador conecta primeiro o WhatsApp Oficial pela Meta e conclui Coexistência.
2. Quando a Cloud estiver saudável e a Coexistência confirmada, aparece na própria caixa oficial uma nova aba **WhatsApp API**.
3. O administrador clica **Conectar WhatsApp API**.
4. O Chat2You cria uma sessão auxiliar no WAHA para o mesmo número, reaproveitando o motor já existente de sessão, QR Code, reconexão, health e normalização.
5. O administrador lê o QR Code.
6. O Chat2You valida que o dispositivo conectado corresponde ao mesmo número da Cloud.
7. Somente depois disso o roteamento híbrido é ativado.

### Política padrão de roteamento

| Situação | Transporte padrão |
| --- | --- |
| Cliente envia mensagem 1:1 | **Cloud / Oficial** |
| Resposta livre dentro da janela de 24h | **Cloud / Oficial** |
| Resposta livre fora da janela de 24h | **WAHA / WhatsApp Web**, se elegível |
| Template aprovado | **Cloud / Oficial** |
| WhatsApp Flow, catálogo, interativo nativo Meta | **Cloud / Oficial** |
| Recurso exclusivo Web | **WAHA / WhatsApp Web** |
| Falha Cloud antes de aceitação inequívoca | **WAHA**, somente se classificada como segura |
| Falha de entrega indeterminada | **Sem fallback automático** |
| WAHA indisponível fora de 24h | **Não tentar texto livre pela Cloud**; oferecer template aprovado |

### Decisão arquitetural principal

**O Core V1 não criará uma segunda Inbox operacional do Chat2You.**

Será criada uma **conexão WAHA auxiliar vinculada à Inbox Cloud**. Nesse modo o WAHA não será dono de uma segunda conversa; será um segundo transporte da mesma mensagem lógica.

Isso evita, por construção:

- duas conversas 1:1 para o mesmo cliente;
- dois ContactInbox;
- automações duplicadas;
- bots duplicados;
- relatórios divididos;
- dois estados de atribuição;
- loops de webhook;
- divergência de status;
- UX com duas caixas para o mesmo número.

A caixa WAHA tradicional continuará existindo e funcionando sem alteração para números que usam apenas WhatsApp API/QR Code.

---

## 2. Problema atual

Hoje o Chat2You possui dois caminhos independentes.

### 2.1 WhatsApp Oficial

- Channel::Whatsapp;
- provider whatsapp_cloud;
- janela de 24 horas;
- templates aprovados;
- Embedded Signup;
- Coexistência;
- saúde do número;
- sincronização de histórico e contatos;
- smb_message_echoes;
- identificadores Meta/BSUID;
- recursos exclusivos da Cloud.

Fora da janela de 24h, uma mensagem livre é atualmente marcada como falha por Whatsapp::SendOnWhatsappService.

### 2.2 WhatsApp API / WAHA

- Channel::Api;
- additional_attributes.provider = waha;
- sessão via QR Code;
- envio/recebimento via WAHA;
- status e reconexão;
- normalização de números brasileiros;
- campanhas próprias;
- sem janela de 24h por padrão.

As duas integrações são hoje caixas independentes.

O problema de produto é permitir que a caixa Cloud use a sessão Web do mesmo número como capacidade auxiliar sem quebrar a Cloud como fonte autoritativa da conversa.

---

## 3. Referência funcional pesquisada

A implementação pública documentada pela Conversa Labs confirma que o padrão é tecnicamente viável:

- Cloud/Coexistência como autoridade de inbound;
- Web como envio/fallback;
- Cloud dentro de 24h;
- Web fora de 24h;
- templates e recursos Meta pela Cloud;
- recursos Web pelo transporte Web;
- identificação visual do transporte;
- reconciliação do eco Cloud após envio Web;
- possibilidade de manter uma única caixa operacional;
- conexão Web somente depois da Cloud estar funcional.

A Conversa Labs é **referência funcional**, não dependência e não fonte de código. O módulo híbrido não foi identificado como código público.

---

## 4. Estado atual comprovado no Chat2You

### 4.1 Janela de mensagens

Arquivo: app/services/conversations/message_window_service.rb

Hoje:

- Channel::Whatsapp → 24 horas;
- Channel::Api → sem prazo, salvo configuração explícita.

A decisão de janela já está centralizada e deve ser reutilizada.

### 4.2 Envio oficial

Arquivo: app/services/whatsapp/send_on_whatsapp_service.rb

Fluxo atual:

    template?           -> Cloud template
    contact info?       -> Cloud
    can_reply?          -> Cloud session message
    fora da janela      -> failed

O ponto de extensão natural é esse serviço.

### 4.3 WAHA

Arquivos principais:

- app/services/waha/client.rb
- app/services/waha/config.rb
- app/services/waha/inbox_provisioner.rb
- app/controllers/api/v1/accounts/waha_inboxes_controller.rb
- app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappApi.vue
- app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConnectionPage.vue

O Chat2You já sabe:

- criar sessão;
- iniciar/reiniciar/logout;
- obter QR;
- consultar estado;
- configurar Apps;
- resolver número;
- limpar sessão;
- operar com WAHA 2026.9.2;
- usar o módulo brazilian-phone-numbers.

### 4.4 Coexistência

O fork atual já trata:

- Embedded Signup com sinal de Coexistência;
- smb_message_echoes;
- sincronização inicial de histórico;
- sincronização de contatos;
- BSUID e identidades alternativas;
- ecos enviados pelo aplicativo;
- saúde do número.

A saúde já persiste:

- is_on_biz_app;
- platform_type;
- status;
- quality rating;
- webhook;
- WABA;
- número.

A própria UI considera Coexistência ativa quando:

    is_on_biz_app == true
    AND
    platform_type == CLOUD_API

Esse será o critério base para habilitar a conexão híbrida.

---

## 5. Objetivos

### O1 — Uma única conversa 1:1

O agente continua trabalhando na conversa da caixa Cloud independentemente do transporte de saída.

### O2 — Escolha automática

O agente não precisa entender janela, provider, QR, Meta ou WAHA para responder normalmente.

### O3 — Cloud permanece principal

Cloud continua sendo:

- autoridade de inbound;
- fonte do histórico operacional;
- origem de templates;
- provider de recursos Meta;
- fonte principal de estado da conversa.

### O4 — WAHA como capacidade auxiliar

WAHA é usado somente quando:

- a regra de roteamento mandar;
- a sessão estiver conectada;
- houver destinatário Web resolvível;
- o tipo de conteúdo for compatível;
- a operação for segura.

### O5 — Zero duplicidade

A mesma mensagem lógica não pode gerar duas bolhas nem dois envios físicos por corrida de jobs, eco Meta ou ACK WAHA.

### O6 — Zero regressão

Caixas não híbridas devem seguir exatamente o comportamento atual.

### O7 — Auditabilidade

Cada mensagem deve responder:

- qual transporte foi escolhido;
- motivo;
- se houve fallback;
- quantas tentativas;
- ID externo;
- resultado.

---

## 6. Não objetivos do Core V1

Não entram no primeiro release:

1. Disparo em massa pelo roteador híbrido.
2. Migração automática de campanhas WAHA existentes.
3. Grupos/comunidades/canais como conversas da Inbox Cloud.
4. Recuperação de todo conteúdo marcado unsupported pela Cloud.
5. Chamadas Web anexadas à conversa Cloud.
6. Conversão automática de Inbox WAHA tradicional existente.
7. Merge de histórico antigo entre duas Inboxes.
8. Inbound Web como failover da Cloud.
9. Fallback após qualquer erro sem classificação.
10. Prometer “economia de template” como funcionalidade oficial Meta.

Itens 3–5 ficam para V2.

---

## 7. Terminologia

**Inbox Cloud:** Inbox oficial Channel::Whatsapp / whatsapp_cloud.

**Conexão auxiliar:** sessão WAHA pertencente à Inbox Cloud híbrida; não é Inbox operacional no Core V1.

**Transporte:** caminho físico de envio: cloud ou waha.

**Mensagem lógica:** uma única linha Message do Chat2You.

**Tentativa de entrega:** uma tentativa da mensagem lógica por um transporte.

**Fallback:** segunda tentativa por outro transporte após falha elegível.

**Aceitação:** provider devolveu evidência inequívoca de aceitação e atribuiu ID.

**Entrega indeterminada:** não é possível provar nem aceitação nem rejeição.

---

## 8. Pré-requisitos

Feature flag de conta:

**whatsapp_hybrid_transport**

Para conectar, todos os gates abaixo são obrigatórios.

### 8.1 Cloud elegível

- Inbox é Channel::Whatsapp;
- provider = whatsapp_cloud;
- credenciais válidas;
- reauthorization_required = false;
- webhook configurado;
- saúde recentemente consultada.

### 8.2 Coexistência comprovada

Obrigatório:

    phone_number_health.is_on_biz_app == true
    phone_number_health.platform_type == "CLOUD_API"

Não inferir Coexistência apenas pelo Embedded Signup.

### 8.3 Cloud operacional

Antes de gerar QR:

- número não pode estar em status bloqueante;
- webhook não pode estar divergente;
- não pode existir erro de autorização;
- health deve ter sido consultado depois do onboarding.

A interface informa que a sincronização inicial da Meta pode levar tempo e que a Cloud precisa estar enviando e recebendo normalmente.

### 8.4 Conflito WAHA

Antes de criar sessão:

- consultar sessão WAHA esperada;
- consultar Apps se ela existir;
- consultar vínculos locais.

Se já houver Inbox WAHA tradicional usando o mesmo número/sessão:

**Core V1 bloqueia adoção automática.**

Mensagem proposta:

> Já existe uma caixa WhatsApp API usando este número. Para evitar duas conversas e automações duplicadas, essa conexão não pode ser reaproveitada automaticamente no modo híbrido.

Conversão segura fica para V1.1/V2.

---

## 9. UX proposta

### 9.1 Local

Configurações → Caixas de Entrada → [Inbox WhatsApp Oficial] → **WhatsApp API**

Nome da aba: **WhatsApp API**

Cabeçalho: **Conexão híbrida**

Subtítulo:

> Use uma conexão auxiliar por QR Code no mesmo número. O Chat2You continua recebendo pela conexão oficial e escolhe automaticamente como enviar cada mensagem.

### 9.2 Estados

#### Verificando

“Verificando Coexistência e saúde da conexão oficial.”

#### Sem Coexistência

> Para usar a conexão auxiliar, este número precisa estar conectado em modo Coexistência com o WhatsApp Business.

#### Cloud com problema

Mostrar motivo específico:

- autorização;
- webhook;
- número desconectado;
- health desatualizado.

#### Pronto para conectar

Exibir:

- Oficial: conectado;
- Coexistência: ativa;
- número mascarado;
- WhatsApp API: não conectado.

CTA: **Conectar WhatsApp API**

Aviso:

> A conexão auxiliar usa WhatsApp Web/QR Code e não é a API oficial da Meta.

#### Aguardando QR

Reutilizar comportamento atual:

- QR;
- expiração;
- regenerar;
- polling;
- instrução “Aparelhos conectados”.

#### Validando número

Depois do scan:

> Confirmando que o aparelho conectado é o mesmo número da conexão oficial.

Se divergente:

- não ativar;
- limpar/desconectar sessão recém-criada;
- registrar falha;
- mostrar esperado/recebido mascarados.

#### Conectado

Mostrar:

- Cloud saudável;
- WhatsApp API conectado;
- engine/version WAHA;
- última verificação;
- política de roteamento;
- Reconectar;
- Desconectar conexão auxiliar.

---

## 10. Política de roteamento

### 10.1 Ordem de decisão

    1. Caixa híbrida ativa?
       não -> fluxo legado
       sim -> continua

    2. É template?
       sim -> Cloud

    3. É recurso exclusivo Meta?
       sim -> Cloud

    4. É recurso exclusivo Web?
       sim -> WAHA, se disponível

    5. Override explícito válido?
       sim -> provider solicitado

    6. Mensagem livre normal?
       dentro de 24h -> Cloud
       fora de 24h -> WAHA, se elegível

### 10.2 Matriz inicial

| Tipo | Dentro 24h | Fora 24h | Observação |
| --- | --- | --- | --- |
| Texto | Cloud | WAHA | Core |
| Imagem | Cloud | WAHA | Core |
| Vídeo | Cloud | WAHA | Core |
| Áudio | Cloud | WAHA | Core |
| Voice note | Cloud | WAHA | Core após teste |
| Documento | Cloud | WAHA | Core |
| Template Meta | Cloud | Cloud | Nunca WAHA |
| Flow Meta | Cloud | Cloud | Nunca WAHA |
| Catálogo/produto Meta | Cloud | Cloud | Nunca WAHA |
| Interactive Meta | Cloud | Cloud | Nunca WAHA |
| Contact-info request Meta | Cloud | Cloud | Nunca WAHA |
| Localização | Cloud | WAHA | após teste |
| VCard | conforme suporte | WAHA | V1.1 |
| Reação | conforme suporte | V1.1 | fora do Core |
| Grupo/comunidade/canal | N/A Cloud | WAHA | V2 |
| Chamada Web | N/A Cloud | WAHA | V2 |

---

## 11. Elegibilidade do destinatário Web

Cloud pode operar com BSUID sem telefone.

WAHA não deve adivinhar um número.

WhatsappHybrid::RecipientResolver deve retornar um destino inequívoco.

Ordem:

1. telefone normalizado do Contact;
2. candidatos já conhecidos pelo Chat2You;
3. resolver existente para números brasileiros;
4. Waha::Client#check_contact_exists;
5. cache por conexão/contato.

Se o contato for somente BSUID:

- web_eligible = false;
- fora de 24h, não tentar WAHA;
- oferecer template Cloud quando disponível.

**Nunca fazer matching por nome.**

---

## 12. Fallback seguro

“Cloud falhou → Web” não significa “qualquer exceção → reenviar”.

### SAFE_FALLBACK

Há prova suficiente de que a primeira tentativa **não foi aceita**.

Exemplos:

- preflight detecta provider indisponível antes do POST;
- credencial já inválida antes do POST;
- rejeição síncrona determinística sem message ID;
- conteúdo rejeitado antes do envio e equivalente Web comprovado.

Pode tentar uma vez no sibling.

### TERMINAL

Segundo transporte não deve ser usado.

Exemplos:

- destinatário inválido;
- bloqueio/política;
- opt-out;
- conteúdo proibido;
- erro que Web não corrige.

### INDETERMINATE

Não é possível saber se houve envio.

Exemplos:

- timeout depois do request iniciar;
- reset de conexão;
- exceção de transporte após write;
- 5xx sem semântica conclusiva;
- provider já devolveu ID e status posterior não é conclusivo.

**Nunca fazer fallback automático.**

UI:

> Não foi possível confirmar a entrega. O Chat2You não reenviou por outro canal para evitar mensagem duplicada.

### Depois de aceitação

Core V1: **não fazer fallback automático após provider devolver ID.**

### Web → Cloud

Se WAHA falhar de forma segura:

- dentro de 24h + conteúdo Cloud compatível → Cloud pode ser fallback;
- fora de 24h → não enviar livre pela Cloud; oferecer template;
- template nunca começa no WAHA.

### Limite

**1 tentativa inicial + 1 fallback automático.**

Sem ping-pong.

---

## 13. Arquitetura

    Cliente
       |
       v
    Meta Cloud / Coexistência
       |
       | inbound
       v
    Inbox Cloud Chat2You
    conversa autoritativa
       |
       | outgoing
       v
    WhatsappHybrid::Router
       |                 |
       v                 v
     Cloud              WAHA
       |                 |
       +--------+--------+
                |
           mesmo cliente

### Princípio

**Inbox não é transporte.**

A Inbox define:

- conversa;
- agente;
- atribuição;
- bot;
- CRM;
- automações;
- relatórios.

O transporte define apenas como a mensagem saiu.

---

## 14. Refatoração WAHA

Não duplicar Waha::InboxProvisioner.

Extrair:

### Waha::SessionLifecycle

Responsável por:

- criar sessão;
- iniciar;
- status;
- QR;
- reconectar;
- logout;
- cleanup;
- validar /me;
- verificar capabilities.

### Waha::InboxProvisioner

Continua usando SessionLifecycle e mantém comportamento atual da Inbox WAHA tradicional.

### WhatsappHybrid::WebProvisioner

Usa SessionLifecycle, mas:

- não cria Channel::Api;
- não cria segunda Inbox;
- não instala App Chatwoot do WAHA no Core V1;
- configura resolver + webhooks técnicos;
- liga sessão a WhatsappHybridConnection.

---

## 15. Webhooks WAHA híbridos

A sessão auxiliar não materializa conversa por App Chatwoot.

Configurar webhook próprio.

Eventos mínimos:

- session.status;
- message.any;
- message.ack.

Posteriores:

- message.revoked;
- message.edited;
- reações;
- chamadas;
- grupos.

### Segurança

- endpoint específico;
- HMAC por conexão;
- secret nunca logado;
- replay protection;
- idempotência de evento;
- limite de corpo;
- rejeitar sessão diferente da esperada.

Endpoint sugerido:

**POST /webhooks/waha/hybrid/:public_id**

public_id não é segredo; HMAC autentica.

---

## 16. Transporte WAHA direto

Criar **Waha::HybridTransport**.

Não depender do App Chatwoot para envio híbrido porque precisamos:

1. ID físico no momento do envio;
2. distinguir aceitação de timeout;
3. controlar idempotência;
4. correlacionar ACK posterior;
5. evitar segunda conversa.

### Extensões em Waha::Client

Adicionar métodos finos:

- new_message_id(session);
- send_text;
- send_image;
- send_video;
- send_voice;
- send_file;
- send_location;
- session_me.

O WAHA 2026.9.2 está acima da versão que introduziu geração prévia de ID e ID fornecido no send para GOWS/NOWEB. Mesmo assim, fazer capability preflight e não confiar apenas na versão.

---

## 17. Identidade de mensagem

Uma mensagem lógica continua sendo uma linha Message.

Usar messages.external_source_ids já existente.

Convenção:

    {
      "whatsapp_cloud": "wamid....",
      "waha": "true_55...@c.us_ABC..."
    }

### source_id

- envio Cloud: continua wamid;
- envio WAHA primeiro: ID WAHA pode ocupar source_id temporariamente;
- depois de eco Cloud comprovado, wamid vira source_id autoritativo;
- ID WAHA permanece em external_source_ids["waha"].

Adicionar índice parcial/expressão para external_source_ids->>'waha', com escopo que evite colisões entre contas/inboxes.

---

## 18. Ledger de tentativas

Criar tabela **whatsapp_hybrid_delivery_attempts**.

Campos:

- id;
- account_id;
- whatsapp_hybrid_connection_id;
- message_id;
- attempt_no;
- transport: cloud/waha;
- reason;
- status;
- fallback_of_id;
- provider_message_id;
- provider_http_status;
- provider_error_code;
- provider_error_subcode;
- error_classification;
- started_at;
- accepted_at;
- completed_at;
- diagnostic_data sanitizado;
- timestamps.

Status:

- planned;
- dispatching;
- accepted;
- server_ack;
- device_ack;
- read;
- played;
- failed;
- unknown.

Razões:

- inside_window;
- outside_window;
- template;
- meta_only;
- web_only;
- manual_override;
- fallback_cloud_to_web;
- fallback_web_to_cloud.

Unique:

- message_id + attempt_no;
- connection_id + transport + provider_message_id quando houver.

---

## 19. Modelo de conexão

Criar **whatsapp_hybrid_connections**.

Campos:

- id;
- public_id;
- account_id;
- cloud_inbox_id único;
- waha_session;
- enabled;
- status;
- inside_window_transport default cloud;
- outside_window_transport default waha;
- automatic_fallback;
- composer_override_enabled;
- safe_fallback_only default true;
- connected_at;
- last_health_at;
- last_error_code;
- last_error_at;
- remote_capabilities jsonb;
- created_by_id;
- updated_by_id;
- segredo HMAC armazenado com mecanismo seguro do projeto;
- timestamps.

Estados:

- provisioning;
- awaiting_qr;
- validating;
- connected;
- degraded;
- disconnected;
- disabled;
- error.

Invariantes:

1. Uma Inbox Cloud tem no máximo uma conexão híbrida ativa.
2. Mesma account.
3. Número WAHA validado deve ser o número Cloud.
4. Não ativar sem Coexistência.
5. Delete da conexão nunca apaga Cloud.
6. Delete da Cloud limpa sessão auxiliar best-effort e audita.

---

## 20. Provisionamento

    Admin
      |
      | Conectar WhatsApp API
      v
    HybridConnectionsController
      |
      +-- feature flag
      +-- valida Cloud
      +-- health
      +-- Coexistência
      +-- conflito WAHA
      +-- cria connection(provisioning)
              |
              v
    WhatsappHybrid::WebProvisioner
              |
              +-- cria sessão
              +-- resolver brasileiro
              +-- webhook híbrido
              +-- start
              |
              v
         awaiting_qr
              |
            scan
              |
              v
          WAHA WORKING
              |
           session/me
              |
       mesmo número?
        /          \
      não          sim
      |             |
    cleanup       connected

Roteamento só ativa em connected.

---

## 21. Envio dentro de 24h

Fluxo:

    Message
      -> SendReplyJob
      -> Whatsapp::SendOnWhatsappService
      -> conexão híbrida ativa?
         não: legado
         sim: Router
      -> can_reply? true
      -> Cloud
      -> wamid
      -> badge Oficial

Nenhuma mudança semântica para a Cloud normal.

---

## 22. Envio fora de 24h

Fluxo:

    Message
      -> Router
      -> can_reply? false
      -> template?
         sim: Cloud
         não:
           WAHA connected?
           recipient resolvível?
           content Web-compatible?
             não: template/erro orientado
             sim:
               pre-generate WAHA id
               persist attempt(dispatching)
               send
               accepted -> external ID + status
               safe fail -> política de fallback/erro

---

## 23. Eco Meta após envio WAHA

Esse é um risco central.

Quando WAHA envia pelo mesmo número em Coexistência, a Meta pode entregar smb_message_echoes na Cloud.

Hoje um wamid desconhecido pode virar nova mensagem outgoing.

Criar **WhatsappHybrid::EchoReconciler** antes da criação normal do echo.

Passos:

1. chega smb_message_echoes;
2. identifica Inbox híbrida;
3. tenta provar relação com Message WAHA já aceita;
4. se comprovada:
   - não cria Message nova;
   - grava external_source_ids["whatsapp_cloud"];
   - normaliza source_id para wamid;
   - preserva external_source_ids["waha"];
   - atualiza attempt;
   - atualiza mesma bolha.
5. se não for possível provar:
   - não fazer matching agressivo;
   - seguir estratégia definida pelo Spike #1.

**Nunca casar só por texto e horário quando houver mais de um candidato.**

---

## 24. Spike obrigatório de correlação

Antes do roteador completo, executar prova técnica isolada.

Objetivo: comprovar relação entre:

- ID pré-gerado/retornado pelo WAHA GOWS 2026.9.2;
- message.any;
- message.ack;
- smb_message_echoes.id da Meta.

Experimento com número de teste em Coexistência:

1. gerar ID WAHA;
2. enviar texto com ID fornecido;
3. capturar response WAHA;
4. capturar message.any;
5. capturar message.ack;
6. capturar smb_message_echoes;
7. repetir em dois contatos;
8. repetir 30 mensagens;
9. repetir texto, imagem, documento e áudio;
10. documentar relação.

### Gate

Core V1 não vai para produção até existir método de correlação com falso positivo zero no conjunto de teste.

Se a relação não for determinística:

- testar ID custom no GOWS;
- avaliar metadado suportado;
- usar estado pendente;
- não lançar matching heurístico como solução final.

---

## 25. WAHA message.any no híbrido

Pode ser recebido sem criar Inbox.

Finalidades:

- correlação;
- diagnóstico;
- reply-to futuro;
- base para recuperação V2.

Não fazer no Core V1:

- criar ContactInbox;
- criar Conversation;
- disparar bot;
- disparar automação;
- contar como inbound operacional.

Dados de correlação podem ficar em Redis com TTL; persistir somente IDs vinculados à Message.

---

## 26. ACK WAHA

message.ack possui estados:

- ERROR;
- PENDING;
- SERVER;
- DEVICE;
- READ;
- PLAYED.

Criar **WhatsappHybrid::WahaAckProcessor**.

Lookup por external_source_ids["waha"].

Mapeamento:

| WAHA | Chat2You |
| --- | --- |
| ERROR | failed |
| PENDING | estado técnico pendente |
| SERVER | sent |
| DEVICE | delivered |
| READ | read |
| PLAYED | read + detalhe no attempt |

Usar Messages::StatusUpdateService para preservar transições forward-only.

---

## 27. Idempotência

### Antes da rede

1. lock da Message;
2. buscar tentativa existente;
3. accepted → não reenviar;
4. unknown → não reenviar automaticamente;
5. criar attempt dispatching;
6. commit;
7. só então chamar provider.

### WAHA

- gerar provider ID antes do envio quando suportado;
- persistir ID antes do POST;
- enviar com o mesmo ID;
- retry técnico somente com semântica idempotente comprovada.

### Cloud

Distinguir:

- aceita com wamid;
- rejeitada;
- transporte desconhecido.

### ActiveJob

Retry não pode criar novo envio se tentativa anterior estiver accepted ou unknown.

---

## 28. Serviço de envio

Recomendação: não alterar SendReplyJob::CHANNEL_SERVICES.

Manter:

Channel::Whatsapp → Whatsapp::SendOnWhatsappService

Dentro do serviço, delegar ao híbrido somente se connection ativa; caso contrário executar exatamente o fluxo legado.

Templates e recursos especiais continuam nos serviços Cloud atuais.

---

## 29. Estado visual de entrega

A UI precisa distinguir:

- Enviando;
- Enviada;
- Entregue;
- Lida;
- Falhou;
- Entrega não confirmada.

“Entrega não confirmada” pode ser estado do attempt exposto pelo serializer, sem necessariamente ampliar o enum global Message no primeiro release.

---

## 30. Badge de transporte

Toda saída híbrida mostra discretamente:

- **Oficial**
- **WhatsApp API**
- **WhatsApp API · fallback**
- **Oficial · fallback**

Tooltip:

- transporte;
- motivo;
- horário;
- tentativa.

IDs técnicos somente em diagnóstico admin.

---

## 31. API interna proposta

GET /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid

Retorna:

- eligibility;
- Cloud health resumido;
- connection status;
- WAHA status;
- routing config;
- capabilities;
- erro sanitizado.

POST /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid

Provisiona de forma idempotente.

GET /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid/qr

POST /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid/reconnect

PATCH /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid

DELETE /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_hybrid

Delete exige confirmação e não apaga Cloud.

---

## 32. Permissões

Somente admin autorizado pode:

- criar conexão;
- renovar sessão;
- alterar roteamento;
- habilitar fallback;
- habilitar override;
- desconectar.

Agente usa override somente quando habilitado e permitido.

---

## 33. Feature flags

### Conta

**whatsapp_hybrid_transport**

Controla:

- aba;
- endpoints;
- Router;
- badges;
- webhook híbrido.

### Runtime kill switch

**WHATSAPP_HYBRID_ROUTING_ENABLED**

OFF:

- conexão permanece;
- novos envios não usam WAHA híbrido;
- Cloud volta ao legado;
- fora de 24h volta ao template/restrição oficial.

### Shadow mode

**WHATSAPP_HYBRID_SHADOW_MODE**

ON:

- Router calcula decisão;
- registra métrica;
- não troca transporte real.

Usar antes do piloto.

---

## 34. Observabilidade

Counters:

- route_decision_total{transport,reason};
- delivery_attempt_total{transport,status};
- fallback_total{from,to,result};
- uncertain_delivery_total{transport};
- echo_reconcile_total{result};
- waha_ack_total{ack};
- connection_state_total{state};
- recipient_resolution_total{result}.

Histograms:

- provider_accept_latency;
- ack_server_latency;
- ack_device_latency;
- ack_read_latency;
- echo_reconcile_latency.

Alertas P0:

- envio duplicado comprovado;
- mensagem para destinatário incorreto;
- echo reconciliado com Message errada.

Alertas P1:

- echo ambiguous acima de limiar;
- unknown acima de limiar;
- WAHA flapping;
- fallback subindo abruptamente;
- Cloud e Web degradados.

Logs não devem registrar token, API key, HMAC secret, conteúdo integral ou telefone completo por padrão.

---

## 35. Segurança e conformidade

WAHA/WhatsApp Web é transporte não oficial.

O produto deve:

1. deixar isso explícito;
2. exigir opt-in administrativo;
3. auditar quem ativou;
4. permitir kill switch;
5. não apresentar como extensão oficial da janela Meta;
6. não usar fallback para burlar opt-out, bloqueios ou políticas;
7. não fazer disparo em massa pelo Router do Core V1.

Os termos atuais do WhatsApp Business App restringem aplicações que interagem com o serviço sem consentimento escrito do WhatsApp. O risco contratual/operacional é risco de produto conhecido.

A política oficial continua exigindo template aprovado fora da janela de 24h quando o envio ocorre pela Plataforma oficial.

---

## 36. Campanhas

Core V1:

- Cloud Campaigns continuam Cloud;
- WhatsApp API Campaigns continuam em Inboxes WAHA tradicionais;
- conexão híbrida não vira caixa de campanha;
- disparo em massa não passa por WhatsappHybrid::Router.

Objetivo: continuidade 1:1, não broadcast.

---

## 37. Bots e automações

Como há uma única Inbox operacional:

- bot permanece Cloud;
- assignment permanece Cloud;
- regras permanecem Cloud;
- CRM permanece Cloud;
- webhooks Chat2You permanecem Cloud;
- SLA/relatórios permanecem Cloud.

Transporte não dispara segundo message_created.

Echo reconciliado atualiza Message existente.

---

## 38. Reply-to / citação

Dentro Cloud: comportamento atual.

Quando WAHA é usado:

- usar reply_to Web somente se existir mapeamento comprovado para ID WAHA;
- se não existir, enviar sem reply nativo;
- manter referência interna do Chat2You;
- telemetria native_reply_degraded.

Não usar heurística insegura para descobrir ID WAHA de mensagem antiga.

---

## 39. Mídia

Core deve suportar:

- image;
- video;
- audio;
- document;
- voice note.

Validar:

- URL acessível pelo WAHA ou upload/base64;
- limite;
- MIME;
- timeout;
- ausência de logs do conteúdo.

Teste real obrigatório com ActiveStorage atual.

---

## 40. Reações, edições e revogações

Fora do Core V1.

Dependem de correlação bidirecional robusta de IDs.

---

## 41. Inbound durante falha Cloud

Core V1 continua Cloud-authoritative.

Se Cloud parar de entregar webhook e WAHA continuar recebendo:

- message.any não vira Conversation automaticamente;
- health/telemetry registram;
- admin pode ser alertado.

Inbound Web failover fica para V2.

---

## 42. V2 — recuperação de conteúdo

Evolução possível:

Quando Cloud recebe placeholder unsupported:

1. manter Message Cloud;
2. aguardar cópia Web;
3. provar equivalência;
4. enriquecer Message existente;
5. disparar automação uma única vez após estabilização.

Nunca criar segunda bolha.

---

## 43. V2 — superfícies Web

Depois do Core:

- grupos;
- comunidades;
- canais;
- status;
- broadcast lists;
- chamadas Web;
- eventos Web específicos.

Pode exigir Inbox Web física ou abstração de subcanal; definir em PRD separado.

---

## 44. Migração de Inbox WAHA existente

Não automatizar no Core V1.

V1.1 pode oferecer **Converter para conexão auxiliar**, mas somente com:

1. snapshot sessão;
2. snapshot Apps;
3. campanhas ativas;
4. bots/automação;
5. relatório de conflitos;
6. aprovação explícita;
7. rollback.

Até lá, conflito bloqueia.

---

## 45. Testes

### Unit — Router

- sem híbrido → legado;
- dentro 24h → Cloud;
- fora 24h → WAHA;
- template fora 24h → Cloud;
- Meta-only → Cloud;
- WAHA desconectado fora 24h;
- BSUID-only;
- override Cloud fora 24h recusado;
- safe fallback Cloud → WAHA;
- indeterminate Cloud → sem fallback;
- terminal → sem fallback;
- Web safe fail dentro janela → Cloud;
- Web safe fail fora janela → template.

### Unit — ledger

- sequência única;
- lock concorrente;
- retry accepted não envia;
- retry unknown não envia;
- máximo um fallback;
- status forward-only.

### Unit — WAHA

- ID pré-gerado;
- texto;
- mídia;
- timeout;
- 4xx;
- 5xx;
- capability ausente;
- número inexistente.

### Unit — echo

- match determinístico;
- echo duplicado;
- echo antes ACK;
- ACK antes echo;
- sem match;
- ambíguo;
- echo externo real do celular.

### Request/controller

- feature flag;
- permissão;
- non-Cloud;
- non-coexistence;
- health error;
- conflito WAHA;
- provision idempotente;
- QR;
- reconnect;
- disconnect;
- HMAC inválido.

### Frontend

- aba por eligibility;
- todos os estados;
- expiração QR;
- status conectado;
- política;
- badge;
- aviso de risco;
- sem regressão tabs atuais.

### E2E real mínimo

| Caso | Resultado |
| --- | --- |
| inbound cliente | uma conversa Cloud |
| reply <24h | Cloud |
| reply >24h | WAHA |
| template >24h | Cloud |
| WAHA send → Meta echo | uma bolha |
| Cloud safe failure | um fallback |
| Cloud timeout | zero fallback |
| WAHA cai | degraded |
| WAHA volta | reconecta |
| restart Chat2You | vínculo preservado |
| restart WAHA | vínculo preservado |
| worker retry | sem duplicidade |
| dois sends concorrentes | sem duplicidade |
| BSUID sem telefone | WAHA não usado |
| mídia | transporte correto |
| leitura destinatário | status atualizado |

---

## 46. Teste de caos

Antes de produção:

1. cortar Cloud no meio do POST;
2. matar WAHA no meio do send;
3. reiniciar worker depois de dispatching;
4. atrasar ACK;
5. atrasar echo;
6. duplicar echo;
7. duplicar ACK;
8. inverter ACK/echo;
9. desconectar QR;
10. re-parear;
11. reiniciar WAHA;
12. indisponibilizar Redis;
13. disparar dois jobs da mesma Message.

Critério:

**nenhum cenário pode enviar duas mensagens físicas sem ação explícita do operador.**

---

## 47. Critérios de aceite

### Produto

- [ ] Admin conecta WAHA dentro da Inbox Cloud.
- [ ] QR aparece sem segunda Inbox operacional.
- [ ] Mesmo número validado.
- [ ] Uma conversa operacional.
- [ ] Dentro 24h Cloud.
- [ ] Fora 24h WAHA quando elegível.
- [ ] Template sempre Cloud.
- [ ] Badge de transporte.
- [ ] Falha indeterminada não duplica.

### Dados

- [ ] Uma Message lógica.
- [ ] IDs Cloud/WAHA correlacionados.
- [ ] Attempts persistidos.
- [ ] ACK WAHA atualiza a mesma Message.
- [ ] Echo Meta não duplica send WAHA.

### Operação

- [ ] feature flag por conta.
- [ ] kill switch.
- [ ] shadow mode.
- [ ] métricas.
- [ ] logs sanitizados.
- [ ] rollback aditivo.

### Regressão

- [ ] Cloud não híbrida igual.
- [ ] WAHA tradicional igual.
- [ ] campanhas iguais.
- [ ] history sync igual.
- [ ] bots/CRM/automação sem evento duplicado.

---

## 48. Rollout

### Fase 0 — Spike

Provar:

- ID WAHA ↔ Meta echo;
- ACK;
- mídia;
- same-number;
- GOWS 2026.9.2.

### Fase 1 — Schema + shadow

Router decide, envio continua legado.

### Fase 2 — Piloto

Uma conta + uma Inbox.

- fallback automático OFF;
- rota fora de 24h ativa;
- telemetria alta;
- rollback pronto.

### Fase 3 — Fallback seguro

Somente classes SAFE_FALLBACK comprovadas.

### Fase 4 — Contas selecionadas

Feature flag por conta.

### Fase 5 — Ampliação

Somente com:

- zero duplicidade;
- echo estável;
- unknown aceitável;
- runbook validado.

---

## 49. Rollback

Kill switch:

**WHATSAPP_HYBRID_ROUTING_ENABLED=false**

Resultado:

- Cloud continua;
- sessão auxiliar pode permanecer;
- Router deixa de usar Web;
- fora de 24h volta ao fluxo oficial/template.

Migrations aditivas.

Rollback de aplicação não faz logout WAHA automaticamente.

---

## 50. Arquivos atuais a preservar/estender

Backend:

- app/services/whatsapp/send_on_whatsapp_service.rb
- app/services/conversations/message_window_service.rb
- app/services/whatsapp/incoming_message_base_service.rb
- app/jobs/webhooks/whatsapp_events_job.rb
- app/services/waha/client.rb
- app/services/waha/config.rb
- app/services/waha/inbox_provisioner.rb
- app/controllers/api/v1/accounts/waha_inboxes_controller.rb
- app/models/message.rb
- app/services/messages/status_update_service.rb

Frontend:

- app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue
- app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConnectionPage.vue
- app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue
- componentes de Message;
- i18n.

Documentação:

- Central de Ajuda WhatsApp;
- .env.example se houver ENV nova;
- runbook híbrido;
- troubleshooting.

---

## 51. Novos componentes sugeridos

    app/models/whatsapp_hybrid_connection.rb
    app/models/whatsapp_hybrid_delivery_attempt.rb

    app/services/whatsapp_hybrid/eligibility.rb
    app/services/whatsapp_hybrid/router.rb
    app/services/whatsapp_hybrid/delivery_service.rb
    app/services/whatsapp_hybrid/cloud_transport.rb
    app/services/whatsapp_hybrid/web_transport.rb
    app/services/whatsapp_hybrid/web_provisioner.rb
    app/services/whatsapp_hybrid/recipient_resolver.rb
    app/services/whatsapp_hybrid/echo_reconciler.rb
    app/services/whatsapp_hybrid/waha_event_processor.rb
    app/services/whatsapp_hybrid/waha_ack_processor.rb
    app/services/whatsapp_hybrid/error_classifier.rb
    app/services/whatsapp_hybrid/capabilities.rb

    app/controllers/api/v1/accounts/whatsapp_hybrid_connections_controller.rb
    app/controllers/webhooks/waha_hybrid_controller.rb

    app/javascript/dashboard/api/whatsappHybrid.js
    app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/WhatsappHybridPage.vue

Nomes são proposta; implementação deve seguir convenções reais.

---

## 52. Decomposição em Issues/PRs

### Issue 1 — Spike identidade WAHA ↔ Meta echo

Entrega:

- relatório;
- fixtures;
- matriz de IDs;
- go/no-go.

### Issue 2 — Modelo + flags

- migrations;
- models;
- policies;
- serializers;
- kill switches;
- audit.

### Issue 3 — Extrair ciclo de sessão WAHA

- SessionLifecycle;
- zero regressão standalone;
- testes preservados.

### Issue 4 — Provisionamento híbrido

- API;
- eligibility;
- QR;
- same-number;
- HMAC.

### Issue 5 — Transporte WAHA direto

- adapters;
- mídia;
- provider ID;
- error taxonomy.

### Issue 6 — Router + ledger

- decisão;
- locks;
- idempotência;
- safe fallback.

### Issue 7 — Echo + ACK

- Cloud echo;
- WAHA ACK;
- external IDs;
- índice.

### Issue 8 — UI WhatsApp API

- estados;
- QR;
- health;
- routing;
- aviso;
- disconnect/reconnect.

### Issue 9 — Badges + diagnóstico

- transporte por mensagem;
- delivery uncertain;
- detalhe admin.

### Issue 10 — Observabilidade + runbooks

- métricas;
- alertas;
- troubleshooting;
- rollback.

### Issue 11 — E2E + caos

Gate de ativação.

---

## 53. Dependências

    #1 Spike
       |
       +--> #2 Modelo
       +--> #3 WAHA lifecycle
       |      |
       |      +--> #4 Provisionamento
       |
       +--> #5 Web Transport
              |
              +--> #6 Router
                     |
                     +--> #7 Reconciliation
                            |
                  +---------+---------+
                  v                   v
                #8 UI              #9 Badges
                  +---------+---------+
                            v
                          #10 Obs
                            |
                            v
                          #11 E2E

---

## 54. Decisões não delegáveis ao implementador

1. Cloud é autoridade de inbound no V1.
2. Não existe segunda Inbox operacional no Core V1.
3. Fora de 24h livre vai WAHA somente se elegível.
4. Template sempre Cloud.
5. Falha indeterminada nunca gera fallback automático.
6. Máximo um fallback.
7. Broadcast/campaign não passa pelo Router V1.
8. BSUID sem telefone não usa WAHA.
9. Matching ambíguo nunca reconcilia.
10. Feature é opt-in.
11. Roteamento tem kill switch.
12. Migrations são aditivas.
13. Echo atualiza; não cria segunda bolha.
14. WAHA standalone não pode regredir.

---

## 55. Questões abertas que exigem evidência

### Q1 — Relação exata entre ID GOWS e smb_message_echoes.wamid

Resolver no Spike #1.

### Q2 — ID custom fornecido ao GOWS aparece de forma determinística no eco Meta?

Resolver no Spike #1.

### Q3 — Quais erros Cloud são SAFE_FALLBACK?

Criar allowlist baseada em documentação, testes e logs reais.

### Q4 — Media URL atual é acessível pelo WAHA?

Testar ActiveStorage real.

### Q5 — Reply-to quando a origem não possui ID WAHA?

Core degrada sem reply nativo; V1.1 enriquece.

### Q6 — Fallback automático por default?

Recomendação:

- piloto OFF;
- após métricas ON somente para safe failures;
- fora de 24h é rota normal Web, não fallback.

---

## 56. Riscos

### R1 — Termos/política WhatsApp

**Alto.**

Mitigação:

- opt-in;
- aviso;
- sem broadcast no híbrido;
- kill switch;
- natureza não oficial explícita.

### R2 — Duplicidade física

**Crítico.**

Mitigação:

- ledger;
- provider ID pré-gerado;
- unknown sem retry;
- echo reconciler;
- locks;
- caos.

### R3 — Duplicidade de conversa

**Crítico.**

Mitigação:

- sem segunda Inbox operacional;
- WAHA shadow não cria Conversation.

### R4 — Destinatário incorreto

**Crítico.**

Mitigação:

- resolver por telefone;
- zero matching por nome;
- BSUID-only bloqueado no Web.

### R5 — Queda WAHA

**Médio.**

Cloud continua dentro da janela/templates.

### R6 — Cloud indisponível

**Médio/alto.**

V1 dá continuidade de saída em cenários seguros, não failover completo de inbound.

### R7 — Race de echo

**Alto.**

Mitigação:

- spike;
- Redis/DB idempotency;
- matching estrito.

---

## 57. Métricas de sucesso

- mensagens duplicadas: **0**;
- destinatário incorreto: **0**;
- echo incorretamente reconciliado: **0**;
- replies fora de 24h elegíveis via WAHA: alvo >99% com sessão saudável;
- unknown: alvo <0,1%, investigando cada ocorrência no piloto;
- echo reconciliation: >99,9% para send Web;
- regressão não híbrida: 0;
- regressão WAHA standalone: 0.

---

## 58. Recomendação de produto

A proposta de uma aba **WhatsApp API dentro da caixa Oficial** é a melhor UX para o Chat2You.

Visual:

    Configurações da caixa
    [ Configurações ]
    [ Colaboradores ]
    [ Horário ]
    [ CSAT ]
    [ Configuração ]
    [ Saúde da conta ]
    [ WhatsApp API ]   <- novo

Antes:

    Conexão híbrida

    WhatsApp Oficial   ● Conectado
    Coexistência       ● Ativa

    WhatsApp API       ○ Não conectado

    [ Conectar WhatsApp API ]

Depois:

    WhatsApp Oficial   ● Saudável
    WhatsApp API       ● Conectado

    Roteamento automático
    Dentro de 24h      Oficial
    Fora de 24h        WhatsApp API
    Templates           Oficial
    Fallback seguro     Ativado

    [ Reconectar ] [ Desconectar conexão auxiliar ]

O usuário não administra duas caixas para obter a capacidade.

---

## 59. Estratégia recomendada

Ordem:

**Spike → infraestrutura → rota fora de 24h sem fallback → reconciliação → UI → fallback seguro → rollout.**

Não começar pela UI.

Os riscos reais são:

- identidade da mensagem;
- eco Meta;
- idempotência;
- falha indeterminada.

---

## 60. Fontes externas pesquisadas

### Conversa Labs

- https://ajuda.conversalabs.com.br/hc/ajuda/articles/inboxes-channels-whatsapp-hybrid-inbox-en
- atualização observada: 2026-09-14.

### Chatwoot

- https://www.chatwoot.com/hc/user-guide/articles/1754940076-whatsapp-templates
- https://www.chatwoot.com/features/whatsapp-for-business
- https://www.chatwoot.com/hc/user-guide/articles/1677492191-adding-inboxes

### WAHA

- https://waha.devlike.pro/docs/how-to/events/
- https://waha.devlike.pro/docs/how-to/receive-messages/
- https://waha.devlike.pro/docs/how-to/engines/
- https://waha.devlike.pro/docs/overview/changelog/
- https://github.com/devlikeapro/waha/releases

### WhatsApp / Meta

- https://business.whatsapp.com/policy/
- https://www.whatsapp.com/legal/WhatsApp-Terms-for-WhatsApp-Business-App
- https://www.whatsapp.com/legal/WhatsApp-Terms-for-WhatsApp-Business-Platform

---

## 61. Conclusão

A feature é viável e o fork atual já possui grande parte das peças difíceis:

- Cloud;
- Embedded Signup;
- Coexistência;
- echo;
- history sync;
- health;
- BSUID;
- janela;
- templates;
- WAHA;
- QR;
- reconnect;
- GOWS;
- normalização BR.

O trabalho novo não é “integrar dois WhatsApps”.

É criar com segurança:

1. uma conexão auxiliar WAHA ligada à Inbox Cloud;
2. um Router por mensagem;
3. um ledger de tentativas;
4. correlação Cloud ↔ WAHA;
5. reconciliação de echo/ACK;
6. UX e telemetria.

O principal gate técnico é comprovar a correlação de IDs WAHA/GOWS com smb_message_echoes da Meta. Esse spike deve anteceder o roteador definitivo.
