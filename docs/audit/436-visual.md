# Epic 436 — QA visual isolado

Registro inicial: 2026-09-16, **NEEDS_FIXES — BLOCKED_ENVIRONMENT**.

**Atualização após execução real pelo parent: 87 PASS / 5 FAIL / 34 PNGs. Correções de UI e harness implementadas; nova execução do navegador pendente.** O bloqueio descrito abaixo é histórico da primeira tentativa, não o estado da evidência posterior. Veja a atualização no fim deste arquivo.

A execução real foi bloqueada antes de carregar a página. O sistema recusou `listen` em `127.0.0.1:3437` com `EPERM`. Não houve inicialização do Chromium, renderização dos componentes, requisições de navegador ou screenshots. Não há evidência para aprovar ou reprovar a UI. Nenhuma falha visual de componente foi confirmada.

## Execução e evidência

Comando executado na raiz:

```sh
node tests/qa/email-campaigns/run.mjs > tmp/email436/visual/run.log 2>&1
```

Início registrado: `2026-09-16T12:33:06.671Z`. Saída: `1`.

```text
Error: listen EPERM: operation not permitted 127.0.0.1:3437
code: EPERM
syscall: listen
address: 127.0.0.1
port: 3437
```

Resumo legível por máquina da execução real:

```json
{
  "decision": "NEEDS_FIXES",
  "execution_status": "BLOCKED_ENVIRONMENT",
  "browser_checks_executed": 0,
  "browser_checks_passed": 0,
  "browser_checks_failed": 0,
  "screenshots": [],
  "browser_requests": 0,
  "confirmed_ui_findings": [],
  "blocker": "listen EPERM 127.0.0.1:3437",
  "artifacts": {
    "results": "tmp/email436/visual/results.json",
    "log": "tmp/email436/visual/run.log",
    "fixture_checks": "tmp/email436/visual/harness-static-checks.json"
  }
}
```

Diretório absoluto das evidências desta execução:
`/Users/rodrigosilva/dev/worktrees/chat2you/436-email-protection/tmp/email436/visual/`.

O log também informou Browserslist desatualizado. Nenhuma dependência foi atualizada. O erro de bind é o bloqueio efetivo; não foi confundido com erro de frontend.

## Preparação entregue

Arquivos novos exclusivamente em `tests/qa/email-campaigns/`: `App.vue`, `entry.js`, `server.mjs`, `fixtures.mjs`, `run.mjs`, `README.md`.

O harness monta `CrmCampaignManagementPage.vue` real e seus filhos, incluindo proteção, higiene, destinatários, badges, botões e gráfico. Usa aliases correspondentes ao `vite.shared.ts`, Router em memória, Vuex mínimo, Pinia, Axios e índices completos de locale. Não substitui componentes renderizados. `fallbackLocale: false` registra chaves ausentes. O CSS disponível identificado foi `public/vite-test/assets/dashboard-BQ8OZSyf.css`; sua aplicação no navegador **não foi verificada**.

Os cenários preparados abrangem PT-BR desktop 1280×900, dark, árabe RTL 1440×900, mobile 390×844, alemão, inglês, avaliação desconhecida, restrição do provedor e avaliação sem dados atuais. Interações previstas: filtros combinados, paginação, exportação, detalhes/cópia, refresh e HTTP 500, reavaliação HTTP 503, problemas de importação e visibilidade de retomada. Ainda não foram executadas.

Fixtures: três campanhas; 120 destinatários sintéticos `example.org`; classes distintas de falha permanente/temporária/desconhecida e caixa inexistente; texto longo; métricas atuais distintas do registro da pausa; contadores prévios reconciliados. Nenhum dado de cliente.

Contratos preparados para os adaptadores reais, sem requisição observada no navegador:

