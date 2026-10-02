# #792 — Parte 11: navegação e integridade, com bloqueios explícitos

Três capturas reais da aplicação compilada em ambiente local, com APIs/PostgreSQL de teste e dados fictícios. Não são imagens geradas nem o protótipo HTML. **Não certificam a segurança de escrita dos perfis de consulta**: a auditoria reproduziu falhas na autorização de contato/empresa que continuam abertas.

| Imagem | Estado verificado |
|---|---|
| [01-perfil-personalizado-sem-travamento.png](01-perfil-personalizado-sem-travamento.png) | O acesso à empresa continua negado ao papel personalizado, mas agora a aplicação retorna à lista Contatos já autorizada, sem ciclo de redirecionamento. |
| [02-oportunidades-autorizadas-preservadas.png](02-oportunidades-autorizadas-preservadas.png) | A ficha do contato continua mostrando apenas as duas oportunidades que esse usuário pode consultar. Não significa que todos os seus botões ou endpoints de escrita foram certificados. |
| [03-perfil-personalizado-celular.png](03-perfil-personalizado-celular.png) | Mesma consulta de oportunidades no painel móvel, integralmente dentro da viewport de 390×844. |

## Evidência de validação

`manifest.json` contém cinco verificações do navegador, os hashes das fontes/PNGs e ausência de gravação de negócio no roteiro. `contact-regression.json` registra 14 verificações adicionais e comparação integral no banco da pessoa e seus oito cards. Os 19 checks de navegador são caminhos concluídos; não incluem os defeitos de autorização de escrita ainda pendentes.

`concurrency.json` demonstra seis disputas reais de duas conexões PostgreSQL: anexar conversa e trocar contato competem pelo mesmo card; uma operação confirma e a incompatível é recusada. Os testes versionados reproduziam sete falhas antes da correção. `backend-summary.json` contém 544 exemplos, zero falhas e quatro suspensos históricos separados dos 540 aprovados. A suíte frontend completa passou com 7.081 testes em 634 arquivos. `compiled-assets.json` identifica o bundle real utilizado.

## O que NÃO passou como liberação

`permission-findings.json` contém três reproduções de escrita indevida por permissões insuficientes, não testes de segurança aprovados. Os dados foram criados em transações sintéticas e revertidos; não foram acessados usuários ou bancos da AWS.

`release-blockers.json` registra que o revisor independente configurado foi recusado pelo Codex autenticado (BLOCKED_MODEL_TIER, sem fallback) e que o workflow específico de Relacionamentos está desabilitado remotamente. Nenhum desses bloqueios é apresentado como uma aprovação ou como job simplesmente em execução.

A navegação da empresa permanece restrita, sem ampliação de papéis neste patch. O alinhamento de consulta/escrita e o eventual acesso de papéis personalizados precisam ser tratados no próximo incremento e revisados antes do merge.

[Auditoria completa, reprodução e próximos bloqueios](../../../audit/2026-10-01-792-crm-relationships-part-11.md). Sem merge ou deploy.
