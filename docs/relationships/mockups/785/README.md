# Proposta visual — Relacionamentos — #785

Proposta visual aprovada por Rodrigo, que autorizou a implementação em 30/09/2026. As listas foram revistas após o feedback sobre os blocos retos. A implementação e suas validações estão registradas em [auditoria](../../../audit/2026-09-30-implementacao-relacionamentos-785.md). Não é implementação da aplicação. Os dados são fictícios; nenhuma API da conta, destinatário, mensagem ou credencial é consultada. A marca do exemplo acompanha as capturas; a implementação deve continuar usando branding por instalação.

## Ver

Protótipo local: `http://127.0.0.1:37850/`. Alternar as quatro telas na barra superior. Nas fichas, usar **Comparar com largura atual** e as abas. Em telas menores, usar **Abrir acompanhamento** e Fechar/Escape.

A busca funciona sobre os exemplos locais. Nas fichas, abrir a aba Mídias para ver as prévias ampliadas; o menu Mais ações mantém Bloquear contato/Excluir empresa na demonstração. Botões de cadastro, atualizar, mensagem, chamada, exclusão e configuração apenas mostram que nenhuma ação real foi executada.

| Lista de contatos | Lista de empresas |
| --- | --- |
| ![Contatos](previews/contatos.png) | ![Empresas](previews/empresas.png) |

| Ficha do contato | Ficha da empresa |
| --- | --- |
| ![Contato](previews/ficha-contato.png) | ![Empresa](previews/ficha-empresa.png) |

## Recomendação

- Dashboard em faixa única arredondada, com ícones circulares e quatro indicadores úteis; manter busca, filtros e paginação. Os números não mudam de acordo com a página carregada.
- Listas com itens separados, cantos mais suaves e avatares circulares; sem a aparência de tabela reta rejeitada na primeira versão.
- Contatos: total da base, cadastros nos últimos 30 dias, atividade nos últimos 30 dias, vínculo com empresa.
- Empresas: total da base, cadastros nos últimos 30 dias, empresas com contatos, empresas sem atividade há 30 dias.
- Lateral das fichas: limite atual 28rem (448px) → proposta 37rem (592px), aproximadamente +32% no desktop. Atributos, histórico, notas, mídias e ações atuais seguem disponíveis. Abas completas e rolagem independente.
- Ações abaixo da identificação: Enviar mensagem e Chamada à vista; Bloquear contato dentro de Mais ações. Desktop em uma linha; telas menores com grade planejada, sem quebra acidental no breadcrumb. Excluir empresa também fica em Mais ações.
- Mídias da empresa: contêiner de miniatura de 96px, versus size-12 (48px) no componente atual. A borda interna deixa a imagem com 94px no mockup. Contatos e Empresas passam a usar o mesmo painel de mídias em lista, com miniaturas de 96px, pesquisa, filtros, nome/tipo/tamanho e ações Visualizar/Baixar/Abrir conversa. O mockup usa uma única função de apresentação para ambos. Os tamanhos se adaptam à lateral.
- Ao abrir: Notas no contato e Contatos na empresa. Links explícitos para mídias continuam abrindo Mídias.
- Abaixo de 1280px, usar painel de acompanhamento sobreposto para não comprimir o formulário. O protótipo demonstra esse comportamento; preservar ações e tratamento de foco do painel existente na implementação.

## Inclusão e compatibilidade

A proposta é acrescentar componentes próprios em components-next/Relationships, com um encaixe opcional para o resumo nos layouts de lista e configuração opcional da largura nos layouts das fichas. Reutilizar slots e componentes atuais de conteúdo. Para Mídias, incluir uma apresentação compartilhada e manter adaptadores de leitura/ações separados: contato mostra seus próprios arquivos; empresa reúne arquivos autorizados de seus contatos. Preservar isolamento de conta, permissões, origem, expiração e estados de preview. Não clonar telas inteiras, não injetar DOM/CSS por seletor, não alterar contratos de gravação.

É inevitável um pequeno ajuste nos pontos que recebem os novos componentes. Isolar esse ajuste reduz conflitos com upstream; não garante compatibilidade automática com toda versão futura. Revisar esses encaixes após upgrade. A reorganização visual do formulário/lista no mockup é ilustrativa: implementação deve priorizar os pedidos aprovados, reutilizando a composição atual e evitando uma reescrita de cadastro.

Tailwind, tokens e i18n do projeto; branding configurável. O catálogo local próprio segue a política vigente do fork. O protótipo usa utilitários compilados localmente e ícones Lucide já disponíveis no repositório; não requer dependência nova na aplicação.

## Dependência dos indicadores

A implementação aprovada inclui endpoints adicionais somente de leitura para todos os agregados. O resumo usa a base inteira da conta, independentemente da busca e paginação; não deriva números da primeira página. “Novos” usa created_at; “atividade” usa last_activity_at. A janela é os 30 dias anteriores ao instante da leitura. Empresas sem atividade incluem registros nunca ativos criados há mais de 30 dias, excluindo os novos nunca ativos. Os números são consultados ao abrir a lista e não representam atualização em tempo real.

## Evidência e limite

Protótipo executado no Chrome headless em larguras 1630, 1440, 1280, 1024 e 390px. Trinta capturas privadas, seis previews preservados, zero erros de JavaScript e nenhuma rolagem horizontal de página nos estados verificados. Lateral medida em 592px e comparação em 448px, aproximadamente +32%. Botões sem corte, alinhados em uma linha e contidos na área de ações no desktop 1280/1440; Mais ações aparece como botão de reticências com nome acessível no desktop. As imagens de miniatura carregadas e medidas. Abas sem corte nos estados verificados; troca de histórico, busca local e abrir/fechar/Escape do painel exercitados. Relatório em browser-report.json.

Isso comprova a proposta local; não valida integração da aplicação, responsividade em toda resolução, tema escuro, permissões ou regressão de produção. A implementação foi autorizada; merge/deploy desta nova frente continuam dependendo de revisão, validações e aprovação específica. As imagens acima continuam sendo do protótipo, não da aplicação.

## Reproduzir

Da raiz do repositório:

```sh
python3 -m http.server 37850 --bind 127.0.0.1 --directory docs/relationships/mockups/785
```

CSS já compilado e independente de rede. A prévia do documento é fictícia, renderizada a partir de assets/presentation.html; o outro exemplo usa o ícone de marca já existente no repositório, sem arquivo de cliente. Para recompilar após editar o mockup, usar tailwindcss instalado no projeto e entrada com as diretivas base/components/utilities; configuração em tailwind.config.cjs. Ícones SVG extraídos de @iconify-json/lucide; projeto Lucide, licença ISC.

## Prévia das mídias ampliadas

| Contato | Empresa |
| --- | --- |
| ![Mídias do contato](previews/midias-contato.png) | ![Mídias da empresa](previews/midias-empresa.png) |
