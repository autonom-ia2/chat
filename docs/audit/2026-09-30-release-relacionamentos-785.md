# Release de Relacionamentos — #785 — 30/09/2026

## Escopo e autorização

Rodrigo aprovou a versão visual e autorizou continuar com merge/deploy em 30/09. Lote exclusivo release/2026-09-30-lote1, implementação PR #786. A ficha usa lateral 37rem/592px (antes 28rem/448px, +32,14%); Contato abre em Notas, Empresa em Contatos. Dashboard arredondado com agregados da base e apresentação de mídias compartilhada, miniaturas 96px. Sem migração, dependências novas, mudanças de gravação, env, secrets ou infraestrutura além do blue-green existente.

## Revisão e validação

Revisão independente review_776, dois P2 corrigidos (grade com Empresas desativado; Escape preserva lateral/rascunho quando existe overlay interno). Nova revisão dos três arquivos finais sem problema demonstrável; revisão estática separada das verificações da sessão principal.

Árvore de produto da revisão 32d835e3af6ef33f56dfc078de42625cad8a0b35 integra main 1d7f051a2655ef98cdc6ac70fa8b6f1a89c4cfe7, sem conflitos. Validação local: 6.832 testes frontend, 174 relevantes repetidos após a captura de Escape, QA real com dez verificações de overlays e dois estados sem Empresas. RSpec: 5.481 exemplos de integração/contratos, zero falhas, dez pending existentes (sete quarentenas e três evals pagas desligadas). A rodada incluiu 18 testes nativos e teve quatro falhas por libvips ausente no Mac; o resultado Linux substitui essa lacuna, sem alterar/relaxar testes.

ESLint da aplicação: 22 arquivos, zero achados bloqueantes/13 avisos permitidos. RuboCop: 11 arquivos sem infrações. Prettier/gate AST e Guia build/check/Central check passaram, sem arquivo gerado alterado. Capturas aprovadas são reais em ambiente sintético; dados e autenticação privados não entram no Git. Evidência detalhada em 2026-09-30-implementacao-relacionamentos-785.md.

## Publicação e retorno

Antes da entrega, Hub2You e Autonom.ia estavam saudáveis em 1d7f051a2655ef98cdc6ac70fa8b6f1a89c4cfe7: web/worker ativos, Docker em SHA correspondente, HTTP local 200 e target group healthy. Workflows oficiais são disparados pelo único merge commit do lote na main. Nenhum deploy manual duplicado.

Rollback previsto em caso de falha desta publicação: workflow_dispatch com action=rollback e confirm_production=true nos workflows deploy-hub2you-blue-green.yml e deploy-autonomia-blue-green.yml, voltando um degrau para a instância/imagem anterior. Sem alteração de schema/dados a reverter. Confirmar os parâmetros previous-* após o deploy; não remover a instância anterior manualmente.

Pós-deploy: conferir SHA de web/worker e parâmetros SSM, saúde dos target groups, HTTPS e SSO públicos, rotas/serviços/assets publicados; no navegador, conta 16 Hub2You, listas, abas padrão, lateral e mídias, somente leitura. Não enviar mensagens, ligar, bloquear, excluir ou salvar dados de cliente. Não afirmar ausência absoluta de regressões ou cobertura de todos os dispositivos.

## Integração do lote

PR #786 foi squash no lote em 12d568b72efce11eaba7cd3df0d333dcd5397068. git diff --exit-code confirmou árvore idêntica à revisão 32d835e3af6ef33f56dfc078de42625cad8a0b35. Regressão Linux de Relacionamentos passou (288 exemplos, zero falhas, um pending; conversores nativos aprovados), e Email protection concluiu com sucesso (1.032 exemplos, zero falhas, dois pending; frontend 615 arquivos/6.832 testes, lint, catálogos, build e navegador isolado). O teste da imagem de 32d835e ainda estava em execução ao integrar no lote; nenhuma publicação em produção aconteceu nesta etapa. O merge do lote na main continua condicionado ao CI completo e ao runtime Linux de seu SHA final.

CI da revisão: https://github.com/autonom-ia2/chat/actions/runs/36706531843 e https://github.com/autonom-ia2/chat/actions/runs/36706535162. Verificação pública anterior: https://chat.hub2you.ai/ e https://agents.autonomia.site/ retornaram 200; /auth/autonomia retornou 302 em ambos. Endereço atual de Autonom.ia vem do workflow vigente, não do domínio legado dos runbooks.

## Correção final dos overlays no celular

Na conferência real, clicar no campo do diálogo de link do editor fechava a lateral e perdia o rascunho; Escape no seletor de tipo de mídia também fechava a lateral. Os dois layouts agora reconhecem o diálogo do editor e os popovers no clique externo, seguindo os marcadores já usados no ConversationSidebar. Escape preserva o seletor aberto relacionado ao alvo do evento; não consulta seletores desktop ocultos ao mudar de largura. Aparência aprovada e regras de gravação permanecem iguais.

Validação final desta correção: QA real em 1024px e 390px, contato e empresa, 14 verificações aprovadas, zero erros de página. Inclui clique no diálogo de link, preservação do rascunho, Escape no seletor de mídia, ações abertas e novo Escape para fechar a lateral. Os 174 testes frontend existentes relevantes passaram (17 arquivos), Prettier passou e lint dos dois layouts teve zero achados bloqueantes/dois avisos permitidos. Avisos de diretiva de atributo nos testes não representam falhas.

