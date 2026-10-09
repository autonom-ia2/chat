# R1 — correções de acessibilidade da captura real

## Escopo

Este registro cobre apenas as correções confirmadas pela primeira captura real do
F0/F1, dentro da rodada R1. Não inclui uma nova revisão visual nem validação de
produção.

## Evidência e correções

- `app/views/layouts/vueapp.html.erb:2` agora declara `lang` a partir de
  `I18n.locale`, preservando o formato de locale usado pelo HTML.
- `app/views/layouts/vueapp.html.erb:7` remove `user-scalable=0` do viewport.
  A captura tinha identificado a restrição de zoom como falha de acessibilidade.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:176-181`
  mantém o gate mestre, o gate da conta e a permissão, e acrescenta a flag da
  conta para separar o menu novo do legado. Com a flag de redesign ligada, o
  item único aponta para o índice e cobre índice, builder, build, ready e os
  dois painéis em `activeOn`, sem `children`. Com a flag desligada, o grupo
  legado continua com seus dois filhos.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:1469` usa
  `text-n-slate-11` no texto da busca. O ícone e o atalho oculto não foram
  alterados.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:1492` dá nome
  acessível ao botão de nova conversa com chave já existente em inglês e
  português.
- `app/javascript/dashboard/components-next/avatar/Avatar.vue:232` nomeia o
  avatar textual com o nome da pessoa e fallback traduzido. As duas combinações
  claras reprovadas pela captura foram ajustadas reutilizando cores já presentes
  na paleta do componente: `#4747C2` sobre `#FBDCEF` (5,63:1) e `#60646C`
  sobre `#CCF3EA` (4,97:1). Nenhuma cor nova, CSS ou estilo inline foi criado.
- `app/javascript/dashboard/components/Snackbar.vue:32` usa branco no snackbar
  claro e `n-blue-12` no snackbar escuro, inclusive no estado hover, evitando o
  link azul de baixo contraste identificado na captura.

O coordenador alinhou também `localeLoader.js`: depois de confirmar a última
escolha de idioma, atualiza `document.documentElement.lang` pelo helper D9
`toLocaleTag`. A conta pode carregar pt_BR após o HTML inicial em inglês; o
atributo acompanha o catálogo efetivamente exibido. As specs existentes agora
conferem pt-BR/es e o idioma final na corrida entre catálogos, sem alterar as
asserções anteriores.

## Checagens deste bloco

- Prettier nos três componentes Vue alterados: aprovado.
- ESLint nos três componentes Vue: 0 erros; os avisos são os avisos já
  existentes do catálogo dinâmico de i18n (93 no arquivo completo, incluindo
  chaves que o plugin não indexa).
- `git diff --check`: aprovado.
- Contraste das duas combinações de avatar calculado: aprovado acima de 4,5:1.
- Não foram executados testes pesados, build, banco, navegador ou produção
  neste bloco. A captura Axe referenciada é a execução real anterior, não uma
  nova alegação de validação.
