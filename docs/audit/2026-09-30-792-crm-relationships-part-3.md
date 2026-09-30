# #792 — Parte 3: interface real de Relacionamento

**Data:** 30/09/2026. **Estado:** implementação local pronta para aprovação visual de Rodrigo. Não é conclusão de M01–M08. Sem merge, deploy ou alterações na AWS.

## Autorização e escopo

Rodrigo aprovou a parte 2 e pediu que a próxima entrega tivesse screenshots da aplicação construída, não novas imagens conceituais. Acrescentou que a lateral do card deve ter a mesma largura de **Editar funil**. Esta parte implementa o primeiro trecho visual de M01/M02 e para para aprovação.

Worktree exclusiva: `/Users/rodrigosilva/dev/worktrees/chat2you-792-crm-relacionamentos`. Branch `feat/792-crm-relacionamentos`; Issue #792; PR #793 em rascunho. Ponto inicial `18253fa42a50ac243d086f7a8e32282f93511f6d`.

## Implementação

- `CrmCardDrawer.vue` mantém o identificador interno `contact` da aba e muda seu rótulo para Relacionamento. Resumo, Conversas, Follow-ups e Timeline continuam disponíveis.
- A largura é `w-[40rem] max-w-full`, a mesma de `CrmPipelineDrawer.vue`. O drawer de funil recebeu somente um atributo de identificação para a medição; sua largura não foi alterada.
- `CrmCardRelationshipPanel.vue` busca o contato na API nativa e a empresa pelo `company_id`, não pelo texto legado. Apresenta nome, telefone, e-mail, cargo, cidade, domínio e descrição, com estados de carregamento, erro, contato ausente, empresa ausente e texto legado sem associação.
- Avatar, botões, inputs, telefone, diálogo de confirmação, ícones e tokens de cor pertencem ao design system existente. Não foi inserido HTML/iframe paralelo nem CSS particular.
- Editar contato é uma gravação independente. O rodapé fixo apresenta Cancelar e Salvar contato; a confirmação continua pertencendo ao formulário HTML, preservando sua validação. Só são enviadas chaves alteradas; `company_name` não é gravado como associação empresarial.
- Uma atualização do contato recarrega o card e suas vistas pelo mecanismo existente. O rascunho comercial e a aba ativa são preservados na atualização do mesmo card. Respostas antigas de contato/empresa e busca são descartadas pelo composable compartilhado.
- `CrmRelationshipLinkForm.vue` usa as APIs reais para buscar/vincular pessoa existente ou criar pessoa no mesmo card pela API da parte 2, mantendo a chave de idempotência em uma repetição do mesmo payload. Não recria oportunidade.
- Abrir contato/empresa usa as rotas reais, em nova aba, preservando o contexto do CRM. A empresa pode ser gerenciada na ficha existente; não foi construído outro editor empresarial neste incremento.
- O cancelamento de rascunhos do relacionamento usa o diálogo nativo. Troca de aba/fechamento passam pela confirmação, e salvamento em andamento impede nova ação concorrente nesse fluxo.
- Catálogos en/pt_BR do fork atualizados juntos. Não há novo validador por regex, nova dependência de produto, mudança de schema, credencial ou flag de produção.

## Ambiente de validação

Aplicação Rails real em `http://127.0.0.1:3792`, Vite local e PostgreSQL real **exclusivo** `chat2you_792_ui_test`. Os registros são fictícios. Autenticação normal do aplicativo com usuário de QA criado no banco sintético; não foi usado bypass de autenticação nem resposta falsa para APIs de negócio.

O navegador foi Chrome 154 via Playwright já instalado. Browser plugin ausente nesta sessão: usado o fallback Playwright para navegação, verificações e screenshots. Requisições externas do navegador foram bloqueadas. Rails estava em teste, ActiveJob/ActionMailer em adaptadores de teste, sem worker de envio. Redis exclusivo em loopback, porta 6792, DB 2; a suíte Ruby usa outro banco e DB 0. Credenciais de produção não foram usadas.

A worktree tinha `node_modules` apontando por symlink para outra frente e faltavam dependências do lockfile atual. Somente esse symlink foi removido; a worktree passou a ter instalação própria com `pnpm install --frozen-lockfile`. Não se alteraram as dependências da outra frente, o manifesto ou o lockfile.

## Resultados executados

| Verificação | Resultado |
|---|---|
| Frontend de CRM, API e store, após ajuste final do rodapé | 127 testes, 15 arquivos, todos aprovados. |
| Novos testes deste incremento | 25: 9 do painel, 10 do formulário de vínculo/criação e 6 da integração com o drawer. |
| Backend de CRM/contato/limpeza e controllers OSS/Enterprise, seed 794 | 306 exemplos: 303 aprovados, zero falhas e 3 suspensos antigos. |
| Aceitação real pelo navegador | 7 verificações concluídas com APIs e persistência reais locais. |
| Build Vite em modo de teste | Aprovado; 6.034 módulos transformados. Não é publicação nem teste de produção. |
| ESLint dos arquivos tocados | Zero erros. 244 avisos permanecem, incluindo chaves dinâmicas, catálogo histórico e formatação de templates; não foram suprimidos. |
| Guia | `pnpm guia:check` aprovado: 169 fluxos, 170 telas. |
| Traduções do fork | 8 catálogos, 15.896 mensagens; chaves e parâmetros en/pt_BR conferidos. |
| `git diff --check` | Sem erros. |

