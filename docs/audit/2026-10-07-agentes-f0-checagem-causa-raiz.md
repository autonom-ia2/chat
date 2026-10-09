# F0 — parada na checagem e causas antes da correção final

Alvo checado: `design/F0-mapeamento.md`, 245 linhas, SHA-256 `3dd44e652b1f14deefb8a071b1cf5db9c8cd2e7a8e3685c418c7e3be3d1978e4`. A correção normal foi feita pelo autor; a checagem independente de produto/testes encontrou três residuais. A checagem técnica ainda está concluindo o mesmo bloco, sem abrir revisão normal nova.

**Estado: PARADO para diagnóstico.** Nenhum código F0, tela ou aceite visual está aprovado. Este registro precede a correção final; a existência do texto não fecha os achados.

## 1. Matriz resumida não é cobertura de cenários

O autor transformou a lista normativa em 14 linhas abreviadas e inferiu que uma linha por família demonstrava cobertura. Não comparou cada estado do PRD/aceite com um caso executável. O vínculo família → arquivo/spec também foi perdido ao substituir a seção de Playwright.

Consequências provadas pela checagem: F06 omite “Não salvou” e “Ainda respondendo”; F09 não explicita falha ao ligar e editor sem ser administrador; F13 não explicita código vencido. Nomes genéricos de captura como `fail` não provam a diferença de código vencido, sessão desligada e falha de conexão.

Correção final deve enumerar os estados normativos e associar cada grupo a arquivo/caso de spec, fixture, ação, leitor e quatro capturas. A lista deve ser confrontada mecanicamente com as 14 famílias do aceite e PRD §11.6; nenhuma linha é aprovada somente por existir. Não inventar novos cenários ou payloads de sucesso.

## 2. Permissão correta no texto, ator errado no percurso

O papel SuperAdmin foi documentado no inventário geral, mas não transportado para a linha F11 que inclui a captura `tools`. Essa linha só nomeia editor, viewer e administrador de conta, que não substituem o administrador da plataforma.

Correção final deve ligar a variante Ferramentas à fixture SuperAdmin real, manter a ausência para os demais perfis e para Lia e provar a recusa por rota/API. O cenário não pode se autenticar com um único administrador para todas as capturas.

## 3. Estado atual confundido com possibilidade de voltar

A tabela colocou Conte apenas em E1/E2, usando o estado mínimo da primeira visita como restrição permanente. Não avaliou o percurso de retorno a partir de Teste/Ligue, no qual a pessoa altera informação e invalida o teste antes de ligar.

Correção final deve permitir retorno de alteração em E3/E4 conforme PRD, preservar a thread e fazer a invalidação pelo backend. A barra continua com quatro itens; Pronto continua sendo conclusão. Não liberar atalhos de escrita para viewer nem fazer E5/E6 voltar a “Falta terminar”.

## 4. Query e leitor foram descritos como intenção, sem contrato único

A checagem técnica encerrou com cinco residuais, registrados em `revisoes/F0-desenho-checagem-tecnica.md`. O mapa misturou `?from=` com o path de declaração e deixou o formato de origem canônica em aberto. Fixar path sem query e `to.query.from` separado, com uma única representação produzida pelo router e allowlist dos destinos internos. A resolução precisa ser demonstrada com e sem query, sem prioridade artificial de array.

O texto também permitiu “threadId ou resolver existente”, embora BE-05 seja justamente o leitor ausente. Isso transferiu a decisão para a implementação e citou B2 como fornecedor de um endpoint que pertence a B3/BE-05. A fundação deve exigir explicitamente `GET agents/:agent_id/build_thread`, com autorização de edição, agente/conta da rota e última thread guiada, e hidratar o store antes do legado. Thread de outro agente da mesma conta não substitui essa retomada. Ausência não chama `start`.

## 5. Inventário visual dependia da caixa do hexadecimal

A busca exata encontrou os 18 usos do dashboard, mas a página pública `app/views/public/tracked_link_kits/show.html.erb` tem `#0d2344` em CSS próprio. A afirmação de inventário de produto inteiro era maior que a evidência. Essa página pública de Links/QR está fora da fundação Tailwind do dashboard e não será migrada pelo F0; a exclusão precisa ser nomeada e justificada, com busca sem diferenciar maiúsculas/minúsculas. Nenhuma troca cega ou mudança na página pública será feita para fazer o grep passar.

## 6. “Migrar ou justificar” deixou a decisão de locale aberta

A duplicata `CampaignOverviewPage.vue` foi detectada, mas o autor deixou uma exceção sem provar incompatibilidade. A decisão final é migrar o consumidor ao helper comum e remover a função local. Se a implementação descobrir incompatibilidade real, ela para com evidência, sem escolher outra cópia silenciosa.

## 7. Lifecycle não definiu dono de cada responsabilidade

