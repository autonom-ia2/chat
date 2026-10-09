# Auditoria — prontidão do F0 após a decisão D7

**Data:** 2026-10-07
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`
**Branch:** `docs/agentes-ia-prd`
**Alvo atual:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`, SHA-256
`f7ea20c1f3d5937123ebc1022b96cc2c6563116ee0baafde944ff266d66ad52a`
**Decisões:** `docs/audit/2026-10-07-agentes-f0-desenho-decisoes.md`, SHA-256
`5b336f4aa5fb1e55d2052d9c373c2a0cd204d22e4d73c01f275edb48a56142b2`

## Resultado

**F0 continua DRAFT e bloqueado para implementação/aceite.** O mapa atual
registra a decisão nova de D7 e não contém mais uma rota interna de conexão de
WhatsApp, mas ainda não houve uma revisão final específica deste alvo após essa
mudança, nem implementação F0, captura de tela real ou aprovação visual do
Rodrigo.

Este registro é uma auditoria de prontidão e consistência documental. Não é um
PASS de desenho, não substitui a revisão independente, não marca o mockup como
tela real e não autoriza código, merge, fila, deploy, produção ou banco.

## 1. Histórico que permanece histórico

Os dois pareceres finais anteriores revisaram outro contrato e outro snapshot:

- `revisoes/F0-desenho-final-produto-testes.md` revisou o SHA
  `38649eb14b909eae5628b82ac2275f88858cc2d291b4c8eaa3df1eddca9f8755` e
  registrou PASS apenas para os três residuais de produto daquele bloco,
  deixando claro que não aprovava implementação, aceite visual, merge ou
  produção.
- `revisoes/F0-desenho-final-tecnica.md` revisou o mesmo SHA e registrou
  **STOP/F0-FINAL-01**, porque o contrato anterior representava apenas a
  origem `autonomia_agent_panel/channels` para a conexão e não preservava a
  origem `autonomia_agent_build/live`.

Esses resultados não podem ser relidos como PASS do F0 atual. A decisão
explícita do Rodrigo em 07/10 retirou a conexão de WhatsApp da área Agentes;
ela tornou o achado histórico F0-FINAL-01 inaplicável ao novo escopo, mas não
converteu retroativamente o parecer técnico em aprovação. O próprio mapa atual
faz essa distinção em `design/F0-mapeamento.md:137`.

O handoff ainda preserva a parada antiga em
`HANDOFF-CODEX.md:74-75` como histórico. Enquanto a revisão do alvo atual não
for registrada, esse texto não deve ser usado como evidência de que o F0 foi
aprovado nem como obrigação de reintroduzir a rota removida.

## 2. Escopo normativo atual de D7

O contrato atual está consistente entre as fontes lidas:

- `PRD.md:94,329,526,587,668-670` e `CA-CANAIS-01/02` mantêm cadastro e
  conexão em `settings_inbox_list`/`settings_inbox_new`, na área central de
  Canais/Caixas de entrada.
- `design/F0-mapeamento.md:128-137` declara que não existe rota de conexão em
  Agentes; a tela apenas lê/associa canais conectados e, quando não há canal,
  preserva o agente e orienta para `settings_inbox_new` conforme a permissão.
- `design/F0-mapeamento.md:146,217` leva essa regra para a associação de canais
  e para o caso sem canal. Não há obrigação de `from`, QR, número, token,
  `InviteConnectionPage` ou criação de `waha_inboxes` dentro de Agentes.

Esta consistência de texto ainda precisa ser exercitada na implementação e no
aceite tela a tela. Ela não autoriza criar o fluxo antigo sob outro nome.

## 3. Gates de prontidão verificados

| Gate | Evidência atual | Estado |
|---|---|---|
| D7 central, sem rota `from` em Agentes | PRD/F0 e a matriz F09 apontam para `settings_inbox_new` e preservam o agente | **Coerente em documento; sem aceite visual** |
| Mapa F0 revisado no novo escopo | alvo atual SHA `f7ea20...`; o próprio documento ainda diz DRAFT em `:1,250` | **Pendente de revisão final específica** |
| Código de telas F0 | `app/javascript/dashboard/routes/dashboard/autonomia/agentes/` ainda não existe | **Não iniciado** |
| Leitor B3/BE-05 | F0 exige `GET agents/:agent_id/build_thread` em `:24,144,149`; o código atual mantém apenas `resources :build_threads` em `config/routes.rb:395` e o cliente legado `autonomia/build_threads` | **Bloqueado; não fabricar fallback** |
| Acessibilidade Playwright | F0 exige `@axe-core/playwright` em `:181-188`; `tests/playwright/package.json` tem Playwright, mas não declara esse pacote | **Infraestrutura ainda não executável** |
| Cenários e fixtures locais | F0 enumera 13 famílias e perfis em `:179-223`; nenhum cenário foi executado neste bloco | **Pendente** |
| Todas as telas reais | não há implementação F0/F1 nem capturas reais aprovadas | **Pendente** |
| Aprovação e release | não houve OK visual do Rodrigo, CI de PR de implementação, merge, fila, deploy ou produção | **Bloqueado** |

O F1 também recebeu uma revisão normal independente nesta retomada
(`revisoes/F1-desenho-normal-produto-testes.md`), que deixou achados de
produto/testes. Isso reforça que a sequência não pode pular da documentação
para o primeiro deploy; F1 ainda depende de F0 e dos contratos B2/B3.

## 4. Critério objetivo para sair do bloqueio

O F0 só pode deixar o estado DRAFT depois de, no mínimo:

1. revisão específica do alvo atual, já sob D7 central, sem transportar o
   residual histórico de `from` para dentro de Agentes;
2. contratos B2/B3 necessários fechados e provados no ambiente local de teste,
   incluindo a leitura escopada BE-05, sem `start` ou thread inventada;
3. implementação real dos destinos F0, com i18n, tokens, foco, rotas, guards e
   Guia/Central verificáveis;
4. execução do aceite local em todos os estados e cenários do
   `aceite-telas-reais.md`, em 1440/400 px, claro/escuro e perfis de editar/só
   ver/admin, com capturas lidas e comparação com `Todas as telas`/`Ver esta
   tela como`;
5. aprovação visual e funcional explícita do Rodrigo. Só depois os gates de
   PR, fila Automação, merge e deploy podem ser tratados pelas regras do
   handoff.

## Limite da auditoria

Foram feitas somente leituras estáticas, busca de rotas/arquivos e conferência
de hashes. Não executei teste, build, navegador, banco, serviço, produção,
commit, push ou PR. O mockup publicado/inspecionado anteriormente continua
referência visual; não é evidência de que uma tela real foi implementada.
