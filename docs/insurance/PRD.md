# PRD — Cotação de Seguros com AGGER no Chat2You

**Projeto:** Chat2You / Autonom.ia  
**Repositório principal:** `github.com/autonom-ia2/chat`  
**Upstream:** `chatwoot/chatwoot`  
**Status:** Especificação para início de desenvolvimento  
**Data:** 2026-09-03  
**Owner de produto:** Autonom.ia  
**Módulo:** `Cotação`  
**Provider inicial:** AGGER / Aggilizador  
**Objetivo do documento:** servir como fonte de verdade para implementação por LLM de código, seguindo o fluxo operacional Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback.

---

# 1. Resumo executivo

Este projeto adiciona ao Chat2You um novo módulo chamado **Cotação**, com foco inicial em integração operacional com o **AGGER / Aggilizador**.

O MVP deve expor apenas duas áreas principais para o usuário:

1. **Cotação → Conexões**
2. **Cotação → Agente**

Todo o restante deve existir como infraestrutura interna e não como complexidade de interface.

A meta funcional é permitir que uma corretora:

- conecte sua conta AGGER;
- realize o login humano inicial;
- mantenha uma única sessão persistente do AGGER;
- reutilize essa sessão para múltiplas cotações simultâneas em abas diferentes;
- descubra quais produtos e seguradoras estão disponíveis naquela conta específica;
- tenha um **Agente de Cotação** especializado, opcional, ligado a uma ou mais inboxes;
- permita que esse agente converse com clientes, identifique o ramo, colete os dados necessários, execute a cotação pelo AGGER e retorne resultados estruturados;
- obtenha e envie o PDF/proposta gerado pelo fluxo de cotação;
- registre e movimente a oportunidade automaticamente no CRM já existente;
- responda dúvidas sobre o conteúdo efetivamente retornado pela cotação e sobre conhecimento autorizado da corretora;
- encaminhe para humano quando houver ambiguidade, falha, autenticação, informação não comprovada ou decisão fora de escopo.

O agente **não deve controlar diretamente o browser**. O agente consome uma interface determinística do `Insurance Core`, que por sua vez utiliza o `AGGER Connector`.

A competência técnica sobre produtos, schemas, formulários, fluxos AGGER, parsers e regras de execução deve ser construída e mantida pela Autonom.ia. A corretora personaliza apenas tom, comportamento, identidade, conhecimento próprio, regras comerciais permitidas e vínculo com inbox/CRM.

---

# 2. Problema

Hoje a cotação de seguros pelo AGGER exige operação humana do portal, preenchimento manual de dados, navegação por ramos, consulta aos retornos das seguradoras e envio manual da proposta ao cliente.

Os principais problemas são:

- repetição de dados entre conversa e cotação;
- dependência operacional de usuário treinado;
- demora entre coleta de dados e envio da proposta;
- risco de erro de digitação;
- dificuldade de operar muitas cotações simultaneamente;
- ausência de integração conversacional nativa com o Chat2You;
- ausência de ligação automática com CRM;
- dificuldade de escalar atendimento 24x7;
- dependência de sessão autenticada, MFA, CAPTCHA e portais de seguradoras;
- diferenças entre configurações de cada corretora no AGGER;
- impossibilidade de assumir que toda corretora possui os mesmos ramos e seguradoras habilitados.

---

# 3. Visão do produto

O Chat2You deve tratar **Cotação** como uma capacidade de negócio própria.

O AGGER é apenas o primeiro provider.

A experiência desejada é:

```text
Cliente
  ↓
Inbox Chat2You
  ↓
Agente de Cotação
  ↓
Insurance Core
  ↓
AGGER Connector
  ↓
Sessão AGGER persistente
  ↓
Seguradoras disponíveis para aquela corretora
  ↓
Resultado estruturado
  ↓
PDF / proposta
  ↓
Chat2You
  ↓
Cliente + CRM
```

A arquitetura deve permitir futuramente outros providers sem reescrever o agente:

```text
Insurance Core
├── AGGER
├── Quiver
├── provider futuro
└── APIs diretas de seguradoras
```

---

# 4. Princípios de arquitetura

## 4.1. Sessão única por conexão AGGER

Para cada conta/corretora:

- 1 conexão lógica AGGER;
- 1 browser runtime ativo;
- 1 perfil persistente do Chrome;
- 1 sessão autenticada;
- 1 identidade de rede/egress;
- múltiplas abas dentro do mesmo browser;
- nenhum segundo browser ativo para a mesma conexão.

A regra deve ser garantida por lock externo ao Chrome.

## 4.2. O browser não pertence ao Chat2You web

O `autonom-ia2/chat` utiliza deploy blue/green em AWS. Portanto o browser AGGER não deve rodar no mesmo lifecycle da instância web/Sidekiq.

O browser runtime deve ser um serviço stateful independente.

## 4.3. Agente não navega no browser

O agente chama operações de negócio:

- `quote.start`
- `quote.status`
- `quote.result`
- `quote.proposal`
- `connection.status`
- `capabilities.list`

O agente não recebe primitivas como:

- `click`
- `fill`
- `open_tab`
- `eval_js`

Essas ações pertencem exclusivamente ao connector runtime.

## 4.4. IA não interpreta valores financeiros diretamente da tela

Preço, franquia, coberturas, parcelamento e demais campos relevantes devem ser extraídos e normalizados por adapters/parsers.

O LLM recebe dados estruturados.

