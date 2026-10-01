# Visão completa estável — Issue 814 — 2026-10-01

## Decisão e causa

Rodrigo autorizou publicar as correções de campanhas e idioma nos dois ambientes. O lote #811 foi integrado em main `5bc07b468f481f4eb831e85d905ceca5660bfb7d`; os workflows Hub2You `36869562063` e Autonomia `36869562205` concluíram com sucesso. Serviços web/worker ativos, targets saudáveis, `/health` 200 e `DEFAULT_LOCALE=pt_BR` comprovados nos dois runtimes. Preferências individuais preservadas; nenhuma escrita no banco de produção.

A conferência autenticada do editor publicado revelou um defeito adicional no ajuste de modelos longos à tela. Os wrappers MJML usam `min-height: 100vh`. O auto-height do GrapesJS media `body.scrollHeight`; a altura do iframe alimentava a próxima medição. O conteúdo crescia a cada ciclo, até o zoom mínimo: iframe com apenas 6 px de largura e altura interna superior a 590 mil px. Ampliar para 100% e retornar ao editor recuperavam a leitura.

A correção mede a altura da primeira div renderizada dentro de `mj-body`, fixa a altura numérica do frame e observa somente esse conteúdo. Mantém desktop/celular, zoom limitado a 100%, imagens e restauração da posição do editor. Sem migration ou mudança de API. O pedido posterior de Rodrigo incluiu quatro textos da navegação em português: My Inbox, Calls, Channels e Search. O catálogo `pt` continha essas traduções literalmente em inglês; `pt_BR` já continha os valores corretos. Corrigidas somente as quatro chaves, preservando preferências individuais e os demais idiomas. Alteração de catálogo português expressamente autorizada na conversa.

## Ambiente e validação

Worktree exclusivo `codex/814-preview-stable`, origin/main no SHA acima. Reutilizado serialmente o banco local sintético `email812_workspace`, após parar somente o Puma local anterior. Puma 34815, assets sintéticos 34814. Não houve DDL, acesso ao banco de produção ou chamada a provedor pago.

A massa anterior intitulada longa tinha HTML longo, mas MJML curto. Criado um rascunho sintético com 24 seções MJML reais, imagem e rodapé identificável. O primeiro seed local tentou uma associação inexistente; corrigido para a consulta do modelo `EmailSenderIdentity`. O seed final terminou com exit 0.

O wrapper Ruby de build tentou instalar dependências com pnpm 11, incompatível com o pnpm 10 exigido pelo projeto. Executado o CLI Vite já instalado, com o mesmo modo test e plugins, sem alterar dependências ou lockfiles. Resultado final, testes e conferência visual serão registrados antes do commit.

Build inicial: exit 0, 7m39s. A aplicação real mostrou conteúdo estável de 4791 px, imagem carregada e iframe de 74×570 px ajustado à tela, em vez do crescimento sem limite. Em Ampliar, rolagem até 4220 px com rodapé legível. Esse teste encontrou outra falha: ao voltar, a posição 2099 px virava 18,5 px. A captura posterior ao resize e a restauração anterior à atualização real do viewport participavam da falha. O GrapesJS anima seu wrapper durante 350 ms e a rolagem era limitada pela altura antiga. Captura antes da mudança do layout e espera por animações, isoladamente, não resolveram a conferência real (2819 → 18,5); essas tentativas não foram aprovadas. O patch atual observa o resize do próprio iframe, restaura a posição e desconecta ao atingir a altura original. Geração e teardown cancelam o observador anterior. Conferência visual final ainda pendente. Build intermediário: exit 0, 6m26s, dashboard-TqO9mm5V.js; nova compilação limpa em andamento.

União frontend: 163 arquivos, 1961 testes passaram e 1 timeout no inventário existente de traduções, limite 5s. Repetição isolada durante a compilação: 255 passando e o mesmo timeout; nenhuma asserção falhou. Não alterado o limite do projeto. Repetição sem build concorrente também excedeu 5s. Execução diagnóstica isolada com `--testTimeout=30000`: 256 passaram, zero falhas, exit 0; nenhum timeout de fonte foi alterado. O CI oficial no limite normal permanece gate antes do merge. Após o patch atual, testes existentes de apresentação, revisão e payload: 3 arquivos, 71 passaram, zero falhas, exit 0.

ESLint: zero erros, 59 avisos de inventário i18n existentes na página. Prettier, `git diff --check`, Guia e Central passaram. Revisão independente identificou o resize como causa do scroll limitado. O QA permanece pendente da prova funcional final e dos checks oficiais. Lint atual: zero erros, 59 avisos existentes. Todos os marcadores de diagnóstico foram removidos da fonte antes da nova compilação; não integram o patch. Uma tentativa de invocar o wrapper shell do Prettier através de Node falhou; corrigida para o binário correto, que passou.

## Publicação e rollback

Publicar somente após QA visual e checks do SHA final. Merge/deploy já autorizados por Rodrigo. Ambos os workflows blue-green publicam automaticamente após main. Verificar versão, serviços, saúde e comportamento autenticado real depois da troca. Não salvar campanha, enviar e-mail, importar lista ou usar IA paga no smoke.

Rollback pelos workflows existentes. O lote precedente inclui `stage_criteria`: drenar operações CRM pending/running antes de retornar à imagem antiga. Preservar o padrão português brasileiro.
