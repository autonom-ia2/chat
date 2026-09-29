# Publicação e rollback — #757

Estado: somente implementação local, sem commit/push/PR/merge/deploy nesta execução.
Issue #757 → branch feat/757-relacionamentos → revisão do supervisor → commits/PRs
escopados → Project → revisão independente → aprovação explícita → homologação/publicação.
Não interpretar este documento como autorização.

Os workflows deploy-autonomia-blue-green.yml e deploy-hub2you-blue-green.yml disparam em
push na main. Ambos foram apenas lidos. Nenhuma branch/main, workflow ou infraestrutura
foi alterada. A autorização da PR #756 não se aplica.

Antes de publicação: executar toda a matriz de qa-acceptance.md com backend isolado,
resolver falhas, capturar baseline/off/on, validar políticas Enterprise e conversores
na imagem real, revisar o conjunto e obter aprovação de stack, SHA e janela.
As três flags começam off; pilotar cada uma separadamente em conta sintética/homologação.
Nenhuma gravação na conta 16 real ou outra conta de cliente.

Rollback funcional: desligar independentemente relationships_attributes,
relationships_company_media, relationships_navigation pela administração existente,
apenas após aprovação de alteração do ambiente. Layout, definições, valores e derivados
ficam preservados; os caminhos legados reaparecem. Empresas continua com seu gate próprio.
Não existe migration nova. Reverter código não desfaz definições/valores já gravados.

Rollback do binário segue blue/green anterior da stack aprovada; validar web, worker,
SSO e filas. Não consumir o único degrau anterior com múltiplos deploys sem aceite.
Fila low existente pode terminar jobs já pedidos; o job verifica flags antes de converter.

Project remoto não foi acessado por proibição de operações remotas. Atualização pendente:
Project Autonom.ia Dev (users/autonom-ia/projects/3); Status Em andamento; Tipo Feature;
Prioridade P2; Risco Médio; Próxima ação executar integração/E2E e revisão independente;
Ambiente Local. O plano contém também o nome Projeto Hub2You; supervisor deve confirmar
qual registro corresponde ao Project explicitamente indicado no início do plano.
