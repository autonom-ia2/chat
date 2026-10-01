# Traduções dos módulos próprios (#772)

A fonte de verdade é o repositório. `config/fork_i18n.json` registra o overlay: agentes, importação, CRM, proteção de e-mail, seguros, primeiros passos, prospecção e relacionamentos. Os catálogos continuam nos caminhos já usados pelo painel; não existe cópia alternativa da mesma tradução.

O Crowdin continua responsável pelos catálogos do Chatwoot. `crowdin.yml` exclui os módulos registrados. O check obrigatório `Fork translations` impede que um PR de sincronização automática altere esses catálogos e confere a configuração de exclusão, as chaves e os parâmetros das mensagens. Atualizações do upstream precisam preservar esses arquivos e seus imports; resolver conflitos sem substituir as traduções do fork.

Textos exclusivos do fork que já estão em catálogo compartilhado continuam no catálogo atual; alterar somente suas chaves em `en` e `pt_BR`, sem excluir o arquivo inteiro do Crowdin. A orientação de cabeçalhos da importação de e-mail em `campaign.json` segue esse caso.

O workspace de campanhas (#800) também segue esse caso: `CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE` fica em `campaign.json`. O check `scripts/check-email-protection-i18n.mjs` confere as mesmas chaves, parâmetros e a renderização real desse namespace em inglês e português brasileiro. A regra de origem inglesa do upstream não proíbe traduzir os recursos próprios do Chat2You; traduções dentro de uma entrega autorizada não precisam de aprovação separada.

Os módulos próprios exigem inglês e português brasileiro, com as mesmas chaves e parâmetros. As traduções já existentes dos demais idiomas são preservadas. Quando um idioma não tem tradução própria, o painel mantém seu fallback atual; isso não constitui promessa de tradução completa para todos os idiomas do Chatwoot.

Exceção histórica explícita: Prospecção já tinha os textos em português no arquivo `en/prospecting.json`, usados pelo fallback. Nesta entrega, `pt_BR/prospecting.json` assume a fonte de verdade em português e entra no índice pt_BR, mantendo a apresentação existente. O arquivo `en` permanece compatível enquanto sua tradução completa para inglês fica acompanhada na #780. Essa exceção está registrada por catálogo e não autoriza novas strings portuguesas nos outros catálogos ingleses.

Para adicionar um módulo:

1. Registrar o arquivo e sua fonte em `config/fork_i18n.json` e adicionar a exclusão correspondente em `crowdin.yml`.
2. Criar os catálogos completos `en` e `pt_BR`, importar e compor ambos em seus índices. Manter nomes de marcas, parâmetros e identificadores de API.
3. Alterar fonte e tradução pt_BR no mesmo PR. Outros idiomas podem ser incluídos no mesmo processo, sem serviço externo obrigatório.
4. Rodar `pnpm i18n:fork:check`, os testes da tela e a compilação do painel. O check também compila as mensagens e compara parâmetros nomeados.

A política não configura projetos externos, credenciais, glossários remotos ou serviços pagos. Mudanças nos textos do backend continuam seguindo a política do catálogo `en.yml` e do Crowdin.
