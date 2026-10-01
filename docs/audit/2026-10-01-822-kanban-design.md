# Issue #822 — análise e protótipo do Kanban

## Escopo autorizado

Rodrigo pediu análise profunda e mockups navegáveis para aprovação, com UX/UI,
direção de arte e QA trabalhando em paralelo. Esta branch contém somente
documentação/protótipo; não modifica o aplicativo, contratos de API ou banco.
Não houve acesso à conta 18, produção, credentials externas ou chamadas de IA
pagas. Dados e nomes usados no protótipo são fictícios.

## Isolamento

- Issue #822; branch `codex/kanban-design-review` em worktree próprio de main
  `bd2104837da812a91587189b33b2f23daabc6583`.
- A análise de integração considera a PR #793 em `56b56f3a79` e a referência
  Editar Funil já integrada. A correção de concorrência segue na PR #793, sem
  transportar mudanças de produto para esta proposta.
- Navegador isolado do Codex; Chrome pessoal e tabs existentes do usuário não
  foram usados para a conferência.

## Método e decisões

Três agentes existentes foram reutilizados conforme pedido explícito: UX/UI,
direção de arte e QA. O root integra as conclusões, pesquisa fontes primárias e
verifica a renderização e interações em navegador real. Os relatórios distinguem
observações em código, evidências locais e propostas ainda não implementadas.

UI-UX Pro Max aplicada. Duas consultas `--design-system` retornaram padrões de
marketing fora de escopo; não adotamos hero, vídeos, novas fontes ou paletas.
Consulta `--domain ux` sobre dragging movements retornou orientação relevante.
Referências NN/g, W3C/WCAG e Atlassian verificadas com pesquisa web; links e
aplicações registrados no README da proposta.

A revisão inicial de arte rejeitou o topo alto e o KPI sem contrato. O protótipo
deve privilegiar o quadro e conservar funções existentes com acesso claro.

## Achados factuais relevantes

Empresa canônica não é serializada no board; PR #793 melhora o drawer, sem
resolver esse contrato do Kanban. Busca atual é por título. Ordenação client-side
por atenção cobre somente dados paginados por ID. Score sem proveniência no
board não pode ser rotulado como IA. Movimento manual existe na Lista, mas
falta acesso direto equivalente no próprio Kanban.

Esses achados orientam a proposta e seu plano de implementação. Não foram
corrigidos nesta branch de documentação e não devem ser declarados prontos.

## Liberação

Aprovação visual é separada da implementação e do release. Esta entrega não
autoriza merge/deploy. Rollback de uma futura implementação deve ser definido
na PR de código correspondente; esta proposta não tem migration ou transformação
de dados a reverter.

## Validação final

Resultados e matriz de casos em `docs/crm/kanban-design-822/validation.md`.
Node syntax check e build Tailwind aprovados. Aviso Browserslist antigo não
impediu compilação; nenhuma dependência foi instalada/atualizada. Não houve
autofix de fonte. Capturas por CDP do navegador isolado nas medidas declaradas.

Rodrigo pediu posteriormente filtro específico de empresa, simplicidade dos
filtros e proposta de GPT-6 Luna. Acrescentamos a interface de filtros combinados,
chips removíveis e IA opcional com confirmação. A primeira abertura é vazia; a
prévia usa somente cenários fictícios por ID, sem interpretar texto livre por
regex/keywords e sem fingir chamada de provider. Orçamento autorizado US$ 1;
gasto US$ 0. Cost-Aware LLM Pipeline aplicada para avaliar escopo e custo, sem
downgrade automático, novo retry ou algoritmo de interpretação.

No celular, a primeira tentativa inline consumiu todo o espaço do board: rejeitada.
O filtro foi movido para dialog próprio. Teste final comprovou filtros combinados,
1 resultado visível em Proposta, fechamento/restauração do fieldset e 333px
de quadro após confirmar a prévia IA. Arte aprovou as capturas revisadas.

A documentação registra contratos propostos e gates. Fontes do protótipo não
são código de produto a copiar diretamente. Produto, banco e APIs não mudaram.

## Empacotamento da proposta

