# WAHA 2026.9.2 — fechamento técnico do candidato atualizado

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/846.
Branch: `codex/waha-final-candidate-2026-10-02`.
Base: `ffa7ce96920687f3d4d7d43124b78063006b407e`.
Origem: `feat/waha-2026-9-2-chatwoot-sync`, `62af5b0493dda09aba9c764e9e62f58197895f34`.

## Resultado e escopo

Os três achados reproduzidos na preparação anterior estão corrigidos em commits isolados na origem,
revisados e enviados: snapshot de planejamento #850 (`5f565dc3be`), saúde final #851 (`5737a3c611`)
e duplicidade de resolver #852 (`62af5b0493`). R1–R5/N1–N3 permanecem preservados.
Mais de um resolver, inclusive desabilitado, gera SKIP humanizado antes de escrita, sem escolha automática,
remoção, merge ou retry; APPLY interrompe o lote. Oito exemplos novos primeiro reproduziram o problema
(8 falhas), depois passaram. Origem: focados 63/0, regressão do handoff 318/0/3 pendentes preexistentes.

O novo candidato aplica os 30 caminhos da origem sobre a main atual, sem conflito e com conferência
SHA-256 arquivo a arquivo; somente dois espaços finais do handoff histórico foram retirados.
Árvore staged inicial certificada: `64a84f244b2057b8c0eb01bd44ee165214f179d6`.
As três auditorias de preparação complementam a árvore; não alteram produto/testes.
O candidato #848 é histórico e não certifica a versão atual.
Não há delta de UI, schema, migrations, workflow, dependência ou lockfile. Guia R5 foi preservado e regenerado.

## Bateria final, executada e lida

Ruby 3.4.4 via rbenv; Node 24.11.0; pnpm 10.2.0. Banco local exclusivo
`chat2you_waha_final_20261002`, `RAILS_ENV=test`, PostgreSQL localhost e Redis local exclusivo porta 6862.
Nenhum teste apontou para banco de produção. Avaliações pagas permaneceram desligadas.

```bash
bundle exec rspec spec/services/autonomia spec/requests/api/v1/accounts/autonomia \
  spec/models/autonomia spec/jobs/autonomia spec/services/crm spec/controllers/super_admin \
  spec/configs spec/lib spec/services/waha \
  spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb \
  spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb \
  spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb

pnpm test app/javascript/dashboard/routes/dashboard/autonomia \
  app/javascript/dashboard/components/autonomia app/javascript/dashboard/components-next/sidebar \
  app/javascript/dashboard/i18n app/javascript/dashboard/api

pnpm guia:build
pnpm guia:check
pnpm central:check
```

- RSpec: **5582 exemplos, 0 falhas, 12 pendentes**, saída 0; zero erros fora dos exemplos.
  Saída integral lida em cinco blocos e JSON conferido. Duração 4m56,5s mais 10,1s de carregamento.
- Pendentes intactos: três avaliações pagas; nove quarentenas preexistentes em RegistrationCheckout (2),
  Sso (1), CRM FollowUps (3), WebhookListener (1) e Conversation (2). Nenhum exemplo desabilitado,
  assertion/tolerância relaxada ou comportamento de produção alterado para tornar a bateria verde.
- Vitest: **133 arquivos passaram, 1354 testes passaram**, saída 0; saída integral lida.
  Primeira tentativa falhou antes de coletar testes por `fake-indexeddb` ausente no node_modules emprestado.
  O symlink criado nesta preparação foi removido; instalação própria com frozen-lockfile e repetição passaram.
  Nenhuma dependência versionada foi alterada. Avisos existentes de sourcemap/Browserslist/Vue não falharam testes.
- RuboCop: **19 arquivos Ruby/Rake, nenhuma infração**, saída 0. Não há JS/Vue tocado para o lint restrito do CI.
- Guia build/check: saída 0, 174 fluxos, 171 telas, zero telas sem explicação; quatro explicações sem rota
  já informadas pelo build. Regeneração não produziu delta adicional.
- Central check: saída 0, 175 artigos e 171 telas cobertas. Avisos de evidências/linhas permanecem explícitos;
  não se reescreveram artigos fora do escopo. As travas remotas foram confirmadas no SHA publicado conforme o registro abaixo.
- Primeiro comando do Guia pegou pnpm 11 do runtime genérico e não executou o build por incompatibilidade;
  repetição com PATH do projeto (Node 24/pnpm 10.2) passou. Não se atualizou tooling global nem manifest.

