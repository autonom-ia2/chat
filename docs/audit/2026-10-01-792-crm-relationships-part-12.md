# #792 — Parte 12: consulta e edição de cadastros compartilhados

## Autorização e escopo

Rodrigo aprovou a parte 11 e autorizou separar consulta de edição no servidor e nas telas. Base `197bc31c207ddb707b521c6586d393659a11a4c8`, branch/worktree exclusiva `feat/792-crm-relacionamentos`, Issue #792, PR #793 em rascunho. Parar para aprovação do incremento. Sem merge, deploy, alteração da AWS, usuários reais, dependências ou migração.

Não existe cota de duas oportunidades. Nenhum escopo de visibilidade, limite comercial ou tamanho de página foi alterado. Os dois cards dos exemplos anteriores eram dados sintéticos de um papel restrito. Este ensaio também consulta oito oportunidades autorizadas em duas páginas, conservando os cinco itens por página do contrato existente.

## Contrato de permissões

| Contexto | Cadastro compartilhado | Oportunidade |
|---|---|---|
| Administrador | Mantém os direitos anteriores. | Mantém os direitos anteriores. |
| Agente padrão, sem papel personalizado | Mantém criação/edição de cadastros já permitidas. | Mantém as regras anteriores do CRM. |
| Papel personalizado com `contact_view` | Consulta os cadastros, sem as escritas abaixo. | Só consulta se também possui os direitos de CRM exigidos. |
| Papel personalizado com `crm_manage_cards`, sem `contact_manage` | Não cria/edita pessoa ou empresa por consequência do direito comercial. | Pode criar/gerenciar uma oportunidade com pessoa existente ou sem vínculo, conforme os demais gates atuais. |
| Papel personalizado com `contact_manage` | Pode criar/editar o cadastro. Não recebe exclusão integral, gestão de atributos da conta ou CRM implicitamente. | Continua precisando da permissão própria para criar/gerenciar negociações. |

O helper Enterprise `Relationships::RecordPermissions` é compartilhado entre ContactPolicy e CompanyPolicy. A autorização real exige `contact_manage` apenas dos papéis personalizados; administrador/agente sem papel preservam o contrato. O overlay de ContactPolicy mantém importação/exportação anteriores. Exclusão integral de pessoa/empresa continua administrativa. Definir/configurar campos da conta continua separado de editar seus valores.

Os contratos já existentes de leitura de API foram preservados. Isto não é uma reescrita do ACL de todos os módulos: leitores internos, importações de campanhas e integrações continuam tendo suas próprias entradas. Os tokens exclusivos de CRM e os bots não receberam endpoints ou scopes extras. O helper nativo de bots já nega os endpoints de cadastro fora da lista de conversas autorizada.

### Escritas protegidas

As policies cobrem criar/editar pessoa e empresa, avatar e valores personalizados. Entradas que não consultavam a policy de atualização passaram a fazê-lo: notas do contato (criar/editar/excluir), etiquetas, mesclar contatos e ações em lote de contatos. A mesclagem autoriza ambos os registros; o lote conserva a regra administrativa para exclusão. Associação/desassociação empresarial e opt-out já tinham a chamada de autorização e passam a aplicar a policy corrigida.

Cadastro composto e criar pessoa no card existente já autorizavam Contact/Company; passam a recusar o papel comercial sem direito cadastral. A resposta segue o envelope existente HTTP 401 de autorização, sem registro parcial. Gerenciar o vínculo **card → contato existente** não edita a pessoa; essa ação continua pertencendo à permissão comercial. Já **contato → empresa** altera o cadastro e exige gestão cadastral.

Nenhuma autorização vem da quantidade de oportunidades, de um booleano enviado pelo navegador ou do texto do papel.

## Experiência nas telas

`useRelationshipPermissions` espelha as capabilities para a interface; a policy do servidor continua sendo a autoridade. Fichas canônicas recebem `readOnly` explicitamente nos componentes de dados, avatar, etiquetas, opt-out, notas, atributos e associação de contatos. Os dados confirmados permanecem visíveis, com aviso de consulta e sem formulário de gravação. Valores zero/falso não são apagados ou confundidos com vazio. Botões de criação e ações em lote também respeitam a permissão.

A ficha de empresa passa a aceitar `contact_view` e `contact_manage` na navegação, além dos papéis nativos. Isso alinha o acesso da tela à consulta já disponível na API, **sem liberar escrita ao leitor**. A restrição/loop que motivou as partes 10–11 deixa de bloquear a consulta empresarial. O guard anterior continua válido para outros destinos não autorizados. Nenhum usuário ou papel real foi modificado.

No card do CRM, `canManageCards` e `canManageRecords` são independentes. O gestor comercial pode seguir com a negociação, mas não vê Editar pessoa/empresa, mudança de empresa ou edição dos valores personalizados sem `contact_manage`. Nova oportunidade distingue o modo existente/avulso da criação do zero: Criar novo fica indisponível sem o direito cadastral e o motivo aparece na interface. Revogar a capability impede submit de um rascunho novo sem apagá-lo.

A largura do card permanece 40rem/640px. Tokens, cores, componentes, abas e o desenho aprovado permanecem. As fichas mantêm as entradas anteriores: Notas no contato, Contatos na empresa. Não foi criado um app paralelo ou uma versão de dados só para consulta.

## Testes e falhas tratadas

O novo request spec `record_write_permissions_spec.rb` teve **24 exemplos, 21 falhas antes da correção**. Depois passou pelos mesmos 24: recusas reais de escrita, igualdade dos registros e contagens, criação composta sem sobras, leitura preservada, negociação com existente/sem vínculo, revogação de direito e compatibilidade de administrador/agente. As reproduções anteriores de PATCH/POST indevidos não são contabilizadas como segurança aprovada.