## 4.5. Discovery e produção são separados

- Discovery: OpenCLI + Claude/Codex + browser real.
- Produção: adapters determinísticos versionados.
- Recovery: diagnóstico assistido por IA.
- Mudanças em adapters passam por teste, canary e promoção.

## 4.6. Produto visível simples

O usuário não deve ver:

- targetId;
- CDP;
- locks;
- workers;
- tab leases;
- browser profile path;
- adapter versions;
- OpenCLI;
- Claude/Codex.

A interface visível deve falar em:

- conexão;
- reconexão;
- assumir navegador;
- produtos;
- seguradoras;
- agente;
- inboxes;
- CRM;
- cotação;
- proposta.

---

# 5. Escopo do MVP

## 5.1. Dentro do escopo

### Módulo Cotação
- item de menu `Cotação`;
- gate por conta;
- kill-switch global;
- tabs `Conexões` e `Agente`.

### Conexões
- habilitar AGGER;
- iniciar conexão;
- login humano;
- takeover;
- reconexão;
- health-check;
- status;
- capability scan;
- produtos habilitados;
- seguradoras disponíveis por produto;
- teste de readiness;
- atualização manual da configuração.

### Agente
- agente especializado predefinido;
- builder reduzido;
- nome/identidade;
- tom;
- comportamento;
- informações da corretora;
- políticas comerciais permitidas;
- vínculo com inbox(es);
- vínculo com pipeline CRM;
- modo de autonomia;
- teste antes de publicar.

### Insurance Core
- conexão;
- capabilities;
- product registry;
- quote schemas;
- completeness;
- jobs assíncronos;
- quote execution;
- result normalization;
- proposal/PDF;
- callback;
- audit;
- handoff.

### CRM
- criar card;
- atualizar estágio automaticamente;
- associar contato/conversa/cotação;
- manter histórico de eventos.

## 5.2. Fora do escopo inicial

- renovação;
- gestão de carteira de apólices;
- cross-sell;
- sinistros;
- endossos;
- comissões;
- cobrança;
- pagamentos;
- emissão automática de apólice;
- comparação regulatória complexa;
- recomendação financeira/atuarial;
- múltiplos providers simultâneos no mesmo MVP;
- multiagente simultâneo na mesma Inbox;
- alteração estrutural da regra atual de 1 Agente Autonom.ia por Inbox.

Esses itens devem ser possíveis no desenho, mas não implementados agora.

---

# 6. Feature gate

## 6.1. Kill-switch global

Adicionar:

```text
INSURANCE_QUOTING_ENABLED=true|false
```

Comportamento:

```text
ENV OFF
→ módulo indisponível para todas as contas

ENV ON + account OFF
→ módulo invisível para a conta

ENV ON + account ON
→ módulo disponível
```

## 6.2. Gate por conta

Seguir o padrão já existente de `Autonomia::Prospecting::Config`.

Criar:

```ruby
Autonomia::Insurance::Config
```

Com:

```text
INTERNAL_ATTR_KEY = 'autonomia_insurance_enabled'
```

Métodos:

```ruby
enabled?(account)
enable_for!(account)
disable_for!(account)
```

## 6.3. SuperAdmin

Adicionar na página da conta:

```text
Autonomia Insurance / Cotação
Status: Enabled / Disabled

[ Enable ]
[ Disable ]
```

A action deve seguir o padrão de `toggle_prospecting`.

---

# 7. Navegação

Sidebar:

```text
Cotação
```

Rotas sugeridas:

```text
/app/accounts/:accountId/autonomia/insurance/connections
/app/accounts/:accountId/autonomia/insurance/agent
```

Nomes sugeridos:

```text
autonomia_insurance_connections
autonomia_insurance_agent
```

Gate frontend:

- `INSURANCE_QUOTING_ENABLED`;
- `account.autonomia_insurance_enabled`.

O backend deve aplicar o mesmo gate.

---

# 8. Página Cotação

Layout:

```text
Cotação

[ Conexões ] [ Agente ]
```

Sem páginas adicionais no MVP.

---

# 9. Cotação → Conexões

## 9.1. Objetivo

Responder:

> O AGGER está operacional nesta conta e o que esta corretora consegue cotar?

## 9.2. Estados

```text
NOT_CONFIGURED
PROVISIONING
AUTH_REQUIRED
AUTHENTICATING
DISCOVERING
READY
DEGRADED
HUMAN_REQUIRED
OFFLINE
```

## 9.3. Tela

Exemplo:

```text
AGGER                                        ● Conectado

Conta
co******@corretora.com.br

Sessão
Autenticada

Última verificação
há 2 minutos

Última descoberta
há 1 hora

[ Abrir AGGER ]
[ Reconectar ]
[ Assumir navegador ]
[ Atualizar configuração ]
```

Abaixo:

```text
Produtos e seguradoras

Automóvel
10 seguradoras disponíveis

Residencial
3 seguradoras disponíveis

RC Profissional
4 seguradoras disponíveis
```

## 9.4. Primeiro acesso

Fluxo:

```text
Conectar AGGER
  ↓
criar InsuranceConnection
  ↓
provisionar browser profile
  ↓
iniciar runtime singleton
  ↓
abrir AGGER
  ↓
HUMAN_REQUIRED
  ↓
Assumir navegador
  ↓
login / senha / MFA / CAPTCHA / celular
  ↓
Finalizar autenticação
  ↓
health check
  ↓
capability scan
  ↓
readiness test
  ↓
READY
```