- `GET /api/v1/accounts/436/email_campaigns/reports`: `payload.summary`, `campaigns`, `campaign_options`, `protection`, `preflight`, `meta`. Opções independentes da campanha selecionada.
- `GET .../reports/:id/recipients`: q/status/problem/page combinados; `payload.recipients` e `payload.meta = {count,current_page,total_pages,per_page}`. Cinco linhas por página para exercitar paginação.
- `GET .../reports/:id/export`: mesmo q/status/problem, CSV de todas as linhas correspondentes.
- `GET .../reports/:id/import_issues`: quatro motivos `invalid_email`, `domain_nxdomain`, `domain_typo`, `invalid_recipient`; `payload.issues` e `meta`.
- `POST .../campaigns/:id/reevaluate`: HTTP 503 sintético com diagnóstico fictício não destinado à exibição; erros GET 500 acionados durante os cenários.

## Verificação possível neste ambiente

- `node --check` em `server.mjs`, `run.mjs`, `fixtures.mjs`: exit 0.
- `node --input-type=module --check < tests/qa/email-campaigns/entry.js`: exit 0.
- Cinco verificações locais de fixtures: exit 0. Confirmaram 120 destinatários/três campanhas; dez correspondências para filtros combinados; cinco linhas na segunda página; reconciliação de 120 linhas na análise; CSV com todas as dez correspondências.

Essas verificações não são testes de navegador nem validação de UI. Após o bloqueio, o registro do ciclo de vida do servidor e do resultado fatal foi melhorado; nenhuma nova tentativa de bind nem execução visual foi feita. O harness precisa da primeira execução completa no ambiente autorizado do parent.

## Segurança e próximo passo

Nenhum arquivo de produção, configuração compartilhada, dependência ou tradução foi editado. Não houve operações Git, Rails, banco, infraestrutura, SMTP, API paga, instalação, leitura de secrets/.env, perfil privado ou tráfego externo. Não foi alterada a sandbox nem tentada outra porta. O servidor não chegou a escutar; o processo do comando terminou.

O parent deve executar `node tests/qa/email-campaigns/run.mjs` em ambiente que já permita a porta local autorizada, inspecionar os screenshots produzidos e tratar eventuais falhas reais antes de aprovação. Questões de contraste, espaço excessivo, clipping, RTL e traduções permanecem sem conclusão visual. Integração DB/API, review, merge, deploy e rollback continuam com o parent. Esta entrega não afirma revisão humana nativa, backend E2E ou prontidão de produção.


## Correção após revisão visual real — 2026-09-16

Fonte: `tmp/email436/visual-independent-review.md` e `tmp/email436/visual/results.json`, execução iniciada em `2026-09-16T12:36:18.918Z`: **87 PASS, 5 FAIL, 34 screenshots escritos**, zero erros JS informados. As cinco falhas eram duas de dicionário (árabe/alemão), uma de botões árabes sem tradução, uma de direção de células e uma de teclado (11/16). A revisão detectou ainda defeitos visuais que as asserções antigas não capturavam.

Antes de editar, abri com `view_image`: `pt-mobile-recipients.png`, `pt-desktop-protection.png`, `pt-desktop-manual-protection.png`, `ar-rtl-recipients.png` e `pt-mobile-whole.png`. A evidência mostrava e-mail em fragmentos, coluna 41,5 px/linha 765 px na geometria registrada, dois badges de proteção idênticos, título de proteção contradizendo pausa manual, e capturas recortadas pelo scroll interno. Não foi inferida inversão visual de e-mail árabe a partir da asserção antiga incorreta.

Mudanças de produto, apenas dentro de `EmailProtection/`:

- Tabela com mínimo de 60rem, coluna de e-mail com mínimo de 15rem, nome/status/detalhes com mínimo de 12rem; rolagem horizontal no contêiner existente. E-mail e nome resumidos em uma linha com truncamento; conteúdo integral em detalhes, com quebra de palavras e cópia do endereço integral. Nome internacional sintético exercita o acesso ao conteúdo completo.
- E-mails isolados em `<bdi dir="ltr">`, na tabela e nos detalhes. Células de status, cabeçalhos e rótulos mantêm direção herdada.
- Badge semântico idêntico aparece uma única vez. Estados distintos têm rótulos existentes `HEALTH` e `CAMPAIGN_STATUS`.
- Título manual usa `STATUS.manual`; pausa por proteção usa `TITLE`; visão normal/desconhecida usa `HEALTH`. Bloqueio explícito da conta/provedor prevalece sobre pausa manual, inclusive quando o payload contraditório contém `resume: true`; não há inferência de capacidade a partir de aparência saudável.

