# Validação renderizada da proposta

Todos os resultados abaixo são do protótipo com dados fictícios em memória.
Não provam integração, persistência, acurácia IA, produção ou deploy.

## Ambiente e checks

- Worktree da Issue #822, base `bd2104837da812a91587189b33b2f23daabc6583`.
- Python HTTP local somente loopback, servindo a pasta do protótipo.
- Navegador isolado Codex; nenhuma automação do Chrome pessoal.
- Node v24.11.0: `node --check prototype/app.js`, aprovado após as alterações.
- Tailwind compilado com a dependência existente da worktree PR #793. Apenas
  aviso da base Browserslist antiga; sem falha. Não instalamos/atualizamos pacotes.
- Console final sem erros. Zero selects nativos e nenhuma chamada externa no JS.
- Overrides de viewport usados para teste e restaurados antes da entrega.

## Resultados observados

| Verificação | Resultado |
|---|---|
| Desktop 1280×900 / 1440×900 | Página sem overflow; CTA visível; coluna começa em y=185 com controles de rolagem. |
| Desktop 1920×1080 | Cinco status inteiros; coluna começa em y=177. |
| Card padrão / sem valor ou sinal | 165px / 125px; responsável não assume identidade do contato. |
| Celular 390×844 | Sem overflow; um status por vez; gaveta cobre 390px e footer termina em y=844. |
| Empresa no detalhe | Mariana Costa e Norte Logística distintos; telefone aparece uma vez. |
| B2C | Quatro oportunidades com contato sem empresa; nenhum vínculo inventado. |
| Busca Norte | Quatro de onze oportunidades do conjunto fictício. |
| Filtro empresa Norte | Quatro de onze; empresa Alvorada retorna duas. |
| Alvorada + Minha carteira + Somente atrasados | Um card, ID 7; badge mostra três filtros, total mostra uma oportunidade de onze. |
| Remover filtros individualmente | Recorte atualizado; remover responsável/atraso mantém empresa. |
| Limpar filtros com busca Implantação | Busca preservada; uma oportunidade permanece. |
| Sem empresa vinculada | Cinco cards, incluindo o card sem contato; não implica classificação B2C. |
| Combinação sem resultado | Mensagem identifica filtros e oferece limpeza de busca/filtros. |
| Trocar para Pós-venda | Dois cards e três status próprios; filtros são limpos. |
| Criar oportunidade em memória | Total passa onze → doze; não inventa mensagem/score. |
| Título igual ao contato | Nome não se repete; telefone fica como identidade secundária. |
| Mover por teclado | Novo dois / Atendimento quatro; total onze; foco volta ao acionador. |
| Arrastar com entrada real do navegador | Card 1 passa de Novo a Atendimento, mesmo resultado do botão. |
| Desfazer | Card retorna ao status anterior e total permanece onze. |
| Mais status | Alcança Perdido integralmente, até x=1440; próximo fica desabilitado no limite. |
| Tab/Escape na gaveta | Foco permanece no modal e retorna ao título/Mover correto, inclusive na Lista. |
| Loading / vazio / erro | Estados explícitos; retry retorna quadro; não há API nessa demonstração. |
| Lista / Calendário | Compartilham recorte, status e três datas de retorno coerentes. |
| Filtros no celular | Dialog próprio conserva espaço do quadro; ao fechar, card com resultado está na etapa visível. |
| IA inicial | Campo vazio; entender/aplicar desabilitados; aviso de prévia visível. |
| IA exemplo Alvorada | Prévia mostra empresa + atrasados e um resultado; só confirmar altera filtros. |
| Editar pedido após sugestão | Prévia inválida; aplicar desabilitado; texto livre não é interpretado por heurística. |
| IA no celular | Prévia termina em y≈685; footer começa em y=767; após confirmar ambos modais fecham e board conserva 333px. |

Os casos IA são cenários de UI predefinidos por IDs. Não foram executados pelo
GPT-6 Luna. Gasto de provider: US$ 0; orçamento autorizado máximo: US$ 1 caso
uma avaliação real seja necessária em etapa posterior.

## Revisão independente

- Direção de arte: aprovação visual limitada à interface/fluxo, após capturas
  desktop e celular. Inicial vazio, transparência e copy condicional corrigidos.
- UX/UI: grupos de filtro, aplicação imediata, etiquetas removíveis, busca
  escalável da empresa e separação entre contagem/filtros recomendados.
- QA: fontes do payload, limites de busca/ordem/empresa e crítica estática.
  Correções renderizadas e fechamento constam nesta validação do integrador.

## O que falta para release

Contrato real empresa/proveniência; consulta e picker autorizados; paginação e
contagens coerentes; filtro IA tipado com esclarecimento para ambiguidades;
eval do modelo dentro do orçamento; integração dos fluxos completos do CRM;
testes de permissão/OSS/Enterprise/realtime e revisão visual do produto construído.
Mockup aprovado não equivale a autorização de merge ou deploy.

## Revisão após feedback de descoberta

- Em 1280 e 1440 pixels, empresa, atraso e IA têm top=169 e altura=44;
  faixa de filtros tem 81px, sem caixa envolvente e sem overflow da página.
- Criar funil permanece visível em 390px, altura 44; input recebe foco ao
  abrir; criação fictícia seleciona Renovações, total zero, foco volta ao CTA.
- Empresa Alvorada + Minha carteira + Atrasados continua retornando um card
  de onze e badge de três filtros.
- Celular 390×844: retorno e IA alinham em top=317 após ajuste de espaçamento,
  sem overflow. A gaveta conserva fechamento e retorno ao quadro.
- Ajuda de Novo → Editar funil abre a prévia de contexto existente.
- Navegação por Tab passou a incluir textarea e summary no controle do modal;
  criação de oportunidade tem nome acessível completo no celular.
- Build Tailwind aprovado, mesmo aviso Browserslist; Node syntax aprovado;
  console final sem erro/warn; viewport restaurada; zero chamadas pagas.
