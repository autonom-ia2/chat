# Agendamento: baixar o QR code da página (#1290)

Data: 11/10/2026. Branch `feat/1290-baixar-qr`.

## Decisões

- O botão mora num componente novo (`BookingQrDownload.vue`), ligado em
  `BookingLinkActions.vue`, por onde passam a lista, o passo final e "um link
  para cada pessoa". Toque mínimo nos arquivos que #1282 e #1289 também mexem.
- PNG de 1024 px, margem de silêncio de 4 módulos, fundo branco opaco e
  correção de erro Q (25%). SVG como ação secundária: o pacote `qrcode` já gera,
  sem dependência nova.
- Nome do arquivo com `@sindresorhus/slugify` (já usado no portal):
  `qr-<pagina>.png`; no link por pessoa, `qr-<pagina>-<pessoa>.png`.
- Navegador que bloqueia download costuma não avisar. Por isso, depois de cada
  pedido fica um link para abrir a imagem e salvar por lá; quando a recusa é
  detectável, o texto diz que o navegador não deixou.
- Cartaz (logo + nome + QR + frase) ficou fora. A logo vem do armazenamento por
  redirecionamento (`url_for` do anexo); desenhar em canvas exige CORS no
  armazenamento, que não deu para conferir daqui, e sem ele o cartaz sairia sem
  logo em silêncio. Pede issue própria.

## Validação

- Vitest focado em `settings/booking/specs`: 15 arquivos, 217 testes, 0 falhas.
- ESLint: 0 erros (avisos `no-missing-keys` de `BOOKING`, que já existiam).
  Prettier: sem diferença. `email-protection-eslint.mjs`: 0 bloqueios.
  `check-fork-i18n.mjs`: en e pt_BR cobertos.
- PNG e SVG gerados pelo código real no Chrome headless e lidos de volta com o
  detector de código de barras do macOS (Vision): os dois devolvem o link.

## Não validado

- O botão dentro do painel rodando (Tailwind real, celular de verdade, iOS).
