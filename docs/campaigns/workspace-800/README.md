# Campanhas implementadas — evidência visual

Issue #800, PR #801. Capturas feitas no navegador com os componentes reais de produto, após a implementação aprovada. O shell externo e os dados são sintéticos: conta local 800, sem IA, SES ou acesso à conta 16/banco de produção. O ambiente reproduzível está em `tests/qa/email-workspace/`.

| Tela | Captura |
|---|---|
| Lista compacta e próxima ação | [Desktop](previews/01-campanhas.jpg) |
| Editor, assunto, blocos e propriedades | [Desktop](previews/02-editor.jpg) |
| Biblioteca com os 14 modelos reais | [Desktop](previews/03-modelos.jpg) |
| Revisão com público apto e confirmação | [Desktop](previews/04-revisao.jpg) |
| Orientação para rascunho incompleto | [Desktop](previews/05-pendencia.jpg) |
| Lista em celular | [390 px](previews/06-campanhas-mobile.jpg) |
| Biblioteca em celular | [390 px](previews/07-modelos-mobile.jpg) |
| Biblioteca em tablet | [768 px](previews/08-modelos-tablet.jpg) |

As capturas desktop usam 1440 × 900 px. O painel rola verticalmente para mostrar o restante dos cards e controles. Os textos novos são do catálogo inglês; o conteúdo ilustrativo dos modelos é o original licenciado. A tradução pt_BR aguarda autorização específica conforme o audit trail.

## QA independente

O agente `/root/qa_800` revisou os fluxos e a aparência em desktop, 390 e 768 px. Os ajustes apontados foram tratados. Parecer funcional aprovado, condicionado à suíte ampla final e ao registro das capturas: ambas as condições foram concluídas.

- Backend: 159 exemplos, **0 falhas**, incluindo supressão individual com SES saudável, catálogo idempotente e isolamento entre contas.
- Frontend: 438 testes em 16 arquivos, **0 falhas**, incluindo confirmação/cancelamento, agendamento, atualização de prontidão, prévia Desktop/Mobile, importação e proteção.
- Build, lint, catálogo de traduções existente, Guia e diff: concluídos. Avisos existentes de Browserslist/chunks/enums não impediram os checks.
- Conferência final do parent: em 390 px, lista/biblioteca têm largura de documento igual ao viewport e nenhum botão/input ultrapassando seus limites; o mesmo em 768 px para a biblioteca.

Os totais do QA direcionado são subconjuntos/repetições dos checks finais, não testes extras somados. Isso comprova a versão local, sem garantir ausência absoluta de regressão ou entrega real de e-mail. Merge, deploy e seed de produção estão pendentes; o plano está em `docs/campaigns/email-workspace-release-800.md`.

Os workflows de testes de e-mail, Guia e traduções estão desativados manualmente no GitHub. O commit implementado não tem CI remoto; os resultados acima são locais. Resolver essa condição antes de declarar o release aprovado.