Mudanças do harness, preservando a página real e os adaptadores:

- Capturas sequenciais do contêiner real `#app > .overflow-y-auto`, sem aumentar viewport e sem `locator.screenshot` de painéis fora da área visível. Recortes correspondem à interseção efetivamente visível; nomes e manifestos registram posição vertical/horizontal, foco, viewport e tamanho do arquivo.
- Aguarda fontes, ausência de fetch/XHR ativo e geometria/texto estáveis. Alvos sem altura e requisições durante captura fazem a execução falhar. Manifesto conta somente arquivos efetivamente escritos.
- Mobile verifica ≥180 px para e-mail, ≤160 px para linhas fechadas, overflow horizontal interno, largura do documento ≤391 px, extremos esquerdo/direito da tabela e foco. O viewport continua 390×844.
- RTL verifica o `bdi` de cada endereço na tabela e em cada detalhe aberto, incluindo `direction:ltr` e `unicode-bidi:isolate`; rótulos/status devem permanecer árabes RTL.
- Teclado mantém 100% dos botões expostos habilitados, mesmo fora da viewport. Exclui conteúdo de detalhes fechados e ocultação efetiva por ancestrais/inert/estilos. Não exclui ações com tabindex negativo nem tamanho zero para fazê-las passar. Cada summary é alcançado e aberto por Tab/Enter, seguido da cópia por teclado e conferência da área de transferência. Há screenshots de foco reais previstos, sem afirmar que já foram gerados.
- Mantidos filtros q/status/problem, página 2, exportação completa, HTTP 500/503, problemas de importação e cenários de capability. Novo cenário manual+provedor mantém o payload inseguro de teste (`resume:true`), exigindo que a UI o bloqueie. Nenhuma regra de negócio da fixture foi enfraquecida; apenas um nome sintético foi ampliado para texto internacional.
- O CSS do dashboard continua real. O harness gera utilidades atuais com PostCSS/Tailwind e a configuração de produção, pois o bundle antigo não continha `min-w-[60rem]`. A geração foi exercitada offline e a regra de 60rem foi encontrada; sua aplicação/renderização aguarda Chromium.
- A comparação dark/light preserva a geometria inicial clara, em vez de usar a inspeção sobrescrita após o erro 500. O escopo é explicitamente a página de gestão real **sem shell/sidebar de navegação**, com fixtures sintéticas; não é backend E2E.
- `fallbackLocale:false` e falhas de chaves ausentes permanecem, inclusive após interações. Traduções pertencem ao worker separado; nenhum JSON/index/checker/spec de locale foi editado nesta entrega.

Validação offline desta correção: 69 testes de componente em seis arquivos passaram (Vitest, máximo dois workers); cinco testes Node de seleção de controles/contratos de fixture passaram; sintaxe do runner/server/fixtures/entry passou. ESLint dos três arquivos de produção: **0 erros / 45 avisos**, sendo 35 de chaves dinâmicas e dez de resolução estática de i18n. Vitest informou Browserslist desatualizado; sem instalação. Comandos e limites completos em `436-ui.md` e no README do harness.

**Estado: PENDING_PARENT_BROWSER_RUN.** Nenhum servidor/navegador foi iniciado nesta correção; nenhum novo PNG de UI foi produzido. Os PNGs antigos foram reabertos ao concluir para comparar os defeitos observados com a intenção do código, não para declarar um novo render aprovado. O parent deve executar `node tests/qa/email-campaigns/run.mjs` na porta autorizada 3437 e inspecionar os PNGs listados pelo novo resultado, após o worker de traduções. Backend E2E permanece posterior. Nenhum arquivo fora da propriedade autorizada precisou ser alterado; sem operações Git, produção, Rails, DB, SMTP, credenciais, APIs pagas ou alteração de sandbox.