A segunda rodada completa do backend do lote terminou: 5.481 exemplos, zero falhas, dez pending existentes, sem erros fora dos exemplos. Conversores nativos continuam cobertos pelo gate Linux; a correção acima altera somente os dois layouts frontend. Revisão independente review_776 confirmou o guard ligado ao alvo do evento e não encontrou novo problema demonstrável; não executou testes próprios. O CI completo da versão integrada continua necessário antes do merge na main.

## Gates finais e merge autorizado

Complemento #791 squash no lote em c6a35799914231a2f866095c86e6f024bec943d7, árvore idêntica ao delta revisado/testado em 79889a1e6edf69cf3fa644e84218721960a85076. CI final de Relacionamentos [36709472697](https://github.com/autonom-ia2/chat/actions/runs/36709472697) aprovado: 615 arquivos/6.832 testes frontend; 288 exemplos backend, zero falhas, um pending de quarentena existente; 18 testes nativos sem falhas. Artefato relationships-runtime.json confirma c6a3579, Ruby 3.4.4 x86_64-linux-musl e 11 verificações reais aprovadas dentro da imagem, incluindo PNG/PDF/MP4/JPG/WebP, fallback, limites e encerramento por timeout.

CI final de proteção de e-mail [36709472742](https://github.com/autonom-ia2/chat/actions/runs/36709472742) aprovado: 1.032 exemplos, zero falhas, dois pending de quarentena existentes; contratos puros, 6.832 testes frontend, lint/catálogos/compilação/navegador. Fork i18n e Guia/Central aprovados na mesma versão. Uma rodada de Guia/Central foi substituída automaticamente pela concorrência do workflow; a rodada mais recente [36709494391](https://github.com/autonom-ia2/chat/actions/runs/36709494391) concluiu verde. Nenhum teste relaxado ou eval paga executada.

PR [#790](https://github.com/autonom-ia2/chat/pull/790) mergeado na main em 30/09/2026 12:01:05 UTC, commit e45fbe68945f948525dcc0a2997eae5c3c9dc74f. git diff --exit-code entre c6a3579 e origin/main confirmou árvore idêntica. Main anterior permaneceu em 1d7f051 até esse merge. Publicações automáticas iniciadas: Hub2You [36712108138](https://github.com/autonom-ia2/chat/actions/runs/36712108138) e Autonom.ia [36712108156](https://github.com/autonom-ia2/chat/actions/runs/36712108156); resultado e verificação pós-deploy ainda pendentes nesta etapa.

## Resultado em produção

Os workflows Hub2You 36712108138 e Autonom.ia 36712108156 concluíram com sucesso em e45fbe68945f948525dcc0a2997eae5c3c9dc74f. Nas duas stacks: serviços web/worker ativos, imagens Docker correspondentes, target group healthy, HTTP local e HTTPS público 200, SSO público 302. Sonda de leitura confirmou o SHA, rotas de resumo/mídia, serviços compartilhados, vips/ffmpeg/pdftoppm e CSS compilado com 37rem; 11 verificações de fonte/runtime aprovadas em cada stack. Sem consultas de dados de cliente nessa sonda.

Navegador real da Hub2You, conta 16, viewport CSS 1470px: listas de Contatos e Empresas com quatro indicadores carregados e sem alerta; contato abre em Notas, empresa em Contatos. Laterais mediram 592px, fonte raiz 16px. Os três botões do contato mediram 44px de altura na mesma linha; as cinco abas exibiram nomes completos, incluindo Mesclar. A empresa exibiu cinco miniaturas de 96 × 96px, três imagens carregadas e dois ícones de arquivo. O contato de exemplo não tinha anexos: consulta 200 e estado vazio correto. Contato com anexos e comportamento móvel foram verificados em dados sintéticos, não em registros reais deste teste. Nenhum envio, ligação, bloqueio, exclusão ou edição de registro de cliente.

Uma primeira consulta da lista de mídias da empresa após a troca respondeu 500 em 14.988ms, com Rack::Timeout::RequestTimeoutException; ActiveRecord registrou 10.586,2ms em sete consultas. Nova tentativa respondeu 200 em 2.853ms; reabertura sem tentar novamente respondeu 200 em 585ms e mostrou as miniaturas. A causa da lentidão inicial não foi confirmada. Ocorrência preservada na issue [#794](https://github.com/autonom-ia2/chat/issues/794), com investigação de desempenho separada, sem aumentar limite nem esconder a falha com novas tentativas automáticas. Não atribuir a ocorrência ao idioma: os frames de SwitchLocale envolvem a ação, mas não demonstram falha de tradução.

Rollback confirmado em ambas: parâmetros previous-* apontam para as instâncias anteriores à entrega, já paradas e preservadas, correspondentes à versão 1d7f051a2655ef98cdc6ac70fa8b6f1a89c4cfe7. Nenhum rollback executado. A aceitação em navegador foi na Hub2You; na Autonom.ia foram conferidos serviços, fonte/runtime e endpoints públicos, sem sessão interna autenticada nesta verificação. Este registro não afirma ausência absoluta de regressões.