Os três testes Ruby suspensos são os mesmos já documentados nas partes 1 e 2; não contam como aprovados. A primeira bateria ampliada de frontend pegou uma expectativa incorreta do teste novo (`max-w-[100vw]`): o componente já usava o limitador nativo `max-w-full`, e a medição real comprovava 390px no celular. A expectativa foi corrigida para o contrato existente; não foi retirada a verificação de largura.

### Sete verificações reais de interação

1. Editar cargo, salvar contato e conferir a API: o card mantém ID, título, valor, etapa e responsável; o título comercial ainda não salvo continua no formulário.
2. Cancelar alteração abre o diálogo nativo; continuar mantém o rascunho, descartar mantém o último valor efetivamente salvo.
3. Abrir a ficha real do contato em outra aba conserva a oportunidade de origem.
4. Abrir a ficha real da empresa corresponde ao ID canônico.
5. Notebook 1366×768 mantém a lateral de 640px.
6. Criar contato somente com nome pela interface grava pessoa e vínculo no mesmo card, sem telefone/e-mail inventado.
7. Buscar João, selecionar e confirmar o vínculo atualiza o card pela API real.

O teste de vínculo foi ajustado para esperar o **nome no cabeçalho do cadastro confirmado**, e não o mesmo nome no resultado da busca enquanto a requisição ainda estava em andamento. A execução final verificou tanto DOM quanto persistência.

## Evidência visual e comparação com a referência

Capturas finais em `docs/relationships/screenshots/792-part3/`. São screenshots integrais do navegador, sem pintura, montagem de UI ou edição posterior dos pixels.

| Comparação | Evidência / decisão |
|---|---|
| Estrutura | Kanban nativo ao fundo, drawer lateral e as cinco abas; não se reconstruiu a navegação do produto. |
| Largura | Card e Editar funil medidos em **640px** no desktop; card 640px no notebook e **390px** no celular. |
| Identidade | Logo nativa Hub2You, tokens escuros e acentos azuis/teal existentes; sem marca redesenhada. Avatares usam as cores do componente nativo. |
| Tipografia | Nome e contato com hierarquia própria; título da negociação no subtítulo do drawer, sem a expressão gramaticalmente incorreta “Detalhes do Implantação...”. |
| Ações | Leitura separada de edição; Salvar contato permanece visível no rodapé, sem depender da rolagem do formulário. |
| Mobile | Nome e ações separados em linhas para evitar quebra no meio de “Mariana”; aba Relacionamento sem reticências; rolagem interna e rodapé preservados. |
| Escopo incremental | Atributos personalizados e mídias ainda não foram encaixados nesta nova aba. Não existem botões simulados desses recursos. |
| Diferenças intencionais | Fichas abertas em nova aba nesta etapa; edição de contato inline, com rodapé nativo, em vez do modal da demonstração; dados/contagens fictícios correspondem ao banco local, não aos números do HTML. |

As capturas do HTML aprovado e da implementação foram inspecionadas visualmente. O primeiro screenshot mobile expôs a quebra ruim do nome e o rótulo truncado; ambos foram corrigidos e recapturados. Na revisão da edição, Salvar contato estava abaixo da dobra; foi movido ao rodapé fixo e o fluxo real foi repetido.

Tamanhos: desktop 1620×928, notebook 1366×768, celular 390×844. A amostra desktop de Editar funil permite conferir a mesma borda esquerda/largura do card. O conteúdo maior que a altura da lateral rola normalmente; a captura do celular mostra o primeiro viewport, não um corte aplicado à imagem.

## Limitações e pontos que não podem ser omitidos

- A aceitação não apresentou erros de página JavaScript. Houve respostas 404 do endpoint local `/enterprise/api/v1/accounts/1/limits` no shell do aplicativo; ficaram registradas no relatório. Não se afirma rede completamente sem erros nem validação dessa capacidade de licença no ambiente local. Nenhuma API nova de negócio falhou na execução final.
- A geração de fixtures evidenciou o callback nativo `Enterprise::Concerns::Contact#associate_company_from_email`, executado após commit quando chega o primeiro e-mail e Companies está habilitado. Isso foi preservado. A escolha explícita de empresa e seus efeitos devem ser compatibilizados antes de concluir M04; “não chamar criação de empresa” não equivale a garantir ausência de associação automática nativa.
- Para demonstrar texto legado **sem** vínculo, somente o registro sintético foi colocado nesse estado. Não se desfizeram vínculos de clientes reais.
- A busca da interface é por nome, e-mail ou telefone, como a API atual. Busca por empresa/paginação aprimorada, edição empresarial inline, atributos, mídias e Nova oportunidade completa permanecem nas partes futuras.
- Chrome foi exercitado; Safari/Firefox e os ambientes AWS não foram validados nesta parte. Tema escuro é a referência capturada; tema claro não recebeu homologação visual específica.
- A revisão é releitura do diff e validação automatizada/visual desta entrega, não revisão independente por outro profissional/agente. Revisão independente do conjunto segue pendente antes do pedido final de merge.

## Checkpoint

Parar após apresentar as capturas. Próxima parte proposta: atributos personalizados e mídias no painel, reutilizando as capacidades existentes, após aprovação visual de Rodrigo. O formulário completo de Nova oportunidade ainda terá sua etapa própria.

Nenhum merge/deploy foi autorizado por esta aprovação incremental. A PR permanece em rascunho. As rotinas de publicação podem afetar duas stacks; não fazer merge parcial para demonstrar o resultado. O status do CI remoto deve ser conferido no commit atual, sem reaproveitar o resultado do commit da parte 2.