---

# 10. Takeover humano

## 10.1. Objetivo

Permitir que o usuário opere o mesmo browser persistente.

## 10.2. Regras

- não criar outro Chrome;
- não criar outro perfil;
- não alterar IP;
- runtime muda para `HUMAN_CONTROL`;
- novos jobs ficam pausados;
- jobs em execução devem terminar ou entrar em estado seguro;
- takeover possui timeout;
- apenas usuários autorizados;
- sessão temporária;
- audit log obrigatório.

## 10.3. Ações

```text
Assumir navegador
Devolver para automação
```

## 10.4. Casos de uso

- login inicial;
- MFA;
- CAPTCHA;
- reautenticação;
- troca de senha;
- login em seguradora;
- erro inesperado;
- operação manual excepcional.

---

# 11. Browser Runtime

## 11.1. Requisito

Serviço separado do Chat2You.

Sugestão de MVP:

```text
EC2 stateful dedicada
+
EBS criptografado
+
Elastic IP
+
Chrome
+
OpenCLI/CDP
+
Session Broker
```

## 11.2. Singleton lock

Para cada `insurance_connection_id`:

```text
runtime_lock
```

Nenhum segundo runtime pode subir simultaneamente.

Implementar fencing token/generation.

## 11.3. Profile persistente

Exemplo:

```text
/chrome-profiles/<connection_id>/
```

Nunca compartilhar profile entre dois processos Chrome ativos.

## 11.4. IP

Preservar identidade de saída estável.

---

# 12. Tab Pool

## 12.1. Objetivo

Permitir múltiplas cotações simultâneas na mesma sessão.

Estados:

```text
FREE
LEASED
RUNNING
WAITING_EXTERNAL
RESETTING
QUARANTINED
```

Cada job recebe:

```text
tab_lease_id
browser_target_id
```

Nunca depender de "aba atual".

## 12.2. Concorrência

Começar conservadoramente.

Configuração:

```text
max_concurrent_quote_jobs
```

Valor inicial recomendado:

```text
2 ou 3
```

Evolução por teste:

```text
3 → 5 → 10 → 15 → 20
```

Abrir 20 abas não é suficiente para validar 20 cotações simultâneas.

---

# 13. Insurance Connection

Modelo conceitual:

```text
Autonomia::Insurance::Connection
```

Campos sugeridos:

```text
id
account_id
provider
status
session_status
runtime_status
username_hint
external_account_label
capabilities_version
last_authenticated_at
last_healthcheck_at
last_capability_scan_at
metadata jsonb
created_at
updated_at
```

Provider inicial:

```text
agger
```

Credenciais completas não devem ficar nesta tabela.

---

# 14. Credenciais

## 14.1. MVP

Preferir login humano sem armazenamento de senha.

## 14.2. Futuro

Se login automático for necessário:

- AWS Secrets Manager;
- secret ref no DB;
- senha nunca em logs;
- senha nunca em prompt;
- senha nunca em frontend após submit;
- somente browser runtime recebe plaintext temporário.

---

# 15. Capability Discovery

## 15.1. Objetivo

Descobrir o que a conta da corretora possui disponível.

Exemplo:

```json
{
  "auto": {
    "enabled": true,
    "insurers": [
      "porto",
      "tokio",
      "hdi"
    ]
  },
  "residencial": {
    "enabled": true,
    "insurers": [
      "porto",
      "tokio"
    ]
  }
}
```

## 15.2. Importante

O scan da conta NÃO descobre a lógica completa do produto.

Existem dois conceitos:

### Global Product Registry
Conhecimento construído pela Autonom.ia.

### Account Capability Map
Disponibilidade específica daquela corretora.

---

# 16. Product Registry

## 16.1. Objetivo

Representar todos os produtos AGGER que a Autonom.ia já mapeou e testou.

Exemplo:

```text
auto                PRODUCTION
residencial         PRODUCTION
rc_profissional     TESTING
empresarial         DISCOVERY
vida                DISCOVERY
```

## 16.2. Estado

```text
DISCOVERED
MAPPED
TESTED
CANARY
PRODUCTION
DEPRECATED
```

## 16.3. Pacote por produto

```text
product/
├── manifest
├── input_schema
├── conversation_schema
├── validation_rules
├── agger_workflow
├── result_schema
├── result_parser
├── proposal_workflow
└── regression_tests
```

---

# 17. Discovery Lab

## 17.1. Ferramentas

- OpenCLI;
- Claude Code;
- Codex;
- browser real autenticado;
- Chrome DevTools Protocol;
- inspeção de DOM;
- inspeção de network;
- screenshots;
- logs.

## 17.2. Objetivo

Mapear:

- produtos;
- formulários;
- condicionais;
- selects;
- validações;
- campos obrigatórios;
- etapas;
- iframes;
- modais;
- endpoints;
- respostas;
- geração de proposta;
- download de PDF;
- estados de seguradora.

## 17.3. Resultado

Conhecimento deve ir para código/config versionado.

Nunca depender da memória da LLM.

---

# 18. Agente de Cotação

## 18.1. Conceito

O agente não é criado do zero.

Ele nasce como um **Agente de Cotação Autonom.ia preconfigurado**.

A competência central é bloqueada e mantida por nós.

## 18.2. Responsabilidades fixas