Logs, JSON, manifesto e patches revisados ficam em `.codex/waha-final-validation/`, ignorado pelo Git.
Antes de commit: diff/check, leitura das auditorias e conferência de manifesto. Depois dos hooks normais:
comparar patch commitado byte a byte com o revisado, confirmar ausência de reescrita e push do SHA.
Nenhum bypass de hook foi autorizado.

## Revisão independente da árvore atual

Dois revisores por domínio, somente leitura, sem testes concorrentes no banco ou acesso operacional:

- Migrador/cliente/configuração/provisionamento/cleanup/rake: aprovado sem novo bloqueador no delta.
  Conferiu comparação integral das versões de Chatwoot durante planejamento, preflight N1, saúde final
  WORKING antes de persistência, recuperação R1/fail-stop e duplicidade de resolvers. R2/R3/N3 preservados;
  Apps não relacionados continuam no payload completo. Sintaxe dos 11 arquivos Ruby/Rake de produto e
  diff staged aprovados. O risco legado de colisão no provisionamento não é chamado pelo backfill nem
  foi agravado materialmente pelo delta; piloto restrito ao updater, sem criação como fallback.
- Métricas/conversa/eventos/jobs/Enterprise: aprovado sem novo bloqueador. Primeiro início de reabertura
  persiste junto ao status; resolução captura o timestamp antes do enqueue. Ordem dos jobs, bot, horário
  comercial e rollups usam esse início. Assinatura do job permanece compatível com workers antigos/novos;
  workers antigos/eventos sem marcador conservam comportamento legado. Freeze_time permanece somente
  nos seis cenários de tempo de resposta, sem mudar assertions/tolerâncias.

Condições conhecidas: GET/preflight/PUT não são atômicos; impedir escritores paralelos também durante
recuperação. Provider/trava devem ficar estáveis até escoar a fila. Todos os workers novos e ciclo novo
depois do deploy. Evento de abertura não foi corrigido; não há recálculo histórico. Nenhuma dessas
condições foi ocultada ou apresentada como aceite E2E real.

## Situação operacional e próximos gates

Conferências atuais AWS/WAHA foram somente leitura, detalhadas no
[plano de publicação e piloto](2026-10-02-waha-release-and-pilot-plan.md).
Ambas as aplicações seguem em `ab84a219bdd30f287ed0011ed61d62ec43f1fab4`, com web/worker ativos,
targets healthy e HTTP 200. SHA conferido dentro dos dois containers de cada instalação.
WAHA 2026.9.2 e módulo brazilian-phone-numbers carregado confirmados por GET nas duas instalações.
Estados agregados: Hub2You 32 WORKING/2 FAILED; Autonom.ia 2 WORKING/9 FAILED. Nenhum reparo foi tentado.
Esses estados antecedem a publicação do candidato. Caixa piloto precisa estar WORKING.

Rollback de aplicação é um degrau, com imagem ativa atual como retorno do próximo deploy; ele não desfaz
dados/configuração do backfill. Restaurar backfill exige snapshot privado e comparação com o estado atual,
sem PUT cego nem sobrescrita de intervenções posteriores. Procedimentos e parada estão no plano.

**Fechamento técnico aprovado; operação ainda não autorizada.** Candidato b13dcfaed875 foi enviado, hooks
normais aprovados, patch commitado idêntico ao revisado (SHA-256
`fa58a2e4187346088da212b5f45a3eae01436d91cac4ab70cc7057e413fbb0ba`); worktree limpo.
PR #853 mergeable/draft; Guia/traduções/escopo concluídos sem falha. Jobs de email dispensados por escopo;
bateria Ruby/frontend completa executada localmente, sem atribuir sua execução ao CI remoto.
Rodrigo definiu o piloto Hub2You; IDs guardados privadamente e vínculo remoto/WORKING confirmados por GET.
Ainda faltam janela sem escritores, snapshot privado imediatamente antes de APPLY e responsável pelo piloto.
Depois: aprovação explícita de merge/deploy, lote exclusivo e conferência de runtime; dry-run total=1;
aprovação separada de APPLY e oito aceites reais antes de expansão. Nenhum dry-run produtivo foi realizado.
Não afirmar que snapshot privado, janela ou piloto estão prontos enquanto não forem definidos.

Não houve merge, deploy, backfill real, escrita em banco produtivo, mudança de sessão WAHA, logout,
pareamento, QR, credencial/auth ou configuração operacional nesta preparação. Diagnósticos SSM executaram
somente leitura de serviço/imagem/SHA/HTTP. A branch original foi preservada; checkout principal não editado.
