# CRM Kanban: identidade do cliente e filtros (#830)

## Escopo e autorização

Rodrigo autorizou implementar os cards com empresa em destaque e pessoa abaixo;
sem empresa, pessoa em destaque. O negócio continua visível como informação
secundária. Filtros manuais completos, criação de funil visível e painel compacto
seguem a proposta visual #822 / PR #827. Encontrar com IA fica desabilitado;
a integração com o Guia da Plataforma será discutida em outra PR.

A autorização cobre implementação, revisão e testes locais. Não cobre merge,
deploy ou alteração de dados de clientes. Orçamento máximo para modelos US$1;
nenhum provedor é chamado nesta implementação.

## Base e isolamento

- Issue: https://github.com/autonom-ia2/chat/issues/830
- Branch: codex/830-crm-kanban, worktree separado.
- Dependência: PR #793, ainda em rascunho, head 56b56f3a792c88be8eea278ec378184440342d4f.
- Base atual integrada: origin/main 5bee5a8d5dde48bdb651c629be7f4c6817fae03c.
- Merge local fa84c45dd1 integra a dependência com main. Não houve merge no GitHub.
- Único conflito: mapa gerado do Guia; resolvido executando o gerador, sem edição manual.
- `node scripts/guide-map/check.mjs`: 174 fluxos, 171 rotas, 0 rotas sem explicação.
- Banco local novo, dados integralmente fictícios; Rails 3830, Vite 35830, Redis 6830.
- Dependências locais existentes reutilizadas; setup temporário em `.codex/830`, ignorado pelo Git.

## Riscos examinados

A Prospecção pode enviar empresas diferentes ao CRM usando um contato compartilhado.
Nesses casos a empresa do contato não pode substituir a empresa persistida na origem
do card. O payload e o filtro devem resolver a empresa por card e limitar a leitura
à conta autorizada. A montagem deve evitar consulta por card.

Revisão cruzada: backend e contratos, frontend e filtros, identidade e direção de arte.
## Resultado local e decisão de parada

Rodrigo pediu atualizar os registros e parar em 01/10/2026. O trabalho fica em
rascunho para revisão, sem autorização de merge ou deploy. Não iniciar novos
testes, alterações ou integração com o Guia até a retomada.

Implementado:

- Empresa, pessoa e negócio com a mesma hierarquia no Kanban, Lista e cabeçalho
  do card. Empresas da Prospecção são resolvidas por card e por conta.
- Busca única, Mais filtros com empresa/sem empresa e faixa de atenção 0–100,
  etiquetas e critérios existentes. Parâmetros inválidos retornam 422.
- Criar funil visível; Encontrar com IA cinza e desabilitado. Sem faixa de atalhos
  Minhas oportunidades/Sem responsável/Retornos atrasados, conforme correção explícita.
- Cinco abas mais compactas: Resumo, Relacionamento, Conversas, Retornos, Histórico.
  Retornos ativos primeiro, formulário e configurações automáticas recolhidos.
- Status de conversa em português, estado do negócio visível em leitura,
  histórico com tentativas e próxima tentativa sem erro bruto de provedor.
- Atualização da vista ativa após editar contato/empresa: outros cards ligados
  ao mesmo contato são recarregados. Confirmado no navegador com fixture.
- Conversa primária de cards legados sem join devolvida no contrato completo,
  com inbox e atividade, preservando a filtragem de permissão do agente.
- Exportação usa a empresa efetiva do negócio, inclusive contato compartilhado.
- Busca ocupa uma linha própria em celular; nenhuma seleção nova usa select nativo.

## Validação concluída

- Vitest, oito arquivos focados: **117 testes passando**, zero falhas.
  Drawer, card, relacionamento, follow-up automático, funil, identidade da Lista
  e store. Log local ignorado: `.codex/830/root-final-vitest.log`.
- RSpec conjunto: **102 exemplos, 0 falhas, 2 pendentes**. Pendências são
  quarentenas legadas em follow_ups_spec.rb:27 e :233, anteriores à alteração.
- Enterprise export: **5 exemplos, 0 falhas**.
- RuboCop dos arquivos alterados e ESLint quiet dos componentes alterados: sem
  erros. Uma linha longa preexistente de payload_builder_spec.rb:64 foi identificada
  na execução ampla e não foi modificada. Avisos de catálogo i18n, Browserslist e
  sourcemap de dependência não impediram os testes.
- Guia gerado em dia: 174 fluxos, 171 telas, zero telas sem explicação.
- `git diff --check` passou. Não houve autofix sem revisão.
- O primeiro commit falhou porque o setup local não contém `.husky/_/husky.sh`.
  O hook também executa autofix dentro do commit, incompatível com a regra de
  revisão prévia. Os checks acima foram executados separadamente; o snapshot
  usa hooksPath temporário só nesse comando, sem alterar a configuração do repo.
- Navegador real, fixtures locais: cinco abas, B2B/B2C/card sem contato,
  empresa distinta da Prospecção, edição e restauração de contato compartilhado,
  filtro por empresa com seleção mantida após pesquisar outra, score 90–20
  bloqueado e 70–90 aplicado, busca por negócio, Lista e zero selects nativos.
- Arraste entre status persistiu após recarregar; restauração pelo botão Mover
  confirmada. Rolagem horizontal alcançou Fechamento e Perdido. Em 390px,
  document/body ficaram com 390px, sem overflow externo.
- Direção de arte revisou capturas desktop/mobile sem bloqueio visual restante.
- **US$0** em chamadas pagas. Não houve acesso a dados de cliente nesta validação.

## Evidências e limites

Capturas do produto local, com dados fictícios, em
[galeria](../crm/kanban-830/README.md). Não são mockups nem prova de produção.
Eventos de falha/reagendamento do histórico foram semeados; não representam
envio real ou execução de IA. O ator de IA foi corrigido na fixture para o tipo
system usado pelo contrato real.

A captura de Mais filtros coincidiu com reinício local do Rails e continha aviso
transitório de conexão; foi preservada apenas no setup ignorado, fora da galeria.
O filtro foi verificado após reconexão. Falta recapturar essa tela para aprovação.
Não houve validação de carga, produção, provedor ou CI remoto desta branch.
Não foi acrescentada a rodada extra de specs do drawer solicitada no fim,
porque a orientação de parar chegou antes da edição.

## Retomada e liberação

1. Revisar esta PR em conjunto com #793, que continua aberta em rascunho.
   O diff contra main inclui essa dependência; não tratar tudo como alteração #830.
2. Finalizar revisão independente, CI remoto e captura limpa de Mais filtros;
   revisar os casos novos do drawer em testes focados, se necessário.
3. Rodrigo aprova as telas reais e autoriza explicitamente merge/deploy.
4. Preparar o lote com #793, verificar main atual, executar checks do lote e
   somente então liberar. Esta tarefa não criou nem ativou release em produção.
5. Rollback: sem migração nesta alteração; voltar à imagem/release anterior
   conhecida se o smoke de identidade, filtros, movimento ou vínculos falhar.
   Registrar o SHA da imagem anterior no plano do lote antes de executar deploy.