- identificar intenção de cotação;
- identificar produto;
- consultar disponibilidade daquela conta;
- coletar os campos requeridos;
- validar completude;
- iniciar cotação;
- acompanhar;
- receber resultado;
- explicar somente informações comprovadas;
- enviar proposta;
- atualizar CRM;
- realizar handoff quando necessário.

---

# 19. Builder específico

Reaproveitar o padrão visual/conversacional da criação de Agentes Autonom.ia.

Mas o builder deve perguntar apenas o que a corretora pode personalizar.

## 19.1. Perguntas permitidas

### Identidade
- nome da corretora;
- nome do agente;
- apresentação;
- assinatura.

### Tom
- formal;
- consultivo;
- direto;
- informal;
- detalhado;
- objetivo.

### Comportamento
- nível de explicação;
- uso de linguagem técnica;
- quando chamar humano;
- como apresentar propostas.

### Conhecimento da corretora
- história;
- diferenciais;
- horários;
- contatos;
- site;
- endereço;
- políticas internas;
- FAQ;
- documentos próprios.

### Regras comerciais
- preferências permitidas;
- critérios internos;
- orientações de atendimento.

### CRM
- pipeline;
- estágio inicial;
- mapeamento padrão.

### Inbox
- uma ou mais caixas de entrada disponíveis.

---

# 20. O que o cliente não pode editar

- workflow AGGER;
- quote schemas;
- parsers;
- selectors;
- network adapters;
- regras anti-alucinação;
- interpretação técnica dos estados;
- geração de PDF;
- proteções de segurança;
- limites de concorrência globais;
- regras de handoff críticas;
- provider credentials internas;
- recovery logic.

---

# 21. Camadas de conhecimento do agente

## 21.1. Insurance System Knowledge

Mantido pela Autonom.ia:

- produtos;
- conceitos;
- schemas;
- regras;
- fluxos;
- significados dos retornos;
- campos;
- limitações.

## 21.2. Broker Knowledge

Mantido pela corretora:

- tom;
- informações institucionais;
- FAQ;
- política comercial;
- orientações.

## 21.3. Live Quote Context

Vem da cotação atual:

- seguradoras acionadas;
- seguradoras não configuradas;
- prêmio;
- franquia;
- coberturas;
- parcelamento;
- falhas;
- observações;
- proposta/PDF.

---

# 22. Inbox

O fork atual possui `Autonomia::Agents::AgentInbox` com `inbox_id` único.

Portanto:

- um Agente de Cotação pode ter várias inboxes;
- uma Inbox não deve ter dois Agentes Autonom.ia diretos no MVP;
- se uma Inbox já estiver ocupada, informar;
- permitir troca explícita;
- não alterar essa restrição no primeiro release.

Exemplo:

```text
WhatsApp Comercial        ✓ disponível
WhatsApp Cotação          ✓ disponível
Instagram                 ⚠ já possui agente
```

---

# 23. Modo de autonomia

Configuração:

```text
COLLECT_ONLY
QUOTE_WITH_APPROVAL
QUOTE_AND_SEND
```

## 23.1. COLLECT_ONLY

- conversa;
- coleta;
- valida;
- cria oportunidade;
- humano inicia cotação.

## 23.2. QUOTE_WITH_APPROVAL

- conversa;
- coleta;
- inicia cotação;
- recebe resultado;
- humano aprova antes do envio.

## 23.3. QUOTE_AND_SEND

- conversa;
- coleta;
- cotação automática;
- PDF;
- envio automático;
- CRM.

---

# 24. Quote Schema

Cada produto deve possuir schema estruturado.

Exemplo:

```json
{
  "product": "auto",
  "version": 1,
  "fields": [
    {
      "key": "vehicle_plate",
      "type": "string",
      "required": true
    }
  ]
}
```

Campos condicionais:

```text
if has_young_driver == true
→ require young_driver fields
```

---

# 25. Conversation Completeness Engine

O agente não deve perguntar tudo em sequência fixa.

Ele deve:

1. extrair dados já presentes;
2. consultar contato/CRM quando permitido;
3. preencher schema;
4. calcular campos faltantes;
5. perguntar somente o necessário;
6. revalidar;
7. só iniciar cotação quando `complete=true`.

---

# 26. Quote Job

Modelo conceitual:

```text
Autonomia::Insurance::Quote
```

Campos sugeridos:

```text
id
account_id
connection_id
contact_id
conversation_id
crm_card_id
product
status
requested_by_type
requested_by_id
input_data jsonb
capabilities_snapshot jsonb
provider_reference
result_data jsonb
proposal_attachment_id
error_code
error_details jsonb
started_at
completed_at
created_at
updated_at
```

---

# 27. Estados da cotação

```text
DRAFT
COLLECTING
READY
QUEUED
RUNNING
WAITING_INSURERS
PARTIAL
COMPLETED
HUMAN_REQUIRED
FAILED
CANCELLED
```

---

# 28. Estados por seguradora

Obrigatório diferenciar:

```text
NOT_CONFIGURED
AUTH_REQUIRED
QUEUED
RUNNING
QUOTED
DECLINED
ERROR
TIMEOUT
```

Nunca tratar `NOT_CONFIGURED` como recusa.

---

# 29. Execução assíncrona

As ferramentas HTTP dos Agentes Autonom.ia possuem timeout curto.

Portanto:

```text
quote.start
```

deve responder rapidamente:

```json
{
  "quote_id": "...",
  "status": "queued"
}
```

Depois:

```text
quote.status
quote.result
```

Ou callback/evento.

---

# 30. Callback

