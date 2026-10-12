# Catálogo do idioma que falha: a página recarrega uma vez

Origem: QA visual de Modelos WhatsApp (#1380, achado M3). Uma tela inteira apareceu
em inglês, de forma intermitente. Separado do PR de Modelos porque vale para o
painel inteiro.

## Causa

O catálogo de cada idioma (`app/javascript/dashboard/i18n/locale/<idioma>/index.js`)
é um download à parte, feito por `import()`. Quando ele falha (rede, deploy
trocando os arquivos), o idioma fica em inglês. Tentar `import()` de novo na mesma
página não resolve: o navegador guarda a falha do módulo para a página inteira.

## Prova no navegador (Chrome, Playwright, 12/10/2026)

Roteiro: `idioma-e.cjs`. O 1º pedido de `.../i18n/locale/pt_BR/index.js` responde
500 e os seguintes passam.

| Versão | Pedidos do catálogo | Título da tela |
|---|---|---|
| Nova tentativa de `import()` na mesma página | 1 | "Message templates" (inglês) |
| Recarregar a página uma vez (esta branch) | 2 | "Modelos de mensagem" |

Resultado da versão desta branch: `m3-resultado.json`, prints `m3-a-com-cache.png`
(a aba já tinha carregado o catálogo antes) e `m3-b-sem-cache.png` (aba nova).
A interceptação do Playwright desliga o cache HTTP do navegador; o cache que causava
o problema (o da falha guardada pela página) é o que foi provado.

## Comportamento

- Falhou o catálogo: a página recarrega uma vez (marca em `sessionStorage`).
- Falhou de novo na mesma sessão: fica em inglês, sem laço de recarga.
- Na abertura do painel, a falha deixa o painel em inglês em vez de em branco.
- Deu certo: a marca é apagada.

## Validação

- `TZ=UTC vitest run app/javascript/dashboard/i18n/specs`: 17 passaram (3 casos novos
  em `localeLoader.spec.js`).
- ESLint nos dois arquivos e `.github/scripts/email-protection-eslint.mjs`: sem
  bloqueio.