Dois testes antigos de replay tinham o primeiro cadastro autorizado somente por CRM. Seus cenários positivos agora incluem `contact_manage`; a segunda requisição após revogação e todas as asserções de recusa continuam intactas. Nenhum teste foi desativado para passar. A regressão ampliada inclui notas, etiquetas, ações em lote e mesclagem além do workflow de Relacionamentos/CRM.

Testes novos de UI verificam capabilities independentes, troca de conta, revogação, manutenção do rascunho, criação com contato existente e remoção de controles de edição/inclusão. Um teste novo inicialmente lia a capability da instância stub como atributo HTML; foi corrigido para verificar a prop booleana real, sem relaxar a expectativa `false`. Os testes anteriores mantêm explicitamente o cenário autorizado, em vez de depender de uma prop ausente.

O primeiro roteiro de navegador encontrou cinco cards em vez dos dois esperados: três eram fixtures legítimas do ensaio de concorrência da parte 11. Não era mudança de visibilidade nem quota. Apenas esses registros identificados, do banco sintético e funil de QA, foram arquivados antes de renovar o baseline; as políticas e os resultados reais não foram simulados.

## Evidências locais

Ambiente: Rails test/CI=true em 127.0.0.1:3792; banco UI `chat2you_792_ui_test` separado do banco RSpec `chat2you_792_test`; Redis 6792; adaptadores de teste de jobs/e-mail e nenhum worker de entrega. Browser plugin não disponível: Playwright/Chrome existente, sem instalação. Bundle compilado sem HMR; sem respostas de negócio simuladas no roteiro da parte 12. Desktop 1620×1000, celular 390×844 e regressão notebook 1366×768.

O roteiro próprio concluiu 13 verificações e oito capturas. O papel de consulta abriu pessoa e empresa sem editores; o servidor recusou PATCH direto de ambos. O gestor de oportunidades criou uma negociação real com pessoa existente, mas recebeu 401 ao tentar o cadastro composto. O gestor cadastral recebeu os formulários permitidos. O administrador consultou oito negociações em duas páginas, sem limite de duas. Nenhuma exceção JavaScript ocorreu nos caminhos concluídos; os avisos locais de limites Enterprise 404 permanecem registrados.

Conferência direta do banco: 49 contatos, 23 empresas, 87 → 88 oportunidades, 33 mensagens e oito conversas. O único acréscimo foi a oportunidade confirmada pela UI. Pessoa e empresa foram comparadas integralmente, com timestamps UTC de seis casas: intactas. A regressão de consulta da parte 9 usa baseline posterior separado e não sobrescreve sua galeria publicada.

| Validação final | Resultado |
|---|---|
| Frontend completo | **7.098 testes em 636 arquivos**, todos aprovados na reexecução final. |
| Backend ampliado | **598 exemplos: 594 aprovados, zero falhas e quatro suspensos anteriores**. |
| Contrato específico de autorização | 24 exemplos aprovados, incluídos na bateria maior; não somados novamente. |
| Navegador atual + regressão do contato | **13 + 14 = 27 verificações** concluídas; oito capturas novas. |
| Persistência após o roteiro atual | Uma oportunidade criada; mesmos cadastros/empresas/mensagens/conversas. |
| Persistência após a regressão do contato | Nenhuma gravação; contato e seus oito cards preservados integralmente. |
| Build | Vite test compilado aprovado, avisos existentes de tamanho de chunks mantidos. |
| ESLint / RuboCop | 31 arquivos JS/Vue, zero bloqueadores e 29 avisos de chaves dinâmicas; dez arquivos Ruby, nenhuma infração. |
| Traduções | Oito catálogos, 16.232 mensagens compiladas, en/pt_BR conferidos. |
| Guia / Central / AST | Gerados e conferidos; verificação de ausência de novos regex aprovada. |

Os quatro suspensos históricos continuam em `spec/models/account_spec.rb:52` e `spec/requests/api/v1/accounts/crm/cards_spec.rb:333,556,583`; não foram desativados nesta entrega nem contados como aprovados. Os hashes estão na galeria deste incremento, junto com o manifesto e a prova de persistência. Os roteiros/logs temporários ficam em `.codex/792/part12-*`. Não publicar credenciais, snapshots completos ou tokens de sessão.

## Governança e limites antes da liberação

Guia atualizado em `porques.md` e regenerado por comando, não editado diretamente. A matriz `docs/relationships/crm-integration.md` registra a mudança de contrato. Permissão de envio de mensagem, edição de definições, integração externa e exclusão integral não foram ampliadas.

Este incremento protege as entradas de cadastro verificadas e alinha a UI do CRM e das fichas/listas canônicas. Não certifica todos os escritores assíncronos, os controles legados dentro do atendimento, a revogação de uma permissão após um job já ter sido autorizado/enfileirado ou todas as políticas de leitura de módulos independentes. A revisão transversal continua necessária; não confundir este recorte com aprovação global do produto.

Continuam pendentes a revisão independente (`BLOCKED_MODEL_TIER` na tentativa anterior), o workflow específico de Relacionamentos desabilitado remotamente, a revisão dos quatro testes históricos suspensos e dos demais escritores/efeitos externos. Nenhum desses gates foi contornado, reabilitado ou apresentado como aprovado. Somente depois de fechar o conjunto será pedida autorização de merge/deploy; rollback de código não apaga os registros já confirmados.