Preferir evento:

```text
quote.completed
quote.partial
quote.failed
quote.human_required
```

O Chat2You recebe e:

- atualiza quote;
- atualiza CRM;
- anexa PDF;
- retoma conversa do agente quando aplicável.

---

# 31. Normalização do resultado

Schema sugerido:

```json
{
  "quote_id": "...",
  "product": "auto",
  "offers": [
    {
      "insurer": "porto",
      "status": "quoted",
      "premium": {
        "amount": 2345.67,
        "currency": "BRL"
      },
      "deductible": {
        "amount": 3200.00,
        "currency": "BRL"
      },
      "installments": [],
      "coverages": [],
      "assistances": [],
      "observations": []
    }
  ]
}
```

---

# 32. Regras anti-alucinação

O agente não pode:

- inventar seguradora;
- inventar preço;
- inventar cobertura;
- inventar franquia;
- inventar parcelamento;
- dizer que seguradora recusou se estiver `NOT_CONFIGURED`;
- dizer que algo está coberto sem evidência;
- chamar uma proposta de "melhor" sem critério explícito.

Pode dizer:

- menor preço;
- menor franquia;
- maior cobertura apenas se comparável e comprovável;
- opção com maior/menor valor objetivo.

---

# 33. PDF / proposta

## 33.1. MVP

Prioridade:

1. obter PDF/proposta oficial do AGGER;
2. armazenar no Chat2You;
3. associar à cotação;
4. enviar pela conversa.

## 33.2. Futuro

Gerar proposta Chat2You própria a partir do resultado normalizado.

## 33.3. Requisitos

- nome seguro;
- ActiveStorage/S3;
- audit;
- associação a contact/conversation/quote;
- não depender de link temporário do browser.

---

# 34. CRM

## 34.1. Pipeline

No wizard do agente:

```text
Pipeline de cotação
```

Permitir:

- selecionar existente;
- criar template padrão.

Template sugerido:

```text
Nova oportunidade
Coletando dados
Cotando
Proposta pronta
Proposta enviada
Negociação
Ganho
Perdido
```

## 34.2. Transições

```text
intent_detected
→ Nova oportunidade

collecting
→ Coletando dados

quote.started
→ Cotando

quote.completed
→ Proposta pronta

proposal.sent
→ Proposta enviada

customer.negotiating
→ Negociação

won
→ Ganho

lost
→ Perdido
```

---

# 35. Associação com conversa

Toda cotação originada de conversa deve armazenar:

```text
account_id
contact_id
conversation_id
crm_card_id
agent_id
```

O card deve aparecer no CRM existente.

Não criar CRM paralelo.

---

# 36. Teste do agente

Antes de publicar:

```text
Testar agente
```

A tela deve mostrar:

- intenção detectada;
- produto;
- campos coletados;
- campos faltantes;
- capability da conta;
- ação que seria executada;
- resposta planejada.

Em modo seguro, não executar AGGER real sem ação explícita.

---

# 37. Teste da conexão

Botão:

```text
Fazer cotação de teste
```

O teste de readiness deve validar:

```text
✓ browser
✓ sessão
✓ extensão
✓ produto
✓ seguradoras
✓ execução
✓ parser
✓ proposta
✓ PDF
```

Status:

```text
READY
DEGRADED
```

---

# 38. Recovery

Quando adapter falhar:

```text
UNEXPECTED_STATE
```

Capturar:

- URL;
- etapa;
- DOM relevante;
- screenshot;
- network metadata;
- adapter version;
- job;
- account;
- product.

Recovery Agent pode diagnosticar.

Não promover correção automaticamente para produção em fluxos críticos.

Pipeline:

```text
DISCOVERY
DRAFT
TESTED
CANARY
PRODUCTION
```

---

# 39. Handoff

Disparar para humano quando:

- auth/MFA/CAPTCHA;
- campo conflitante;
- dúvida sem evidência;
- erro inesperado;
- seguradora pede informação não mapeada;
- cliente pede negociação especial;
- ação fora do escopo;
- low-confidence;
- proposta incompleta.

Handoff deve incluir resumo estruturado.

---

# 40. Segurança

Regras obrigatórias:

- senha nunca em prompt;
- cookie nunca em prompt;
- Authorization nunca em prompt;
- secrets não em logs;
- headers sensíveis redigidos;
- screenshots de login não persistidos indefinidamente;
- takeover autenticado;
- tenancy em todas as queries;
- account_id explícito em jobs;
- provider runtime autenticado por service credential;
- browser runtime não exposto publicamente;
- PDF com acesso autorizado;
- auditoria de ações críticas.

---

# 41. Auditoria

Registrar:

```text
account
user/agent
conversation
quote
operation
provider
adapter_version
timestamp
result
human_takeover
errors
proposal_sent
```

---

# 42. Observabilidade

Métricas mínimas:

```text
connection_status
session_age
last_healthcheck
active_tabs
queued_jobs
running_jobs
quote_duration
quote_success_rate
provider_error_rate
auth_required_count
human_takeover_count
pdf_success_rate
adapter_failure_rate
```

---

# 43. API interna do Insurance Connector

Contrato inicial sugerido.

## Connection

```http
POST /v1/connections
GET  /v1/connections/:id
POST /v1/connections/:id/start
POST /v1/connections/:id/reconnect
POST /v1/connections/:id/takeover
POST /v1/connections/:id/release-takeover
POST /v1/connections/:id/scan-capabilities
GET  /v1/connections/:id/capabilities
POST /v1/connections/:id/readiness-test
```

