# Contrato visual — Relacionamentos / Issue #776

## Autorização e base

Rodrigo aprovou o plano de auditoria e autorizou implementar, revisar e testar. Na continuação, autorizou merge e deploy após implementação, revisão e testes verdes. Não autorizou alteração de flags ou dados produtivos. Base 6c89c4bc5dd3826c81a68cf72e6f7809d10eb351. Trabalho exclusivo em fix/776-relationships-visual-alignment.

## Referências reconciliadas

- Home: image-gen-5(20260929-100506).png — três cards de acesso, título/subtítulo, ícones destacados, capacidades reais e ações Abrir contatos / Abrir empresas / Configurar atributos.
- Formulário: image-gen-1(20260929-100453).png e image-gen-4(20260929-100502).png — título contextual, descrições, entidade fixa na ficha, tipo e locais permitidos com explicação.
- Mídias: image-gen-1(20260929-101551).png — miniatura + nome, informações legíveis, contato, controles organizados. Adaptar a largura real da lateral; visão ampliada para tabela.
- Atendimento: Captura de Tela 2026-09-29 às 07.16.57.png — preservar cabeçalho Contatos, informações, ações, accordions e compositor. Sem novos cards grandes ou abas no atendimento.
- Auditoria de origem: Auditoria_Frontend_Relacionamentos_Chat2You_2026-09-29.md, UI-01..UI-13 / QA-01.

## Sistema visual

Reutilizar tokens n-surface/n-background, n-slate, n-blue, n-violet e n-teal, fonte e componentes do projeto. Tailwind sem CSS global, scoped ou estilos inline novos. Branco e superfícies claras no tema claro; variantes dark dos tokens existentes. Sidebar e logotipo seguem a configuração da instalação, sem marca fixa.

Home: título 30–36px; subtítulo 16–18px; ícone do módulo 40px sobre área 80–96px; cards com cabeçalhos/ícones 48–64px, corpo 14–16px e ação sólida visível de 40–48px. Grade 3 colunas quando houver espaço, 1 em mobile, alinhamento consistente e sem altura vazia artificial. Capacidades e apoio contextual apenas reais.

Formulário: Dialog existente, largura lg/xl, hierarquia clara, rótulos visíveis, aviso global, Switch existente para locais, footer com Cancelar e confirmação contextual; manter submit nativo, foco, rascunho, conflito e validação. Entidade não pode mudar indevidamente.

Fichas: seção com título/descrição e ações, grade de duas colunas quando couber e uma estreita; célula com ícone por tipo, nome/descrição/valor e ações discretas. Sem regex para identificar nome ou tipo. Valor zero/falso não é vazio. Variante compacta permanece dentro do accordion.

Mídias: busca em primeira linha; controles avançados recolhíveis na lateral, contato pesquisável sem campo+botão+seletor redundantes. Tamanho em KB/MB, tipo amigável, datas pelo contexto autorizado. Agrupamento visível por contato, paginação do servidor, caminhos de origem intactos. Estados separados: carregando, vazio, filtro sem resultado, falha e preview indisponível. Nenhum retry para indisponibilidade permanente (#771).

## Exceções deliberadas

Não copiar métricas/números fictícios, Negócios/Tarefas, recentes/submenus descartados, menu duplicado, upload direto, etiquetas de empresa inexistentes, carrossel automático, waveform artificial, opção de Empresa na lateral não suportada, promessas novas de IA. Os valores ilustrados não viram seeds produtivos.

## Proteção funcional

Sem mudança de API, banco, autorização, expiração, geração de previews, chaves, concorrência, integrações, SSO, IA, campanhas, infra ou dependências. Manter feature flags existentes e URLs. Mudanças em componentes-base opcionais/localizadas.

## Idioma

A extensão em pt_BR usa somente o catálogo próprio de Relacionamentos já existente. Preservar o comportamento do fork entregue em #760/#771; não tocar tradução comunitária nem resolver a governança separada #772. Catálogo en acompanha as mesmas chaves.

## Gate visual separado

Navegador real isolado com dados fictícios, 1630×930, 1024×930, 390×844 e claro/escuro. Conferir referência e captura: composição, escala, paleta, espaçamento, ícones, botões, textos, foco, tabs, scroll e estados. Não contar screenshot salva como aprovação. Baselines de navegador são candidatas até o aceite de Rodrigo; nenhuma atualização automática para ocultar regressão. Comparar Antes → Referência → Implementado.

## Gate técnico

Testes unitários/componentes, fluxos reais de criar/salvar/recarregar/selecionar valores, permissões e contexto. Preservar todos os cenários existentes; atualizar apenas seletores de controles aprovados. AST sem regex, lint, build, Guia/Central e CI. Falhas/limites explícitos. Merge e deploy exigem o candidato revisado, evidências de navegador e CI verdes; confirmar o SHA publicado, saúde e rollback das duas stacks.
