# F1 — causas raiz e correção documental

**Data:** 2026-10-07  
**Branch:** `docs/agentes-ia-prd`  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Estado:** DRAFT; nenhuma implementação de produto autorizada.  
**Escopo:** uma correção documental de F1, mockup e seção de rota compatível do F0.

## Fontes da causa

- `docs/agentes-ia-redesign/revisoes/F1-desenho-normal-tecnica-seguranca.md`;
- `docs/agentes-ia-redesign/revisoes/F1-desenho-normal-produto-testes.md`;
- `docs/agentes-ia-redesign/design/F1.md`;
- `docs/agentes-ia-redesign/design/F0-mapeamento.md`;
- `docs/agentes-ia-redesign/mockup/src/screens-list.js`;
- `docs/agentes-ia-redesign/mockup/src/data.js`;
- PRD §6.1, CA-LISTA-04/05/07/08/15 e contratos B2/BE-05.

## Seis causas registradas antes da correção

1. **F1-TEC-01 — E2m não tinha ramificação compatível.** A tabela mandava tratar E2m junto do leitor
   BE-05, embora E2m seja manual e o contrato devolva `422 manual_mode`; com o gate novo ligado, o mesmo
   nome de rota abre a casca nova de `autonomia_agent_panel`, ainda não entregue. A causa é misturar
   retomada guiada e ajuste manual numa ação genérica. A correção mínima é ramificar E2m antes do BE-05 e
   usar uma rota legada nomeada, explicitamente disponível sob a flag nova enquanto F2–F7 não entregarem a
   casca correspondente; não criar tela falsa nem chamar `build_thread`.
2. **F1-TEC-02 — PATCH parcial podia destruir a projeção.** O CRUD/`EDIT` do store substitui o item pelo
   corpo parcial do `PATCH agents/:id`, mas a lista depende de `state`, `channels` e `stats` que esse corpo
   não devolve. A causa é reutilizar uma mutação genérica para uma projeção composta. A correção mínima é
   uma ação própria que envie somente `status`/`enabled`, não faça `EDIT`/`UPSERT`, e só substitua a projeção
   após GET bem-sucedido; se o GET falhar, conserva o item anterior e avisa que os dados estão desatualizados.
3. **F1-UX-01 — só ver não tinha Abrir nos rascunhos.** A fonte do mockup condicionava a ação de E1–E4 à
   permissão de editar, embora CA-LISTA-15 exija leitura nesses estados. A causa é tratar “Continuar” como
   única ação do cartão em vez de oferecer o fallback de “Abrir”. A correção é renderizar `Abrir` para só ver,
   mantendo Continuar/Ligar/escritas ocultos, e registrar a variante no aceite.
4. **F1-UX-02 — estatísticas não tinham forma fechada.** F1 nomeava `stats.week/month`, enquanto B2 usa
   `replies/handoffs` e o mockup usa índices `7/30` e `handed`. A causa é deixar a tela depender de uma forma
   visual de dados em vez do contrato B2/Analytics. A correção fecha `week/month.replies/handoffs`, períodos
   inclusivos iguais ao B2, texto “passou” derivado de `handoffs` e ausência de números para interno.
5. **F1-UX-03 — invalidation de teste não tinha mensagens de causa.** F1 dizia apenas “motivo localizado”,
   sem chaves, parâmetros ou frases distintas para `person` e `material`. A causa é transportar o enum sem
   fechar a explicação humana. A correção especifica as duas cópias do PRD, com nome e gênero derivados do
   enum seguro de voz (`{A}`/`{ela}`), sem inferir pelo nome.
6. **F1-TEST-01 — cenários não tinham fixtures reais nomeadas.** A lista do mockup só instancia Clara e Lia
   ativas externas; os cenários pedem interno, E4, E6 e rascunhos E1/E2/E2m/E3. A causa é listar estados sem
   fornecer uma matriz verificável de dados locais. A correção nomeia fixtures por estado/perfil/variante,
   vindas da API/banco local de teste, e registra como divergência intencional quando o mockup usa referência
   visual que ainda não é dado de produto.

Nenhuma alteração em F1, F0 ou mockup foi feita antes deste registro. A correção permanece documental:
não executar produto, Rails, banco, testes, build, navegador, produção, fila, push, PR ou merge.

## Correção documental aplicada

- E2m agora ramifica antes do BE-05 para `autonomia_agent_panel_legacy`/`tune`, uma entrada nomeada do
  painel legado disponível durante o staging mesmo com a flag nova ligada. Não há tela dummy, `href`
  arbitrário, criação de thread ou conexão de canal nessa exceção.
- Pausar/religar ganharam uma ação F1 própria: PATCH mínimo de `status`/`enabled`, sem `EDIT`/`UPSERT` ou
  atualização otimista; somente um GET posterior bem-sucedido substitui a projeção. Falha no GET preserva
  o registro anterior e mostra dados desatualizados.
- O contrato de stats foi fechado como `week/month.replies/handoffs`, com as janelas inclusivas do B2/
  Analytics e sem números para interno. Os textos de E3 agora distinguem material e pessoa e derivam o
  artigo apenas do enum seguro `voice`.
- Os cenários F1 passaram a citar fixtures locais nomeadas para E1–E6, E2m, interno, sem canal e as duas
  causas de E3. O mockup recebeu somente essas variantes de referência e o botão “Abrir” de só ver em E1–E4;
  a diferença entre `status`/stats do mockup e o contrato API real ficou registrada como intencional.

## Checagem estática limitada

- `node --check` passou em `mockup/src/data.js` e `mockup/src/screens-list.js`;
- `bash -n mockup/build.sh` passou;
- `mockup/build.sh` foi executado e regenerou `mockup/jornada.html`;
- `git diff --check` ficou limpo;
- não foram executados testes, Rails, banco, navegador, serviços ou produção.
