# Publicação e rollback — Relacionamentos #757 / PR #760

## Autorização

A implementação foi autorizada; **merge/deploy e alteração de conta real exigem nova
aprovação explícita de Rodrigo**. A PR #760 é o ponto de revisão. O fluxo permanece:
Issue → Branch → PR → Project → Review → Approval → Merge → Deploy/rollback.
Os documentos históricos de agentes não substituem o estado atual da PR e de seus checks.

## Alcance do merge

Os workflows `deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml` disparam
em mudanças de aplicação na main. **Um merge desta feature pode publicar as duas stacks.**
As flags de uma conta controlam a experiência; não impedem um deploy na outra stack.

Antes de qualquer merge, confirmar SHA, janela, contas piloto e stacks autorizadas:

- Com ambas autorizadas, seguir os blue/green existentes e validar cada stack.
- Com somente uma autorizada, preparar uma mudança separada, revisada e aprovada do
  mecanismo de publicação que impeça o outro gatilho antes de mergear aplicação.
- Não tentar controlar escopo cancelando um deploy que já iniciou.

O workflow novo `relationships.yml` faz somente CI em runner descartável. Não publica
imagem, não usa AWS/secrets de produção e não executa rollout.

## Gates antes da aprovação

Concluir a matriz de `qa-acceptance.md`, verificar o SHA testado, resolver P0/P1/P2,
conferir checks de CI e smoke da imagem Linux. Rever evidências desktop/mobile e dados
fictícios. Não usar dados reais para testes de criação ou mutação.

O smoke Linux verifica a mesma imagem final do Dockerfile, incluindo vips/poppler/ffmpeg,
sem rede e com filesystem somente leitura, memória/CPU/tempo/saída limitados.
No macOS, os testes nativos não certificam o limite de memória Linux.

## Habilitação

`relationships_navigation`, `relationships_attributes` e `relationships_company_media`
começam desligadas. Habilitar somente após aprovação, pelo mecanismo operacional de
feature flags existente e para a conta explicitamente autorizada. Companies e
custom_attributes continuam com seus gates próprios.

1. Validar a experiência antiga com flags desligadas.
2. Após o blue/green saudável, habilitar a conta piloto aprovada.
3. Validar criar/editar atributo, preencher e recarregar, apresentação no accordion,
   navegação e mídias autorizadas, sem acionar mensageria/IA desnecessariamente.
4. Ampliar somente após aceite; não consumir a geração anterior de rollback com
   múltiplos deploys antes da validação da versão atual.

## Rollback funcional

Desligar as três extensões independentemente, com autorização de operação. Isso
restaura os acessos e a apresentação legada. Valores, definições, configuração e
arquivos originais permanecem no banco/storage. Não existe migration nova nem backfill
em massa. Reverter código não desfaz dados que tenham sido legitimamente preenchidos.
Jobs já iniciados são limitados e os novos pedidos respeitam as flags; observar fila low.

## Rollback do binário

Usar a operação `rollback` do blue/green existente da stack autorizada. Conferir tráfego,
SSO, web, worker e filas. A política existente preserva somente a geração imediatamente
anterior; confirmar a disponibilidade dela antes do deploy e não limpar esse alvo antes
do aceite. Nunca remover dados para reverter uma apresentação.

## Critérios de interrupção

Perda/sobrescrita indevida, vazamento de acesso, falha de salvamento, regressão de
atendimento, conversão fora dos limites ou indisponibilidade do alvo impedem liberação.
Falha administrativa de Project não autoriza ignorar revisão nem gates técnicos.

## Project atualizado

Board: Autonom.ia Dev — https://github.com/users/autonom-ia/projects/3
O conector dedicado retornou404, mas o acesso existente pelo GitHub CLI funcionou.
A Issue #757 e a PR #760 foram adicionadas ao board e receberam os sete campos abaixo.
Uma leitura posterior confirmou os valores dos dois itens; não há atualização manual
pendente. Nenhuma permissão ou credencial foi alterada para obter esse acesso.

Projeto: Hub2You
Status: Em review
Tipo: Feature
Prioridade: P2
Risco: Médio
Próxima ação: Conferir os checks da PR #760 e obter aprovação do SHA, stacks e conta piloto antes de merge/deploy.
Ambiente: Local

## Complemento operacional antes da publicação aprovada

A main foi atualizada pela release #761 (GPT-6 Sol/Luna e IA interativa assíncrona),
seguida da auditoria #763. Relacionamentos preserva essa atualização; o rollback
imediato desta publicação aponta para a imagem14a8d040d3087044071935d11c0b655bacc8ec3c,
não para a imagem anterior ao GPT-6. Conferir o ponteiro real novamente ao trocar tráfego.

Antes de rollback de binário, desligar as três extensões e concluir/remover somente
os jobs Relationships::CompanyPreviewJob pendentes, reagendados ou em retry. A imagem
anterior não conhece essa classe. Não esvaziar filas inteiras nem interromper mensagens
ou InteractiveJobs de IA. Derivados podem ser regenerados; não apagar originais.

A habilitação e verificação nas duas stacks usa uma operação manual revisada, com
concorrência compartilhada com cada blue/green, SHA exato em web/worker, transação de
QA revertida e habilitação somente nas contas ativas elegíveis. Nenhuma alteração de
Companies/custom_attributes/CRM, licença, credenciais ou padrões de contas futuras.


## Estado de produção após o merge #768

O PR #768 foi mesclado em `main` no SHA
`585712e44ae2f083a86f2ede4bc8608cf954e199`.

- Hub2You concluiu o blue/green nesse SHA e preservou a geração anterior como rollback.
- Autonom.ia não trocou tráfego: o build foi interrompido antes de criar o green por
  HTTP 429 (`Data limit exceeded`) ao resolver as imagens-base no `public.ecr.aws`.
  Repetir o job sem mudança de condição reproduziu o mesmo bloqueio.
- As três flags de Relacionamentos continuam desligadas enquanto a Issue #770 / PR #771
  fecha os dois findings funcionais pós-merge.
- O finding de i18n do #768 foi reclassificado como inconsistência de governança do fork:
  o histórico comprova módulos próprios com pt_BR mantido localmente (por exemplo #660),
  apesar da regra genérica do AGENTS.md. Remover o catálogo agora degradaria a interface.
  A política futura fica na Issue #772, sem mascarar o conflito nem bloquear este hotfix.
- Antes de habilitar, exigir: #771 verde, revisão do delta, Autonom.ia no mesmo SHA de
  aplicação e novo preflight/verify das duas stacks.
