# #792 — Parte 14: atendimento e CRM com controles por permissão

Capturas da aplicação compilada, login normal, APIs e PostgreSQL locais, dados fictícios. Não são imagens geradas ou o HTML de demonstração. Não comprovam deploy na AWS.

A pessoa pode ter acesso à conversa sem poder editar o cadastro compartilhado ou gerenciar negociações. A lateral do atendimento continua com sua apresentação nativa; o card do CRM mantém 640px no desktop e se ajusta aos 390px do celular.

| Arquivo | Estado real |
|---|---|
| [01-atendimento-cadastro-em-consulta.png](01-atendimento-cadastro-em-consulta.png) | Contato dentro do atendimento em leitura, com aviso e sem os controles cadastrais de edição. |
| [02-notas-e-atributos-preservados.png](02-notas-e-atributos-preservados.png) | Notas e atributos existentes continuam consultáveis; os controles de criação/exclusão não são oferecidos ao leitor. |
| [03-acoes-atendimento-sem-criacao-comercial.png](03-acoes-atendimento-sem-criacao-comercial.png) | Etapa atual do CRM permanece disponível, sem oferecer criação de card ao perfil que só consulta o CRM. |
| [04-follow-ups-somente-consulta.png](04-follow-ups-somente-consulta.png) | Lembrete e cadência no card, sem criar, concluir, cancelar, resetar ou arquivar pelo perfil de consulta. |
| [05-consulta-follow-ups-celular.png](05-consulta-follow-ups-celular.png) | Mesma consulta no celular, sem rolagem horizontal e com ação de fechamento acessível. |
| [06-edicao-autorizada-no-atendimento.png](06-edicao-autorizada-no-atendimento.png) | Gestor cadastral editando o nome do mesmo contato; a gravação é conferida pela API e pelo banco. |
| [07-gestor-com-acoes-preservadas.png](07-gestor-com-acoes-preservadas.png) | Gestor com as permissões explícitas conserva as ações comerciais e o controle cadastral. |

## Evidências

`manifest.json` contém ações, requisições, identidade da página, console, hashes das fontes/PNGs e assets compilados. `persistence.json` confere a única alteração cadastral solicitada e a preservação dos demais registros/contagens. Atualizações nativas de estado de leitura, caso ocorram, são registradas separadamente; não são confundidas com envio de mensagem.

`backend-summary.json` separa 744 aprovações dos sete testes antigos suspensos. `frontend-summary.json` registra 7.120 testes completos em 639 arquivos e a reexecução direcionada dos 47 testes após o ajuste final de handlers explícitos. Nenhum timeout ou expectativa foi relaxado. `compiled-assets.json` contém os hashes da compilação usada.

O ensaio real usa a superfície de atributos legada, com a configuração nova opcional desabilitada apenas na conta sintética; o valor anterior é restaurado depois da comparação. Os testes de componente cobrem também a superfície nova habilitada. Não há concessão de permissão por booleano do cliente: as tentativas diretas proibidas são recusadas pelo servidor.

[Auditoria, contratos e limites](../../../audit/2026-10-01-792-crm-relationships-part-14.md). Revisão independente, runtime Linux específico, testes históricos e entradas pendentes continuam gates. Parar para aceite de Rodrigo; sem merge/deploy.
