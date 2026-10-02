# Parte 12 — Consulta e edição de cadastros separadas

Aplicação real compilada com Rails/PostgreSQL locais e dados fictícios. Não são imagens geradas ou o mockup HTML. Não demonstram publicação na AWS.

| Captura | Estado |
|---|---|
| [01-contato-somente-consulta.png](01-contato-somente-consulta.png) | Ficha do contato sem formulário de escrita, notas editáveis ou mesclagem para o leitor. |
| [02-empresa-somente-consulta.png](02-empresa-somente-consulta.png) | Papel personalizado abre a empresa em modo consulta, com seus registros comerciais permitidos. |
| [03-consulta-empresa-celular.png](03-consulta-empresa-celular.png) | Mesma consulta no painel móvel, sem corte horizontal. |
| [04-oportunidade-existente-sem-editar-cadastro.png](04-oportunidade-existente-sem-editar-cadastro.png) | Gestor comercial pode cadastrar negociação com pessoa existente sem possuir gestão cadastral. |
| [05-card-com-cadastro-protegido.png](05-card-com-cadastro-protegido.png) | Negociação criada de verdade, com mesmo contato/empresa e sem controles de editar esses registros. Card de 640px. |
| [06-novo-cadastro-sem-permissao.png](06-novo-cadastro-sem-permissao.png) | Criar novo indisponível, com explicação; contato existente e oportunidade sem vínculo preservados. |
| [07-gestor-de-cadastro-com-edicao.png](07-gestor-de-cadastro-com-edicao.png) | Com contact_manage, os formulários de cadastro permanecem acessíveis. |
| [08-todas-oportunidades-sem-cota-de-duas.png](08-todas-oportunidades-sem-cota-de-duas.png) | Administrador consulta oito oportunidades em duas páginas. Não existe limite de duas oportunidades. |

## Resultado e rastreabilidade

13 verificações próprias de navegador + 14 de regressão do contato = 27. O código rodou em bundle compilado sem HMR; nenhum resultado de negócio foi simulado. A regressão antiga conserva a interrupção proposital de um GET para testar retentativa. Os manifestos registram os avisos/404 locais e nenhuma exceção JavaScript nos caminhos concluídos.

A UI fez uma criação comercial explícita. O servidor recusou três tentativas indevidas de escrita: pessoa, empresa e cadastro composto sem permissão cadastral. `persistence.json` compara o banco antes/depois: somente uma oportunidade acrescida, mesmos 49 contatos/23 empresas/33 mensagens/oito conversas e registros compartilhados integralmente intactos.

Frontend completo: 7.098 testes em 636 arquivos aprovados. Backend: 598 exemplos, 594 aprovados e quatro suspensos antigos separados. Os casos novos que falharam antes das correções e os ajustes de fixtures/stubs estão descritos na [auditoria](../../../audit/2026-10-01-792-crm-relationships-part-12.md).

`manifest.json` registra os checks, capturas, hashes e respostas HTTP; `compiled-assets.json` contém os hashes das entradas compiladas; `contact-regression.json` conserva a reexecução do fluxo antigo e seu baseline próprio; `frontend-summary.json`/`backend-summary.json` distinguem passados/falhas/suspensos. Credenciais e snapshots completos permanecem fora do repositório, em arquivos locais de QA.

Aguardar aprovação deste incremento. Revisão transversal, CI específico e revisão independente continuam pendentes antes de merge/deploy.
