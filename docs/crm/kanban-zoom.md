# Zoom do Kanban

Issue: [#839](https://github.com/autonom-ia2/chat/issues/839). Referência visual aprovada: `mockup_crm_kanban_zoom.html` fornecido por Rodrigo em 02/10/2026. SHA-256: `7ab512c2c694e3852f06dabc4e7f65c967b8b1e8a09cc309a89ea1f5b69076c8`.

## Contrato funcional aprovado

A barra mantém esta ordem: **Funil → Criar funil → Buscar por nome → Mais filtros → Encontrar com IA → Zoom**. A busca cede espaço ao novo controle. Criar funil permanece sem borda decorativa. O controle tem largura fixa para não deslocar a busca quando o percentual muda de dois para três algarismos.

A lupa abre um popover com o percentual atual, menos/mais, cinco atalhos e a indicação de persistência. Cada clique muda **1 ponto percentual**. O intervalo permitido é **70% a 130%, inclusive**. Menos fica desabilitado em 70%; mais, em 130%. Os atalhos são **80%, 90%, 100%, 110% e 120%**. Apenas uma correspondência exata fica destacada; em 87%, nenhum atalho é marcado. O valor inicial é 100%.

Somente o quadro muda de escala: colunas, cabeçalhos das etapas, cards e seu conteúdo. Menu, cabeçalho da página, busca, filtros, botão de zoom, drawers e modais não mudam de escala. Lista e Calendário não exibem o controle e não recebem zoom. Retornar ao Kanban restaura a escolha. Trocar de funil mantém a mesma preferência.

Escape e clique fora fecham o popover. O foco entra no painel ao abrir; Escape o devolve à lupa. Os controles funcionam por teclado, têm nomes acessíveis, estados desabilitados nativos e área de interação de pelo menos 44 px. O percentual é anunciado de forma não interruptiva. Não são interceptados atalhos ou gestos de zoom do navegador.

## Preferência e abrangência

Reutiliza o helper `LocalStorage` e a convenção já existente nas preferências de apresentação do CRM. A chave é `chat2you.crm.kanban.zoom.v1:<user_id>:<account_id>`. O valor é um número inteiro JSON, por exemplo `87`. O helper também mantém seu timestamp habitual `:ts`.

A preferência pertence ao **usuário e à conta, neste navegador/origem**. É preservada ao navegar, atualizar a página e reabrir o mesmo navegador, enquanto os dados do site forem mantidos. **Não sincroniza entre computadores, navegadores, perfis ou domínios**. Limpar os dados do site remove a preferência. Em navegação privada, vale a política de retenção do navegador. Troca de usuário/conta não herda a escolha de outra identidade; abas da mesma origem acompanham mudanças por `storage`.

Valores ausentes, corrompidos, não inteiros ou fora da faixa restauram 100%. Falha ao gravar não impede o zoom, mas substitui a indicação de escolha salva por uma mensagem explícita de falha. Não há escrita de uma preferência anônima antes da identificação de usuário/conta.

## Implementação e decisões de segurança de layout

- `CrmKanbanZoom.vue`: controle visual reutilizando o `Popover` do produto, tokens de cor do tema e textos em `en`/`pt_BR`.
- `useCrmKanbanZoom.js`: validação, limites, estado, isolamento e armazenamento local. Não consulta nem modifica dados do CRM.
- `useCrmKanbanAutoScroll.js`: rolagem de borda restrita ao arraste, com coordenadas do viewport e limites do layout. Respeita deslocamentos negativos em RTL; encerra listeners e animação ao soltar, cancelar, perder foco ou desmontar o quadro.
- `kanbanZoom.js`: constantes e utilitários Tailwind literais para os 61 níveis; a lista explícita evita perda de classes no build de produção.
- `CrmKanbanPage.vue`: controle no fim da barra, aplicação de `zoom` nativo somente ao quadro, largura da página fixada à área disponível e wrapper do preview de arraste.

Usar somente `transform: scale()` não é equivalente: pode deixar área de rolagem e coordenadas sem relação com o tamanho mostrado. A implementação usa `zoom`, que participa do layout, e mantém as rolagens do quadro/colunas. A largura da página precisa permanecer `w-full`: sem isso, o tamanho intrínseco do quadro reduzido pode encolher também o cabeçalho e a barra.

### Arraste por mouse e toque

A ordenação interna de cada coluna continua sendo automática, pela regra existente do CRM (`sort=false`). Esta entrega **não cria reordenação manual**. Arrastar entre etapas mantém a API e as regras atuais.

O Sortable calcula o preview em coordenadas do viewport. Mouse e toque usam a mesma implementação de preview (`force-fallback=true`), evitando divergências do arraste HTML nativo em áreas recortadas com zoom. Um limiar de 4 px separa clique de arraste. Deixar o clone dentro de um ancestral com zoom aplicaria a escala duas vezes. Por isso o preview fica no `body`, fora do quadro. Um wrapper mantém posição e dimensões nas coordenadas do viewport; somente o card filho do preview recebe a escala selecionada, com largura automática. As classes condicionais se aplicam exclusivamente quando o Sortable adiciona `crm-kanban-drag-preview`. O card normal não recebe uma segunda escala. As opções são passadas por `v-bind` para manter os tipos booleano/número reais recebidos como atributos pelo Draggable.

O wrapper também recebe a direção `ltr`/`rtl` da conta, pois o clone no `body` não herda a direção do aplicativo. O quadro bloqueia o clique residual gerado ao terminar um arraste; um novo `pointerdown` libera o clique normal, e ativação de teclado permanece permitida.

A rolagem automática usa `scrollWidth - clientWidth` e `scrollHeight - clientHeight`, sem somar medidas do viewport com medidas internas já escaladas. Em RTL, a faixa horizontal é negativa. O cálculo roda somente durante um arraste ativo e não interfere na rolagem normal pelo usuário.

A mudança de percentual não remonta cards, não solicita listas/etapas novamente, não altera oportunidade, não recarrega a página e não faz requisições de persistência por clique. O custo é de apresentação e de uma pequena gravação local.

## QA reproduzível

Roteiro e execução contra a aplicação real: [tests/qa/kanban-zoom](../../tests/qa/kanban-zoom/README.md). Evidências visuais: [kanban-839](kanban-839/README.md). A auditoria registra resultados efetivamente executados, achados e limitações.

## Publicação e rollback

A entrega é exclusivamente frontend. Não há migração, nova variável de ambiente, credencial, serviço, alteração de API ou limpeza de dados de produção. A autorização para implementação **não autoriza merge nem deploy**.

Após aprovação de Rodrigo: conferir checks do PR e branch base atual; mesclar pelo fluxo normal do repositório; executar o workflow de release/deploy já existente para o ambiente explicitamente aprovado, sem criar um caminho paralelo de publicação. Identificar o release anterior antes da publicação.

No smoke test do ambiente autorizado: confirmar 100% no primeiro acesso; selecionar 87%, navegar/recarregar e confirmar persistência; testar 70%/130%, arraste entre etapas, rolagem à última coluna e retorno de Lista/Calendário; confirmar que toolbar, filtros e drawers não escalam. Não movimentar oportunidades reais sem autorização para os registros de teste.

Em regressão: reverter o commit/PR e reconstruir/publicar o frontend pelo processo existente, ou republicar o release anterior conforme o procedimento do ambiente. A chave local não afeta versões anteriores; sua remoção não é requisito de rollback. Não é necessário rollback de banco de dados.
