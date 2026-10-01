# Editor de e-mail: espaço, rolagem e destinatários — #807

## Escopo e autorização

Rodrigo aprovou a implementação em 01/10/2026 após revisar o mockup: detalhes do e-mail recolhidos, etapas na mesma linha, Destinatários com alerta âmbar sem botão adicional de correção, rolagem que recolhe/restaura as etapas e visão completa com ajuste/ampliação. Esta entrega deve ser conferida em capturas da aplicação antes de merge e deploy.

Issue: https://github.com/autonom-ia2/chat/issues/807. Branch: `codex/807-editor-scroll`, base `476db3af5e`. Worktree isolada; checkout principal preservado. Issue em andamento nos Projects jarvis e Autonom.ia Dev.

## Mudança

- Assunto e texto de prévia ficam em Detalhes do e-mail, acessíveis sem ocupar espaço inicial do canvas.
- A etapa Destinatários usa a prontidão calculada pelo servidor: alerta para lista vazia/inadequada ou importação falha, atividade durante processamento e check quando a lista está pronta. Estado desconhecido permanece neutro.
- O clique na etapa reutiliza a recuperação existente para importação falha ou abre os destinatários. O popup automático de erro continua montado.
- O scroll do iframe recolhe as etapas ao descer e as restaura ao subir, compensando a posição do conteúdo. Salvar, revisar e o estado da lista permanecem no cabeçalho.
- Visão completa utiliza a API nativa de geometria e zoom do GrapesJS. Ajusta o corpo inteiro à área disponível; Ampliar permite leitura com scroll. Retorno restaura a geometria e a posição anterior.
- Em campanha legada com HTML e canvas MJML ainda vazio, a ação abre a prévia existente do HTML original. Não converte nem sobrescreve o conteúdo. Após adicionar blocos, o modo do canvas passa a ser utilizado.
- Abertura direta carrega a lista quando o store está vazio, depois o detalhe com prontidão. Falha de leitura mostra o alerta existente e continua o carregamento de placeholders.
- Em telas abaixo de 1280 px, as abas existentes alternam Blocos, Conteúdo e Propriedades; o painel ativo ocupa o espaço restante com scroll. No celular, título e ações usam linhas próprias para preservar a leitura.

Somente frontend. Não há mudança de endpoints, banco, admissão de envio, SES, TypeSafe, IA ou faturamento. Não há override correspondente em enterprise para os componentes alterados. Classes do design system e utilitários Tailwind; sem CSS novo. Português e inglês atualizados conforme autorização explícita do Rodrigo para ambos; demais idiomas usam a infraestrutura existente de fallback.

## Validação e revisão

Comandos executados separadamente de qualquer commit, com saída lida:

- Prettier `--check` nos cinco componentes/composable: conforme.
- `.github/scripts/email-protection-eslint.mjs` nos cinco arquivos: zero achados bloqueantes; 39 avisos de chaves dinâmicas de tradução.
- Vitest existente em `components-next/Campaigns/EmailProtection/specs` e `emailTemplateBody.spec.js`, UTC, dois workers: **16 arquivos, 486 testes passando**, zero falhas. Essa rodada antecede os ajustes finais de responsividade e o desvio de prévia HTML-only; a rodada independente de 26 testes e a aceitação visual foram posteriores.
- `scripts/check-email-protection-i18n.mjs` e `scripts/check-fork-i18n.mjs`: inventário, compilação e paridade de parâmetros validados.
- Build final `vite build --mode test`: concluído em 2m29s; aviso existente de bundles maiores que 500 kB.
- Hook local não encontrou `npx` no runtime disponível. A mesma tarefa foi executada separadamente com `node node_modules/lint-staged/bin/lint-staged.js`: aprovada. Diff completo relido, sem mudança adicional de produto; seis arquivos e **26/26 testes** repetidos em 2,60 s. O commit utiliza `HUSKY=0` apenas para não repetir o hook indisponível; nenhum arquivo de hook foi alterado.
- Agente QA `qa_800`: cinco arquivos, 22 testes existentes passando, zero falhas; asserções de API repetidas sobre a fonte final. Campanha sintética pronta: `can_send=true`, dois aptos, um protegido por falha permanente. Importação recuperável, HTML-only, permissões, isolamento e 14 modelos globais validados. Texto de prévia salvo e relido: `QA 807 · prévia preservada`.
- Revalidação ampliada após os últimos ajustes: **seis arquivos, 26/26 testes passando**, incluindo o contrato de preservação de HTML. Campanha legada 3 relida, sem escrita: `body_mjml=nil`, HTML/imagem preservados e enviável.

Revisão independente pelo agente `review_776`: corrigidos o cálculo de zoom antes do resize, callback após desativação, leitura prematura de Canvas.getWindow no evento de carga, tratamento da falha de getOne, carregamento inicial com store vazio e altura do painel ativo em telas menores. Parecer final sem outro problema demonstrável; revisão estática. A função existente de prévia foi posicionada antes da ação que a chama para respeitar o lint, sem alteração do corpo da função.

QA no navegador identificou problemas que a suíte existente não cobre: ligação inicial de scroll e corte do rodapé em visão completa. Ambos foram corrigidos e repetidos na aplicação real. Na conferência final em 1280 × 720, o canvas ganhou 61 px de altura ao recolher as etapas (481 → 542 px). Em 1024 × 768, as abas alternaram os painéis e a rolagem alcançou Rodapé legal e Margem. Em 390 × 844, título/ações permaneceram legíveis e a visão completa enquadrou o corpo e o rodapé. A campanha HTML-only abriu a prévia original; nesse caso legado utiliza-se o popup existente, não o novo zoom do canvas. Novos textos de navegação e detalhes foram conferidos em português e inglês. Os nomes antigos dos blocos ainda são definidos em português pelo plugin; não foram alterados nesta correção. A leitura de erros de console na última navegação retornou lista vazia. Não foram criadas specs que apenas espelham a implementação; a aceitação do novo comportamento é feita no navegador.

## Ambiente e limites

Aplicação Rails completa com bundle frontend de teste em `127.0.0.1:34807`; Postgres `email807_workspace` e Redis DB 10 locais isolados. Conta e campanhas sintéticas. Sem dados de cliente, chamadas a provedor, envios, agendamentos ou mudanças de produção. Somente o Puma desta worktree foi reiniciado para atualizar o manifest do build.

Para comparar português e inglês no ambiente sintético, foi utilizado o parâmetro oficial `locale` do bootstrap. A preferência sintética do perfil, sozinha, não mudou o idioma no bootstrap observado; não foi expandido o escopo para alterar esse comportamento.

As capturas em `docs/campaigns/editor-807/` são do app completo no navegador, não de HTML de mockup nem imagens geradas. A marca e o menu são os componentes reais. Conta de QA e conteúdo sintético distinguem o ambiente de produção.

## Release e rollback

Merge/deploy não executados nesta etapa. Após aprovação das capturas e CI, incluir a PR no trem de release conforme `docs/processo-de-release.md`; merge na main aciona as stacks hub2you e autonomia. Validar abertura, edição/salvamento, recuperação de importação, rolagem e retorno da visão completa nas duas stacks. Não fazer envio real como smoke test.

Sem migration. Se houver regressão, usar `action=rollback` nos dois workflows blue-green para retornar à instância anterior, dentro da janela disponível. Se outra release já tiver substituído essa instância, preparar lote de reversão. Nunca alterar o banco para reverter esta mudança de apresentação.
