# Auditoria — implementação de Links e QR codes

Issue #823 / PR #824 / branch codex/823-links-qr-mock. Implementação autorizada por Rodrigo após o aceite do mock, incluindo remoção da Gestão de campanhas, temas claro/escuro e renomeação para E-mails.

Página Vue própria em campaigns/links, entre E-mails e Modelos WhatsApp. Reutiliza a API existente de links rastreáveis, sem alteração de banco ou contrato. O gate continua CRM habilitado e acesso a campanhas, independente do adicional de e-mail. Criar/excluir requer campaign_manage; compartilhar permanece acessível a quem pode visualizar. QR e download usam short_url para preservar a atribuição existente. Gestão de campanhas mantém somente relatórios de e-mail. Conferidos app e enterprise, sem override correspondente.

Catálogos en/pt_BR do fork atualizados juntos; título também atualizado em pt para evitar sobrescrever o fallback. Guia atualizado em porques.md e gerado pelos scripts oficiais. A configuração Prettier existente de whitespace foi estendida apenas aos dois novos componentes.

Validações lidas antes de commit:

- Vite build completo passou em 35,99s; avisos de tamanho de chunks e Browserslist preexistentes.
- ESLint dos arquivos Vue/JS tocados: zero erros; avisos de chaves dinâmicas e catálogos legados.
- Suíte existente sidebar/localeLoader: quatro arquivos e 25 testes passando. fake-indexeddb instalado apenas em /tmp e setup local ignorado; nenhuma dependência do produto alterada.
- check-fork-i18n: nove catálogos, 16088 mensagens compiladas, en/pt_BR cobertos. guia:check em dia: 170 fluxos, 171 telas e nenhuma tela sem explicação. git diff --check passou.
- Chromium headless em perfil temporário isolado, localhost:38231: componentes Vue e stylesheet reais com API em memória fictícia. Passaram QR decodificado para short_url, cópia para clipboard, PNG baixado, criação e recuperação de erro, busca, seleção, cancelamento e confirmação de exclusão, papel somente leitura, estado vazio, erro/retry, erro de inbox, ausência de inbox, inglês e mobile 390px sem overflow horizontal. Nenhum pageerror.
- Capturas da lista e criação em claro/escuro revisadas visualmente. Screenshot identifica QA local/dados fictícios. Prévia aberta no Codex. Essa evidência não demonstra integração com banco, aplicação completa autenticada nem produção.

QA scripts e logs preservados em .codex/823 (ignorados). Capturas em /Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f880-afc9-7512-be42-b3b1a48572c8, prefixo links-qr-vue. Mock original mantido como referência histórica aprovada.

Follow-up de CI: central inicialmente falhou por rota sem artigo. Escrito artigo 13.13 conforme kit-do-escritor; artigo 13.11 separado para análise de e-mail e 13.10 corrigido quanto à localização dos links. Mapa atualizado com a rota nova. central:check passou com 175 artigos/171 telas cobertas; avisos históricos de evidências não alteradas permanecem. Revisados texto e diff antes de commit.

Segundo agente autorizado fez revisão geral de português nos menus/perfil/configurações. Confirmou que pt/crm sobrescrevia rótulos com português europeu. Alinhado somente TRACKED_LINKS ao português brasileiro existente, preservando PAGE no fallback pt_BR. check-fork-i18n e JSON/diff passaram. Demais achados de perfil/sidebar/MFA são tratados pelo agente de tradução no PR #826; não foi declarada revisão completa de todos os catálogos do produto.

Revisão final de concordância: contador da lista usa pluralização nativa do i18n. Conferidos 0/1/2 em en e pt_BR (1 campanha, 2 campanhas). ESLint, check-fork-i18n e matriz de navegador repetidos após a alteração: passaram, sem erros de página.

Revisão do autor concluída; revisão independente do código e idioma concluída pelo segundo agente autorizado. Trabalho de tradução do menu separado em #825/#826. Rodrigo posteriormente autorizou explicitamente fechar o lote e publicar em produção. Publicação reunida em release/2026-10-01-lote3; não existem migrações. Rollback operacional pelo workflow oficial action=rollback, confirm_production=true nas duas stacks, com versão anterior bd2104837da812a91587189b33b2f23daabc6583 confirmada nos parâmetros de runtime. O checkout não contém o helper Husky exigido pelo hook; commit usa core.hooksPath=/dev/null somente neste comando, após validações explícitas.

Revisão independente detectou inconsistência antiga: a API criava/excluía links com campaign_view, enquanto a nova UI requer campaign_manage. Corrigidas somente duas autorizações no controller, reutilizando CampaignPolicy create?/destroy?, já utilizada pelas campanhas; listagem e escopo por conta preservados. Revisor aprovou após ajuste. RuboCop: um arquivo, nenhuma infração. Testes existentes da API e permissões Enterprise: 21 exemplos, zero falhas, em banco local isolado. Sem alteração de login, credenciais ou configuração de papéis. Uma tentativa inicial incluiu caminho de spec inexistente e executou zero exemplos; corrigido o comando e lido o resultado acima antes de commit.
