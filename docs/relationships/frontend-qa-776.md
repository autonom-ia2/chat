# Frontend de Relacionamentos — Issue #776

## Entrega e autorização

Correção visual isolada, base `6c89c4bc5dd3826c81a68cf72e6f7809d10eb351`.
Branch `fix/776-relationships-visual-alignment`. Rodrigo autorizou implementar,
testar, revisar e preparar a PR na retomada. Não houve merge, auto-merge, deploy, ativação de
flags nem escrita produtiva nesta etapa. Backend, APIs, modelos, banco produtivo,
SSO, credenciais, infraestrutura e conversor de previews não fazem parte do diff.

## Referência e diferenças deliberadas

O [contrato visual](visual-contract.md) identifica as imagens de origem e as
exceções. A home escolhida é a de três cards, não o dashboard anterior com métricas,
recentes e submenus. O atendimento conserva seus accordions reais. Os controles
são implementados com componentes e tokens do produto, não com uma nova biblioteca.
A marca continua configurável por instalação e o modo escuro conserva seu tema.

Não se copia para o produto: métricas ou dados demonstrativos, upload de Empresa,
etiquetas corporativas inexistentes, carrossel automático, waveform artificial ou
promessas novas de classificação por IA. A chave técnica permanece estável e não é
um campo obrigatório do novo formulário.

## Mudanças por superfície

| Superfície       | Implementação                                                                                                        | Proteção funcional                                                                               |
| ---------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Home             | Cabeçalho, subtítulo, ícones com fundos cromáticos, três cards de capacidades e ações explícitas; apoio contextual.  | Permissões/flags do destino preservadas; capacidades indisponíveis não são anunciadas.           |
| Navegação        | Breadcrumbs com hierarquia e registro atual, sem marcador de lista; eliminação do recuo excessivo nas fichas opt-in. | URLs/names e links legados intactos; layout anterior é default quando a extensão está desligada. |
| Central          | Uma ação de criar e uma ação de configurar, sem duplicação acima do título.                                          | Modelos de Conversa/Contato/Empresa e autorização mantidos.                                      |
| Editor           | Criar/editar/configurar com títulos e confirmações distintos, entidade fixa, explicações e switches de exibição.     | Salvamento transacional, revisão, rascunho em falha, chave e valores inalterados.                |
| Fichas           | Campos em grade responsiva, nome/valor/descrição, ícone de tipo e ações discretas.                                   | Zero e falso não são vazio; gravação continua por campo, separada do cadastro nativo.            |
| Atendimento      | Controles pequenos dentro do conteúdo do accordion existente.                                                        | Mensagens, compositor, Resolver e ordem das seções preservados.                                  |
| Mídias compactas | Busca principal, filtros recolhíveis, contato pesquisável, miniatura/nome e ações contextuais.                       | Autorizações, consulta no servidor, origens e preview limitado mantidos.                         |
| Mídias ampliadas | Empresa identificada, tabela do produto, tipo e tamanho legíveis, grupos de contato e paginação claros.              | Sem deduplicar por nome, reordenar páginas no cliente ou expor dados de outra conta.             |

## Revisão independente

Primeira revisão read-only identificou dois P2 e um P3: popovers transportados para
body poderiam fechar a lateral mobile; capacidades eram anunciadas com flags
desligadas; marcador de lista indevido no breadcrumb. As três correções foram
aplicadas e recebem testes. A revisão não equivale a aceite visual de Rodrigo.

A retomada incluiu nova revisão independente, somente leitura, do diff completo e
dos arquivos novos. Encontrou um P2: após falha em visualizar/baixar mídia, mudar de
página mantinha o alerta e o retry do arquivo anterior. A carga da lista agora limpa
esse estado e invalida ações pendentes. Dois testes reproduziram o erro antes da
correção e passaram depois, cobrindo falha já exibida e rejeição tardia.

A segunda leitura do delta não encontrou achados demonstráveis restantes. O revisor
não executou as suítes e não comparou os pixels com os originais; essas evidências
são separadas. A revisão técnica não substitui a aprovação visual do Rodrigo.

## Ambiente reproduzido

Worktree exclusivo `chat2you-776-frontend`, Rails em `127.0.0.1:34776`, Vite em
`127.0.0.1:35776`. PostgreSQL isolado de testes em `127.0.0.1:55757`, banco
`relationships_776_e2e`, clonado exclusivamente da fixture sintética anterior.
Redis de testes em `127.0.0.1:56757/6`. Nenhum serviço produtivo foi utilizado.

Playwright instalado pelo lock existente. Credenciais,
logs detalhados e scripts privados ficam em `.codex/visual-776/`, ignorado pelo Git.
O browser bloqueia hosts externos. A demonstração usa a conta fictícia Hub2You QA,
não clientes de produção, e o arquivo Hub2You já existente em `public/brand-assets`.
Nenhum logo foi redesenhado. Novas capturas são evidências candidatas até o aceite.

## Limites e ocorrências de preparação

- Primeiro symlink de node_modules não resolveu fake-indexeddb na nova worktree.
  Corrigido por instalação offline com lock congelado, sem mudança de dependências.
