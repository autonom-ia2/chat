# #2702 G29 · a origem do card no editor: conferência visual (08/11/2026)

Os componentes reais do editor (`LivreConfira.vue` ao fundo e `LivreAlterar.vue` aberto, que usa `LivreCondicao.vue`
e `LivreCampo.vue` → `LivreMarcar.vue`), com o Tailwind, o i18n pt_BR e o catálogo gerado (`automacao-passos.json`)
desta branch, num Vite mínimo fora do painel. Funil falso "Vendas" (id 1); etiquetas falsas `vip` e `retorno`.
Captura pelo Chrome headless: 1440 px pela janela e 390 px pela emulação de celular (DevTools). Nenhuma chave de
tradução ficou faltando e a página não registrou erro.

- `filtro-*.png`: gatilho "Quando um card é criado em Vendas" com o "Só se" aberto: "De onde o card veio" · "é" ·
  "um formulário de anúncio". A frase do topo diz "De onde o card veio é um formulário de anúncio".
- `etiqueta-*.png`: o passo "Pôr etiqueta no contato" aberto. A frase, no topo do painel e na linha do passo no
  Confira, diz "Pôr as etiquetas vip e [Anúncio do formulário] no contato". Em "Pôr as etiquetas", `vip` marcada e o dado posto como chip
  "[Anúncio do formulário]"; embaixo, o seletor "Pôr uma etiqueta com o nome de um dado". Em "Tirar as etiquetas",
  `vip` aparece bloqueada porque já está em "Pôr" (comportamento antigo).