A tentativa normal de commit encontrou `.husky/_/husky.sh` ausente nesta worktree
sem instalação de dependências. Não alteramos hooks compartilhados nem
instalamos pacotes. Para esta branch somente de documentos/protótipo, o commit
usa `core.hooksPath=/dev/null` apenas naquele comando, após leitura de fontes,
checks de sintaxe, diff e validação renderizada. A checagem Node foi repetida
com o executável absoluto do runtime existente após PATH sem Node.

## Revisão de feedback sobre descoberta e filtro

Rodrigo relatou dificuldade para achar criação de funil e pediu IA ao lado
dos filtros. A criação foi exposta junto ao seletor, e o painel passou a faixa
compacta. Ver validação/capturas 13/14. Ajustes incluem foco inicial da criação,
textarea/summary no ciclo do modal, rótulo acessível da ação Nova e caminho da
ajuda de status para Editar funil. Discussão da hierarquia empresa/pessoa/negócio
registrada como próxima decisão, sem mudar dados nem os títulos dos cards.

O pre-push também encontrou o mesmo Husky ausente. Hooks foram ignorados apenas
nos comandos desta proposta documental; configuração compartilhada preservada.
Não houve merge, deploy, produto, provider pago ou acesso a dados reais.

## Revisão de filtros e investigação do Guia — 01/10

Rodrigo solicitou manter etiquetas e score com simplicidade, remover duplicidade
da busca de empresa e avaliar reutilização do Guia. Protótipo reorganizado em
busca por nome + Mais filtros + Encontrar com IA; categorias recolhidas e chips.
Nenhuma edição de produto, provedor, conta, banco ou deploy.

Validação: node --check aprovado; Tailwind build aprovado (aviso Browserslist
desatualizado, sem atualização); navegador isolado 1440×900 e 390×844. VIP=6,
VIP+atenção>=84=2, com Alvorada=1; responsável Camila=4; campanhas OU=6; remover
campanhas=11; Urgente=1 sem score; IA fictícia Norte+Minha carteira=2. Escape
restaura foco e aria-expanded. US$0 de chamadas, teto autorizado US$1 preservado.

Pesquisa primária: Carbon Filtering (atualização 11/08/2026) e NN/g User Intent
Affects Filter Design. A instantaneidade do mockup não prova desempenho no
backend. A integração do Guia exige conferir ferramentas executáveis, pois a
instrução escrita pode não representar todas as capacidades já implementadas.

Auditoria independente do Guia concluída em main remoto
902f0059d76da8b1c74c47f57c8e66edc6d55bca. Corrigida a conclusão inicial obtida
do checkout antigo: o Guia possui leitura runtime de conversas/funis/cards.
Empresa → contatos → cards ainda não é filtro CRM canônico. Recomendado
reaproveitar o leitor/autorização do Guia com resolvedor tipado compartilhado,
sem agente adicional persistente. Relatório copiado para reports/guide-crm-audit.md.
Só código/versionamento foi consultado; nenhuma afirmação de deploy/produção.

## Revisão de identidade e Prospecção

Rodrigo autorizou leitura das abas Chrome existentes, conta 20 em Autonom.ia.
Conferidos CRM contas 16/20 e Prospecção conta 16, sem gravações, conversões, buscas
novas ou chamadas pagas. UI observada usa títulos mistos e empresa primária na Prospecção.
O QA auditou main 902f0059d7 e identificou risco P1: contatos compartilhados podem
ter empresa diferente da oportunidade. Contrato recomendado revisado para empresa
resolvida por card em lote/account scope, com fonte persistida da Prospecção.

Protótipo ajustado para empresa/pessoa principal e negócio menor; sem duplicatas
exatas de nomes, sem mudar títulos. Fixture Prospecção separado com quatro cards,
busca/filtro consistente com empresa do card. Node --check e Tailwind CLI passaram,
aviso Browserslist apenas. QA UI: 11 cards, Lista/Calendário, filtro Norte=2 e busca
Alvorada=1 no cenário de 4, Escape/foco e mobile sem overflow. Capturas 19/20/21.
Mudanças restritas a docs/protótipo. Orçamento US$1, gasto US$0. Sem merge/deploy.
