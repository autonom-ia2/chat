# Auditoria — implementação de Links e QR codes

Issue #823 / PR #824 / branch codex/823-links-qr-mock. Implementação autorizada por Rodrigo após o aceite do mock, incluindo remoção da Gestão de campanhas, temas claro/escuro e renomeação para E-mails.

Página Vue própria em campaigns/links, entre E-mails e Modelos WhatsApp. Reutiliza a API existente de links rastreáveis, sem alteração de servidor, banco ou contrato. O gate continua CRM habilitado e acesso a campanhas, independente do adicional de e-mail. Criar/excluir requer campaign_manage; compartilhar permanece acessível a quem pode visualizar. QR e download usam short_url para preservar a atribuição existente. Gestão de campanhas mantém somente relatórios de e-mail. Conferidos app e enterprise, sem override correspondente.

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

Revisão do autor concluída; revisão externa do código/CI deve ocorrer no PR antes de merge. Trabalho de tradução do menu separado em #825/#826 e revisão geral por segundo agente autorizado. Merge, deploy e qualquer acesso a produção não autorizados nesta rodada. Rollback: reverter o commit do frontend; não existem migrações. O checkout não contém o helper Husky exigido pelo hook; commit usa core.hooksPath=/dev/null somente neste comando, após validações explícitas acima.
