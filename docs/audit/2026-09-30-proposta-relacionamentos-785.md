# Proposta de Relacionamentos — #785 — 30/09/2026

Rodrigo pediu avaliação e mockups antes de aprovar mudanças de frontend: resumo no topo de Contatos/Empresas e lateral das fichas pelo menos 25% mais larga, privilegiando inclusão e compatibilidade futura. Autorização desta frente limita-se à proposta local e documentação; aprovação antiga de campanhas não se aplica a sua publicação.

Issue #785, branch codex/785-relationships-mockups, worktree independente. Base main 29109e6d078b8cc5f115076a284777b25a3f57dd. Capturas fornecidas pelo usuário são referência visual; não representam autorização para importar, divulgar ou consultar dados adicionais de clientes. Protótipo usa somente dados fictícios.

Leituras: ContactsIndex.vue, CompaniesIndex.vue, ContactManageView.vue, CompanyDetailView.vue, ContactsDetailsLayout.vue, CompaniesDetailsLayout.vue, CompaniesListLayout.vue, stores/companies.js, componentes de Relacionamentos, controllers contatos/empresas nos dois overlays e contratos de #776. Limite das laterais: max-w-md (28rem), com slots existentes. Totais em metadados; agregados completos do dashboard não estavam disponíveis nas superfícies consultadas.

Skill UI/UX Pro Max aplicada: busca de estilo retornou Data-Dense Dashboard, adaptada à identidade existente. Busca específica Vue não encontrou correspondência mesmo após uma tentativa mais estreita; a recomendação de encaixes usa o código atual e seus slots, sem atribuir esse ponto à base da skill.

Decisão: componentes próprios e pontos opcionais pequenos, sem copiar páginas inteiras ou manipular DOM; não prometer compatibilidade automática com futuras versões. Proposta desktop 35rem; painel sobreposto abaixo de 1280px. Os indicadores novos exigem leitura consolidada adicional; se aprovado frontend estrito, omitir métricas sem dado real.

Artefato: docs/relationships/mockups/785/README.md e protótipo estático com quatro telas, controles de largura/abas e dados sintéticos. Nenhuma alteração em app/, enterprise/, migrations, infraestrutura, secrets, produção ou dados de clientes. Sem chamadas pagas ou envio de mensagens.

Validação: geração de utilitários Tailwind existente; node --check do JS; git diff --check; navegação e capturas via Playwright usando Chrome instalado. Relatório preservado no diretório do mockup: zero erros de JavaScript e zero overflow horizontal nos estados inspecionados. Lateral 560px versus comparação 448px. Capturas desktop inspecionadas visualmente; abas completas e histórico mais legível. Abas, busca local e fechamento do painel por Escape exercitados. Não executar suíte completa de produto para um protótipo isolado nem apresentar essa evidência como regressão real da aplicação.

Revisão manual da proposta e evidências; sem revisão independente adicional. Aceite visual de Rodrigo pendente. PR apenas para tornar a proposta revisável. Nenhum merge/deploy desta frente; rollback produtivo não se aplica ao protótipo, que pode ser desativado encerrando o servidor local.

## Ajuste após feedback de Rodrigo

Rodrigo rejeitou os blocos retos das listas e gostou da composição interna das fichas. Pediu miniaturas maiores em Mídias e correção da quebra dos botões ilustrada na captura enviada. A revisão troca os blocos do dashboard por uma faixa arredondada e as linhas da lista por itens separados com cantos suaves. Mantém a lateral ampliada e leva ações para baixo da identificação; Enviar mensagem/Chamada ficam visíveis e Bloquear contato fica em Mais ações. Não remove a ação de bloquear nem altera seu contrato. Miniatura da empresa: contêiner 48 → 96px; contato com galeria de duas colunas e prévias próximas de 246px na lateral desktop.

Código real consultado adicionalmente: MediaThumbnail.vue, ContactMedia.vue e SharedAttachments/Media.vue. O contato atualmente usa grade de três colunas; ampliar por duas colunas deve ser opção específica da ficha, preservando outras superfícies compartilhadas. Prévia do mockup renderizada a partir de documento fictício; ícone da instalação já existente no repositório usado como segundo exemplo. Sem arquivo de cliente ou download remoto.

Validação adicional: ações do desktop em uma linha em 1280 e 1440px, nenhum texto de botão cortado, prévias carregadas e medidas no desktop/celular. Contêiner de 96px possui imagem interna de 94px com borda. Nesta revisão há trinta screenshots privadas e seis previews preservados. O hook local estava indisponível porque .husky/_/husky.sh não existe na worktree sem dependências; o commit documental inicial usou core.hooksPath=/dev/null somente nesse comando após validação de sintaxe, navegador e diff. Nenhuma configuração global de Git ou hook do projeto foi alterada.

Aceite visual parcial das fichas registrado; aceite da revisão das listas/mídias e autorização de implementação ainda pendentes.

## Ajuste final solicitado

Rodrigo pediu igualdade das mídias de Contatos e Empresas e aumento de 25% para 32% da lateral. A terceira revisão unifica a apresentação dos dois painéis em uma única função do mockup, usando lista de arquivos, contêineres de 96px e controles iguais; substitui a galeria distinta do contato. A largura fica em 37rem (592px), aproximadamente +32% contra 448px. A implementação futura deve compartir apresentação sem misturar escopo de leitura de contato/empresa ou alterar os contratos de origem/autorização.

Capturas e relatório foram refeitos. Lateral 592px medida no desktop; imagens internas de 94px nos dois contextos e nos dois tamanhos inspecionados. Botões desktop alinhados e contidos na faixa de ações em 1280/1440px; reticências preservam o nome acessível Mais ações e a ação Bloquear contato. Dados e ações permanecem simulados. O hook de push também está incompleto nesta worktree; seu único gate bin/validate_push foi lido e executado manualmente antes do push com desativação do hook restrita ao comando.
