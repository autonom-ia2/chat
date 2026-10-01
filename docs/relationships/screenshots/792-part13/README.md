# #792 — Parte 13: conversas e origens autorizadas

Capturas da aplicação real compilada, com APIs/PostgreSQL locais, login normal e registros fictícios. Não são imagens geradas nem o HTML do mockup; não comprovam publicação na AWS.

O mesmo card é consultado por um perfil com acesso somente à caixa comercial e por um administrador autorizado às duas caixas. Cada campanha é projetada conforme a conversa de origem. O roteiro também confere filtros e totais sem alterar os dados. A lateral continua com 640px no desktop e ocupa a largura disponível no celular.

| Arquivo | Estado |
|---|---|
| [01-oportunidade-com-origem-permitida.png](01-oportunidade-com-origem-permitida.png) | Oportunidade acessível, com a campanha permitida e sem a origem restrita. |
| [02-relacionamento-preservado.png](02-relacionamento-preservado.png) | Mesmo cadastro compartilhado e aviso de consulta, com o desenho aprovado preservado. |
| [03-somente-conversa-autorizada.png](03-somente-conversa-autorizada.png) | Aba Conversas mostrando somente o atendimento permitido para esse usuário. |
| [04-conversa-autorizada-celular.png](04-conversa-autorizada-celular.png) | A mesma consulta em 390×844, sem corte horizontal do card. |
| [05-administrador-conversas-permitidas.png](05-administrador-conversas-permitidas.png) | Administrador conserva as duas conversas autorizadas do mesmo contato/card. |

## Evidências

`manifest.json` registra 13 verificações, cinco capturas, identidade do navegador, respostas HTTP, ausência de escrita, hashes das fontes/PNGs e referências dos assets compilados. `compiled-assets.json` registra os hashes do bundle. `persistence.json` compara antes/depois: contato, dois cards e duas conversas intactos, sem alteração das contagens.

`backend-summary.json` separa aprovações e pendências antigas; `frontend-summary.json` registra a bateria completa. `timing-recheck.json` conserva as falhas iniciais de tempo e os resultados sequenciais, sem alterar limites ou desativar testes. Os três testes antigos de visibilidade foram reativados; os outros sete suspensos da seleção ampliada não são aprovações.

Nenhum resultado positivo de negócio foi simulado. Avisos locais, incluindo a consulta de limites Enterprise que retorna 404, permanecem no manifesto. Consultar a projeção não certifica todos os controles legados ou escritores assíncronos.

[Auditoria, contratos e limites](../../../audit/2026-10-01-792-crm-relationships-part-13.md). Revisão independente e runtime Linux específico permanecem gates de liberação. Aguardar aprovação de Rodrigo antes da próxima parte; sem merge/deploy.