## Quotes

```http
POST /v1/quotes
GET  /v1/quotes/:id
GET  /v1/quotes/:id/result
GET  /v1/quotes/:id/proposal
POST /v1/quotes/:id/cancel
```

## Products

```http
GET /v1/products
GET /v1/products/:slug/schema
```

---

# 44. API Chat2You

Criar namespace:

```text
/api/v1/accounts/:account_id/autonomia/insurance
```

Sugestão:

```text
GET  /connection
POST /connection
POST /connection/reconnect
POST /connection/takeover
POST /connection/release_takeover
POST /connection/scan
GET  /capabilities

GET  /agent
POST /agent
PATCH /agent

POST /quotes
GET  /quotes/:id
```

---

# 45. Estrutura de código no `autonom-ia2/chat`

Sugestão:

```text
app/
├── controllers/
│   └── api/v1/accounts/autonomia/insurance/
│       ├── base_controller.rb
│       ├── connection_controller.rb
│       ├── capabilities_controller.rb
│       ├── agent_controller.rb
│       └── quotes_controller.rb
│
├── models/
│   └── autonomia/insurance/
│       ├── connection.rb
│       ├── agent_config.rb
│       └── quote.rb
│
├── services/
│   └── autonomia/insurance/
│       ├── config.rb
│       ├── connector_client.rb
│       ├── capability_service.rb
│       ├── agent_builder.rb
│       ├── quote_service.rb
│       └── crm_sync.rb
│
├── jobs/
│   └── autonomia/insurance/
│       ├── quote_event_job.rb
│       └── connection_health_job.rb
│
└── javascript/
    └── dashboard/
        └── routes/dashboard/autonomia/insurance/
            ├── insurance.routes.js
            ├── pages/
            │   ├── InsuranceConnectionsPage.vue
            │   └── InsuranceAgentPage.vue
            ├── components/
            └── composables/
```

---

# 46. Novo repositório do connector

Criar separado.

Sugestão:

```text
autonom-ia2/insurance-connector
```

Estrutura:

```text
apps/
├── api/
├── worker/
└── browser-runtime/

packages/
├── connector-core/
├── session-broker/
├── tab-pool/
├── jobs/
├── discovery/
└── observability/

connectors/
└── agger/
    ├── auth/
    ├── capabilities/
    ├── products/
    ├── quote/
    ├── proposal/
    ├── parsers/
    └── tests/

skills/
└── agger-discovery/
```

---

# 47. Persistência do connector

Tabelas sugeridas:

```text
connections
browser_runtimes
browser_sessions
browser_tab_leases
jobs
job_events
capability_snapshots
adapter_versions
discovery_runs
human_takeovers
```

---

# 48. Comunicação Chat2You ↔ Connector

Usar HTTPS com autenticação de serviço.

Nunca expor browser runtime diretamente.

Chat2You não deve conhecer:

- CDP endpoint;
- browser credentials;
- session cookies;
- internal OpenCLI endpoints.

---

# 49. Webhooks do Connector

Eventos:

```text
connection.ready
connection.auth_required
connection.degraded
capabilities.updated

quote.running
quote.partial
quote.completed
quote.failed
quote.human_required

proposal.ready
```

Cada evento deve ser idempotente.

---

# 50. Idempotência

Obrigatória em:

- criação de quote;
- callback;
- proposal;
- CRM sync;
- retry;
- capability scan.

Usar idempotency key.

---

# 51. Retries

Definir:

```text
browser_action_retry
quote_job_retry
provider_retry
callback_retry
```

Evitar retry cego em ações que possam duplicar operação.

---

# 52. Testes

## 52.1. Backend Chat2You

- gate global;
- gate account;
- tenancy;
- permissions;
- connector client;
- quote lifecycle;
- CRM sync;
- callback idempotente.

## 52.2. Frontend

- menu visibility;
- route guard;
- connection states;
- takeover;
- builder;
- inbox selection;
- CRM pipeline;
- agent mode.

## 52.3. Connector

- runtime singleton;
- profile lock;
- tab leasing;
- reconnect;
- auth required;
- capability scan;
- quote workflow;
- parser;
- PDF;
- partial result;
- retry;
- quarantine.

## 52.4. E2E

Cenários:

1. conectar AGGER;
2. login humano;
3. capability scan;
4. cotação Auto;
5. resultado;
6. PDF;
7. CRM;
8. duas cotações concorrentes;
9. auth expira;
10. takeover;
11. retomada;
12. seguradora não configurada;
13. seguradora auth required;
14. erro de adapter.

---

# 53. Critérios de aceite MVP

O MVP só pode ser considerado pronto quando:

1. SuperAdmin habilita `Cotação` por conta.
2. Menu aparece apenas para contas habilitadas.
3. Admin conecta AGGER.
4. Login humano funciona.
5. Sessão persiste após fechar takeover.
6. Browser runtime é único.
7. Reiniciar Chat2You não perde sessão AGGER.
8. Deploy blue/green do Chat2You não duplica browser runtime.
9. Capability scan identifica ao menos um produto real.
10. Sistema identifica seguradoras disponíveis daquela conta.
11. Produto mapeado possui schema.
12. Agente coleta dados conversacionalmente.
13. Agent completeness impede cotação incompleta.
14. Quote é assíncrona.
15. Cotação real é executada.
16. Resultado volta estruturado.
17. `NOT_CONFIGURED` não vira `DECLINED`.
18. PDF/proposta é obtido.
19. PDF é enviado na conversa.
20. CRM card é criado.
21. CRM muda de estágio conforme lifecycle.
22. Agente responde perguntas somente com evidência.
23. Auth/CAPTCHA gera takeover.
24. Takeover usa o mesmo Chrome.
25. Processo retoma após devolver controle.
26. Audit log existe.
27. Não há senha/cookie/token em logs ou prompts.
28. Existe rollback do adapter.
29. Existe kill-switch global.
30. Existe teste de readiness.