- O pg_dump padrão era 16 e não exportava o PostgreSQL de teste 17. Foi usado o
  cliente 17 instalado; o banco novo ainda estava vazio e o banco de origem ficou intacto.
- Rodada inicial de E2E concorrente com a suite completa teve timeouts na navegação
  e carregamento. Os cenários não foram removidos nem os timeouts aumentados.
- O limite real de sessões retornou 409 após várias rodadas sobre a fixture clonada.
  Foram limpas somente sessões dos dois usuários sintéticos no banco 776; nenhum
  limite ou código de autenticação foi alterado.
- Os previews usam jobs reais e o adapter de teste não executa filas automaticamente.
  O job limitado foi executado apenas para cinco anexos sintéticos, com ready e
  existência de origem conferidos. Nenhum placeholder conta como miniatura aprovada.
- Um Chromium da captura extensa encerrou a página (Target crashed). A evidência
  dessa tentativa não é considerada aprovada; repetir em processos curtos sem suites pesadas concorrentes.
- Na retomada, a primeira rodada completa do E2E passou 17 casos e falhou em dois
  antes da navegação: faltava `RELATIONSHIPS_TEST_ACCOUNT_ID` no ambiente. Os quatro
  valores necessários ao teste de login são carregados da fixture sintética no
  processo privado de execução, sem imprimir credenciais ou alterar autenticação.
- O locator inicial do contrato selecionava dois elementos `main` aninhados. O
  teste agora identifica o painel interno e verifica que existe exatamente um,
  mantendo as verificações de cards, alvos de toque e ausência de overflow.

## Fuso dos arquivos

Datas exibidas usam o fuso local do navegador e informam isso. Os filtros de dias
continuam sendo interpretados no reporting_timezone do servidor, UTC quando ausente.
O contrato atual não expõe esse fuso no endpoint; não foi inferido nem criada uma API
nova só para apresentação. A interface e os testes distinguem essas duas regras.

## Gates para entrega

| Gate                  | Resultado da retomada                                                 | Evidência privada                 |
| --------------------- | --------------------------------------------------------------------- | --------------------------------- |
| FieldEditor           | 9 testes aprovados, zero falhas                                       | `field-editor-final.log`          |
| Regressão direcionada | 13 arquivos / 112 testes aprovados                                    | `relationships-review-final.log`  |
| Frontend completo     | 614 arquivos / 6.826 testes aprovados; zero falhas, pendentes ou todo | `full-frontend-review-final.json` |
| Snapshots existentes  | 11 aprovados; nenhum atualizado                                       | `full-frontend-review-final.json` |
| Contrato visual       | 5 aprovados, incluindo 390/1024/1630 e popovers reais                 | `e2e-review-final.log`            |
| E2E completo          | 19 testes aprovados; zero falhas                                      | `e2e-review-final.log`            |
| AST                   | Nenhuma regex nova; 182 arquivos cumulativos analisados               | `ast-review-final.log`            |
| ESLint                | 28 arquivos; zero erros / 214 avisos                                  | `lint-review-final.json`          |
| ESLint Playwright     | Zero erros / 14 avisos                                                | `playwright-lint-final-2.log`     |
| Prettier              | Todos os arquivos alterados conferidos                                | `format-review-final.log`         |
| Guia                  | 169 fluxos / 170 telas; nenhuma sem explicação                        | `guia-final.log`                  |
| Central               | 174 artigos / 170 telas; avisos de referências históricas             | `central-final.log`               |
| Build Vite            | Aprovado; 6.025 módulos, 36,47 s, avisos de tamanho de chunks         | `build-review-final.log`          |
| Revisão independente  | P2 corrigido; sem achados demonstráveis restantes                     | Trilha de auditoria               |

Os logs ficam em `.codex/visual-776/`, ignorados pelo Git. As capturas finais
recebem um manifesto com o SHA exato de `HEAD`, viewport, tema e erros de navegador.
O código/testes conferidos e o candidato da PR devem corresponder; documentação
não altera os resultados dos testes. CI remoto e runtime Linux são gates separados,
exigidos antes de qualquer aprovação para merge.

Os mockups originais citados no contrato não foram encontrados nas pastas consultadas
durante a retomada. A composição foi conferida contra o contrato escrito; isso não
certifica igualdade visual com os arquivos originais. As capturas finais devem ser
comparadas com eles e aprovadas pelo Rodrigo. Não considerar esse gate concluído
apenas porque os testes de geometria estão verdes.

## Rollback e próximo gate

Sem migration, backfill ou alteração de contrato. Antes de uma publicação futura,
obter aprovação do SHA e das stacks autorizadas: o merge de aplicação em `main`
pode disparar os dois workflows blue/green. Preparar o alvo anterior de cada stack
conforme [rollout-rollback.md](rollout-rollback.md). O rollback funcional autorizado
desliga as extensões preservando definições, valores e originais; o rollback do
binário usa o alvo anterior verificado. Nenhuma operação de rollback foi executada.

Project Autonom.ia Dev: Projeto Hub2You, Tipo Bug, Prioridade P2, Risco Médio,
Ambiente Local. O status e a próxima ação devem refletir a PR e o gate real.

Aprovação final visual e merge/deploy: **pendentes de Rodrigo**.