O desenho marcou os momentos de ativação/desativação, mas não retirou a sobreposição entre SidePanel e o composable. Definir uma única posse de Escape, gatilho, restauração, foco inicial, scroll e trap em cada consumidor. O SidePanel preserva sua API e controla abertura/fechamento, Escape, scroll e retorno; nele o composable opera somente o trap, por ativação explícita. AudienceSidePanel mantém o contrato atual através do adaptador/default documentado, sem dois listeners de Escape ou duas restaurações. A integração deve contar fechamento e testar reabertura/diálogo aninhado.

## Protocolo restante

Consolidar qualquer residual técnico deste mesmo alvo neste diagnóstico antes da edição. Executar um único bloco final de correção e uma única revisão final independente. Erro na revisão final exige parar e retornar ao Rodrigo, sem novo loop ou implementação F0. B1 segue separado, com sua revisão normal de código já concluída e novos testes de regressão em preparação.

Nenhum merge, fila, deploy, produção ou banco de produção foi executado.

## Resultado da única revisão final — STOP

Alvo final: `design/F0-mapeamento.md`, SHA-256 `38649eb14b909eae5628b82ac2275f88858cc2d291b4c8eaa3df1eddca9f8755`. Produto/testes fechou sem residual no relatório `revisoes/F0-desenho-final-produto-testes.md`. Técnica deixou **F0-FINAL-01 P1**, registrado em `revisoes/F0-desenho-final-tecnica.md`. Resultado conjunto: **não aprovado; execução parada e retorno ao Rodrigo**, sem nova correção/revisão por iniciativa da sessão.

Causa residual: ao fechar a representação canônica/allowlist de `from`, o desenho escolheu somente `autonomia_agent_panel/channels` sem confrontar as duas origens reais. PRD §6.4 exige volta à origem e BE-13 explicita Ligue e Onde atende; `mockup/src/screens-build.js:198` e `screens-panel.js:163` possuem o CTA. Um início em `autonomia_agent_build/live` voltaria ao painel, trocando o contexto da jornada. A escolha de formato único foi confundida com escolha de uma única origem. O diagnóstico recomenda preservar ambas as rotas nomeadas e provar os dois retornos, mas essa correção não foi aplicada nem autorizada como novo ciclo.

Durante a revisão final, B1 executou somente o RED já preparado em snapshot isolado: 127 exemplos Ruby, 16 falhas esperadas e zero erros fora dos exemplos; 14 testes JS, uma falha esperada. Não iniciou suas correções de produto. Todos esses jobs terminaram; nenhuma prévia atual está ativa. B1/B2/F0 permanecem locais, sem implementação de tela real, sem push ao PR documental #1115 e sem produção. Handoff atualizado para preservar esta parada.

## Checagem específica do novo contrato pós-D7 — antes da correção

A mudança explícita do Rodrigo mantém WhatsApp em Canais; não converte o STOP histórico em PASS. A checagem F0-contrato-pos-D7.md no alvo 9c878aff38937afb191f6255ac8a14e3d509096685ccdc7d256ccacaa152613d encontrou três bloqueios:

- F0-D7-01: o mapa omitiu disposição dos chamadores globais de InviteConnectionPage. Correção: preservar formalmente a superfície global preexistente fora do redesign de Agentes, incluindo perfil, SSO e recurso Rails, sem novo link/import/chamador no kit/rota de Agentes. Isso evita regressão de onboarding/SSO e mantém a conexão do redesign somente no fluxo central settings_inbox_new. Não há mudança de auth/permissão/SSO nesta fatia.
- F0-ROUTE-02: foi escrita a exceção E2m, mas continuaram frases genéricas obrigando BE05 em qualquer legado. Correção: definir a hidratação só para retomada guiada com permissão, e E2m só leitura escopada do agente manual + painel legado de escrita manual, sem build_thread/start/job. Ajustar tabela, guard, specs, plano e matriz juntos.
- F0-D9-01: a tabela confundiu o baseline da API antiga com o alvo do composable apenas Tab. Correção: documentar troca explícita da API interna e migração atômica de AudienceSidePanel ao SidePanel comum; API pública da gaveta preservada, único dono do ciclo no SidePanel, sem ponte duplicada.

Causas registradas antes das alterações. Uma correção única e revisão final limitada aos três contratos. Se a final encontrar erro residual, parar e retornar Rodrigo; nenhum código F0 enquanto aberto. Backend B2 e testes RED BE05 independentes continuam locais, sem release.

Correção documental única pós-D7 concluída. Alvo F0 SHA-256 10b95f401f5d28c59d8c33c95690abe356a0344e34348a4d93afbf1ccd28ce98. Disposição global de InviteConnectionPage explícita para perfil/SSO/Rails/Guia, fora do redesign; nenhum novo consumidor/QR/from em Agentes. Hidratação guiada separada de E2m/viewer na tabela, guard, plano e matriz. API interna do composable muda explicitamente para trap; migração AudienceSidePanel atômica e repasse público close somente afterLeave evita desmontagem antes da restauração. Staging preserva componentes legados enquanto telas futuras não existem, sem dummy. Busca de consistência lida e git diff --check exit zero; nenhuma alteração de código produto/F0, navegador/auth/produção. Revisão final única dos três bloqueios pendente.
