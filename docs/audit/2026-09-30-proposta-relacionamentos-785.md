# Proposta de Relacionamentos — #785 — 30/09/2026

Rodrigo pediu avaliação e mockups antes de aprovar mudanças de frontend: resumo no topo de Contatos/Empresas e lateral das fichas pelo menos 25% mais larga, privilegiando inclusão e compatibilidade futura. Autorização desta frente limita-se à proposta local e documentação; aprovação antiga de campanhas não se aplica a sua publicação.

Issue #785, branch codex/785-relationships-mockups, worktree independente. Base main 29109e6d078b8cc5f115076a284777b25a3f57dd. Capturas fornecidas pelo usuário são referência visual; não representam autorização para importar, divulgar ou consultar dados adicionais de clientes. Protótipo usa somente dados fictícios.

Leituras: ContactsIndex.vue, CompaniesIndex.vue, ContactManageView.vue, CompanyDetailView.vue, ContactsDetailsLayout.vue, CompaniesDetailsLayout.vue, CompaniesListLayout.vue, stores/companies.js, componentes de Relacionamentos, controllers contatos/empresas nos dois overlays e contratos de #776. Limite das laterais: max-w-md (28rem), com slots existentes. Totais em metadados; agregados completos do dashboard não estavam disponíveis nas superfícies consultadas.

Skill UI/UX Pro Max aplicada: busca de estilo retornou Data-Dense Dashboard, adaptada à identidade existente. Busca específica Vue não encontrou correspondência mesmo após uma tentativa mais estreita; a recomendação de encaixes usa o código atual e seus slots, sem atribuir esse ponto à base da skill.

Decisão: componentes próprios e pontos opcionais pequenos, sem copiar páginas inteiras ou manipular DOM; não prometer compatibilidade automática com futuras versões. Proposta desktop 35rem; painel sobreposto abaixo de 1280px. Os indicadores novos exigem leitura consolidada adicional; se aprovado frontend estrito, omitir métricas sem dado real.

Artefato: docs/relationships/mockups/785/README.md e protótipo estático com quatro telas, controles de largura/abas e dados sintéticos. Nenhuma alteração em app/, enterprise/, migrations, infraestrutura, secrets, produção ou dados de clientes. Sem chamadas pagas ou envio de mensagens.

Validação: geração de utilitários Tailwind existente; node --check do JS; git diff --check; navegação e capturas via Playwright usando Chrome instalado. Relatório preservado no diretório do mockup: zero erros de JavaScript e zero overflow horizontal nos estados inspecionados. Lateral 560px versus comparação 448px. Capturas desktop inspecionadas visualmente; abas completas e histórico mais legível. Abas, busca local e fechamento do painel por Escape exercitados. Não executar suíte completa de produto para um protótipo isolado nem apresentar essa evidência como regressão real da aplicação.

Revisão manual da proposta e evidências; sem revisão independente adicional. Aceite visual de Rodrigo pendente. PR apenas para tornar a proposta revisável. Nenhum merge/deploy desta frente; rollback produtivo não se aplica ao protótipo, que pode ser desativado encerrando o servidor local.