---

# 54. Fases sugeridas

## Fase 0 — Discovery técnico
- validar AGGER real;
- mapear login;
- mapear sessão;
- mapear extensão;
- mapear Auto;
- mapear seguradoras;
- validar PDF;
- validar 2 cotações simultâneas.

## Fase 1 — Connector foundation
- repo connector;
- connection;
- browser singleton;
- profile;
- tab pool;
- takeover;
- health.

## Fase 2 — AGGER Auto
- capability scan;
- Auto schema;
- workflow;
- parser;
- PDF;
- regression tests.

## Fase 3 — Chat2You UI
- gate;
- SuperAdmin;
- menu;
- Conexões;
- takeover;
- readiness.

## Fase 4 — Agente
- template;
- builder;
- Broker Knowledge;
- Inbox;
- CRM;
- modes.

## Fase 5 — Quote runtime
- tool contract;
- async job;
- callbacks;
- CRM;
- PDF.

## Fase 6 — Hardening
- concurrency;
- auth recovery;
- partial results;
- observability;
- audit;
- rollback;
- security.

## Fase 7 — Expansão por produtos
- Residencial;
- RC;
- Empresarial;
- demais ramos.

---

# 55. Restrições para a LLM de código

A LLM deve seguir estas regras:

1. Não inventar arquitetura existente.
2. Inspecionar repo antes de alterar.
3. Reutilizar padrões atuais do fork.
4. Não alterar upstream desnecessariamente.
5. Manter código Autonom.ia em namespace próprio quando possível.
6. Não quebrar CRM existente.
7. Não quebrar AgentInbox.
8. Não remover proteções de tenancy.
9. Não criar segundo CRM.
10. Não armazenar senha/cookie em plaintext.
11. Não executar ações destrutivas sem teste.
12. Criar migrations aditivas.
13. Atualizar documentação.
14. Atualizar `.env.example`.
15. Incluir testes.
16. Preservar rollback.
17. Não implementar produto AGGER sem discovery comprovado.
18. Não hardcodar seguradoras por corretora.
19. Não hardcodar perguntas em prompt gigante.
20. Schemas precisam ser versionados.
21. Resultados precisam ser estruturados.
22. O agente nunca recebe browser tools.

---

# 56. Documentação obrigatória

Criar/atualizar:

```text
docs/insurance/
├── PRD.md
├── architecture.md
├── agger-discovery.md
├── browser-runtime.md
├── security.md
├── quote-lifecycle.md
├── product-registry.md
├── runbook.md
└── troubleshooting.md
```

Também:

```text
.env.example
README
deploy/runbook
```

quando houver mudança operacional.

---

# 57. Variáveis de ambiente sugeridas

Chat2You:

```text
INSURANCE_QUOTING_ENABLED=false
INSURANCE_CONNECTOR_BASE_URL=
INSURANCE_CONNECTOR_SERVICE_TOKEN=
INSURANCE_CONNECTOR_WEBHOOK_SECRET=
```

Connector:

```text
DATABASE_URL=
REDIS_URL=
AWS_REGION=
AWS_SECRETS_PREFIX=
BROWSER_PROFILE_ROOT=
MAX_CONCURRENT_QUOTES_DEFAULT=3
OPENCLI_ENABLED=true
DISCOVERY_ENABLED=false
```

Não definir valores reais no repositório.

---

# 58. Segurança operacional

Toda alteração de conexão deve ser account-scoped.

Apenas administradores podem:

- conectar;
- reconectar;
- takeover;
- alterar agente;
- selecionar inboxes;
- alterar CRM.

Agentes comuns podem usar a funcionalidade apenas através da conversa/agent runtime conforme permissões.

---

# 59. Regras de rollout

1. Feature OFF por padrão.
2. Ativar somente conta interna/teste.
3. Conectar conta AGGER de teste.
4. Habilitar somente Auto.
5. Canary.
6. Medir.
7. Expandir para corretora piloto.
8. Só depois abrir novos produtos.
9. Kill-switch disponível em produção.
10. Rollback documentado.

---

# 60. Deployment / rollback

O módulo Chat2You deve seguir o pipeline blue/green existente.

O Browser Runtime não deve depender do lifecycle da EC2 web.

Rollback Chat2You:

- voltar target group anterior;
- nenhum impacto na sessão AGGER.

Rollback Connector:

- versão anterior da imagem;
- manter EBS/profile;
- não criar browser simultâneo.

Rollback Adapter:

- selecionar versão anterior;
- sem alterar browser profile.

---

# 61. Project Management

Projeto GitHub obrigatório:

**Autonom.ia Dev**  
`https://github.com/users/autonom-ia/projects/3`

Campos obrigatórios:

- Projeto
- Status
- Tipo
- Prioridade
- Risco
- Próxima ação
- Ambiente

Modelo operacional:

```text
Issue
→ Branch
→ PR
→ Project update
→ Review
→ Approval
→ Merge
→ Deploy / rollback plan
```

---

# 62. Issues sugeridas

## Epic
`[Insurance] Cotação AGGER no Chat2You`

Subissues:

1. `[Insurance] Feature gate e SuperAdmin`
2. `[Insurance] Rotas e UI Cotação`
3. `[Insurance] Connection model e API`
4. `[Insurance Connector] Foundation`
5. `[Insurance Connector] Browser Runtime Singleton`
6. `[Insurance Connector] Human Takeover`
7. `[Insurance Connector] Tab Pool`
8. `[AGGER] Discovery Auto`
9. `[AGGER] Capability Scan`
10. `[AGGER] Auto Quote Adapter`
11. `[AGGER] Result Parser`
12. `[AGGER] Proposal/PDF`
13. `[Insurance] Product Registry`
14. `[Insurance] Quote Schema / Completeness`
15. `[Insurance Agent] Template e Builder`
16. `[Insurance Agent] Inbox Binding`
17. `[Insurance CRM] Pipeline e lifecycle`
18. `[Insurance] Async callbacks`
19. `[Insurance] Security/Audit`
20. `[Insurance] Observability`
21. `[Insurance] Readiness/E2E`
22. `[Insurance] Runbook e documentação`

---

# 63. Decisões travadas

Estas decisões não devem ser alteradas durante o MVP sem aprovação do PO:

1. Menu principal = `Cotação`.
2. Páginas visíveis = `Conexões` e `Agente`.
3. Provider inicial = AGGER.
4. Agente é especializado e predefinido.
5. Cliente não edita lógica técnica AGGER.
6. Agente não recebe browser tools.
7. Browser é stateful e separado do Chat2You.
8. Uma conexão AGGER = um browser runtime ativo.
9. Múltiplas cotações usam múltiplas abas do mesmo browser.
10. Product Registry é global.
11. Capability Map é específico por corretora.
12. Quote execution é assíncrona.
13. CRM existente é reutilizado.
14. PDF/proposta faz parte do MVP.
15. Renovação/cross-sell ficam fora do MVP.

---

# 64. Questões que precisam ser respondidas via Discovery antes da implementação de cada produto

Para cada ramo:

1. A rota/tela é estável?
2. Quais campos existem?
3. Quais campos são obrigatórios?
4. Quais condicionais existem?
5. Quais seguradoras aparecem?
6. Como o AGGER sabe que a seguradora está conectada?
7. Como identificar seguradora `NOT_CONFIGURED`?
8. Como identificar `AUTH_REQUIRED`?
9. Como identificar `DECLINED`?
10. Como identificar sucesso?
11. Existe endpoint interno útil?
12. Existe response JSON?
13. Existe iframe?
14. Existe estado global que impede concorrência?
15. É seguro usar múltiplas abas?
16. Como gerar proposta?
17. Como baixar PDF?
18. O PDF é único ou temporário?
19. Há dados não presentes no PDF?
20. Existe ação que não deve ser automatizada?

---

# 65. Resultado esperado do MVP

A experiência final deve ser:

```text
Cliente:
"Quero fazer seguro do meu carro"

Agente:
identifica Auto
coleta campos faltantes
valida schema

Insurance Core:
verifica Auto disponível para a conta
verifica seguradoras habilitadas
cria QuoteJob

AGGER:
executa multicálculo

Insurance Core:
normaliza resultado
gera/obtém proposta
anexa PDF

Chat2You:
atualiza CRM
retoma agente

Agente:
explica opções comprovadas
envia PDF
faz handoff se necessário
```

Sem operação manual do corretor no fluxo normal.

---

# 66. Definição de sucesso

O projeto é bem-sucedido quando uma corretora consegue:

1. habilitar Cotação;
2. conectar sua conta AGGER uma vez;
3. manter a sessão;
4. ligar o Agente de Cotação às inboxes;
5. configurar apenas identidade/tom/conhecimento;
6. receber um cliente em WhatsApp;
7. coletar dados conversacionalmente;
8. cotar automaticamente em seguradoras disponíveis;
9. receber resultados corretamente;
10. enviar proposta PDF;
11. responder dúvidas com segurança;
12. acompanhar a oportunidade no CRM;
13. lidar com MFA/CAPTCHA via takeover;
14. executar múltiplas cotações usando a mesma sessão AGGER.

---

# 67. Instrução de início para a LLM de código

Antes de escrever código:

1. Clonar/abrir `autonom-ia2/chat`.
2. Confirmar branch `main`.
3. Inspecionar:
   - `Autonomia::Prospecting::Config`
   - SuperAdmin toggle de Prospecção
   - `Autonomia::Agents`
   - `AgentInbox`
   - CRM
   - rotas Autonom.ia
   - Sidebar
   - deploy blue/green
   - tool executor
4. Criar uma Issue para a primeira fase.
5. Atualizar o Project `Autonom.ia Dev`.
6. Criar branch dedicada.
7. Implementar somente a primeira fase.
8. Testar.
9. Documentar.
10. Abrir PR.
11. Não avançar para fases seguintes sem fechar os critérios da fase atual.

**Primeira entrega recomendada:**  
Feature gate + modelo de Connection + UI `Cotação → Conexões` em estado mockado/contract-first, sem ainda automatizar o AGGER. Em paralelo, iniciar o repositório `insurance-connector` com o Browser Runtime Singleton e Discovery técnico do produto Auto.
