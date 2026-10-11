# Agendamento: tema do aparelho e logo por tema (#1295)

Por cima do #1289. Sem migration.

## Decisões do Rodrigo (11/10/2026)

- **Logo: enviar as duas ou deixar o sistema gerar.** A pessoa pode enviar a logo de fundo claro e a de fundo escuro. Sem a segunda, o servidor gera, e a gerada aparece na tela para ver e trocar.
- **Tema da página pública segue o aparelho do cliente.** O jeito de fazer foi delegado.

## Decisões técnicas

- **Tema só com CSS.** As cores da página viraram variáveis `--bk-*` em `app/javascript/public_booking_v2/assets/_booking-theme.scss`: claro em `:root`, escuro em `@media (prefers-color-scheme: dark)`. O layout ganhou `<meta name="color-scheme" content="light dark">`. Nenhum script decide tema, então nada pisca. É a exceção consciente à regra "só Tailwind", no molde de `_next-colors.scss`; as classes saem de `theme/colors.js` (chave `bk`).
- **Tema claro igual ao de antes.** Os valores claros são os que as classes antigas já resolviam. Mudou uma coisa: a cor da marca usada como texto agora passa no AA também no fundo do botão secundário com o mouse em cima (`#f0f0f3`), que antes ficava abaixo para algumas cores livres.
- **`data-booking-theme="light|dark"` força o tema num pedaço da tela.** É o que a prévia do painel usa para mostrar os dois, seja qual for o tema do painel. O painel importa só o arquivo de cores, sem a regra do aparelho.
- **Cor da marca.** O JS grava `--brand-ink-light` (escurecida até AA) e `--brand-ink-dark` (clareada em HSL, sem perder o tom, até 6:1 sobre a superfície escura mais clara). O CSS escolhe `--brand` pelo tema. `--brand-fill` e `--brand-on` não mudaram.
- **Logo por tema sem JavaScript.** Com imagem própria para o escuro, as duas `<img>` ficam no HTML e uma variável do tema mostra uma só. Sem ela, a mesma imagem serve aos dois (`same`) ou ganha uma placa branca arredondada no escuro (`plate`). Valor desconhecido ou imagem que não carrega caem na placa: nunca logo invisível.
- **Onde fica guardado.** Anexo `logo_dark` na página e `brand.logo_dark_source` (`uploaded`, `generated`, `same`, `plate`), gravado só pelo servidor. Na identidade da conta: anexo `booking_identity_logo_dark` e a origem em `settings['booking_identity']`.
- **Geração no próprio pedido, sem fila.** Com libvips (`image_processing`, nenhuma gem nova), numa cópia de até 800 px. Medido: 30 a 220 ms, inclusive num PNG de 16 megapixels. Acima de 16 megapixels a imagem nem é aberta.
- **Regra da geração** (`Crm::BookingV2::LogoDarkEngine`, ideia do motor do Studio):
  1. Sem transparência, tenta tirar o fundo sólido: os quatro cantos parecidos e 90% da borda da mesma cor. Sai tudo o que tem a cor do fundo, inclusive o miolo das letras (o Studio guarda o miolo; no escuro ele viraria um borrão).
  2. Continua sem transparência (foto, JPEG sem fundo liso): `plate`.
  3. Até 10% dos pixels visíveis com contraste abaixo de 3:1 sobre o cartão escuro: `same` (ou a logo recortada, se o fundo foi tirado).
  4. Logo sem cor (preto, cinza, branco): tons invertidos, mantendo o desenho de dentro. Se inverter não melhorar, `plate`.
  5. Logo de uma cor só: silhueta branca.
  6. Várias cores com parte escura: `plate`.
- **Erro nunca derruba o envio da logo.** Arquivo ilegível, libvips ausente ou armazenamento fora do ar: a logo fica salva e a página vai para `plate`, com o motivo no log.
- **Página com logo de antes desta entrega** mostra a placa no escuro até ser salva de novo; no primeiro salvar, a logo de fundo escuro é gerada.
- **A logo de fundo escuro só é aceita em página que já tem logo.**

## Validação local (M4, só specs focados)

- RSpec (com a libvips 8.16.1 compilada no scratchpad, via `rt2.sh`): 248 exemplos, 0 falhas. Cobre o motor (20 casos), a API do painel, a API pública v2, identidade, policy (OSS e EE), modelo e `formatos_spec`.
- Vitest em `public_booking_v2` e `settings/booking`: 24 arquivos, 507 testes, 0 falhas. Inclui AA em 4.096 cores nos dois temas e a prévia igual à página nos dois temas.
- RuboCop: 19 arquivos, sem ocorrências. ESLint: 0 erros. Prettier em dia. Gate `email-protection-eslint`: 0 bloqueios.
- `autonomia:guia:formatos:check`, `guide-map/check.mjs`, `central-de-ajuda/conferir.mjs` e `check-fork-i18n.mjs`: em dia.
- Teste de mutação: sem a trava do `update`, o spec de dois pedidos ao mesmo tempo falha (origem `uploaded` vira `generated`).
- Conferência visual com Chrome headless e as folhas de estilo do projeto: página nos dois temas (data, horário, formulário com e sem erro, confirmação, gerenciar, cancelar, pausada, não encontrada, erro), logo deitada, quadrada e em pé, os quatro casos da logo no escuro, cor escura e clara, passo "Sua marca", prévia com o seletor e painel em tema escuro. O escuro foi exercitado pelo `prefers-color-scheme` de verdade. Dez logos de teste desenhadas para a ocasião passaram pelo motor real, com antes e depois lado a lado.

## Revisão independente

Primeira passada: nenhum achado crítico ou alto. Corrigidos:

- AA da cor da marca no botão secundário com o mouse em cima, no tema claro.
- Dois pedidos ao mesmo tempo podiam regravar a origem antiga da logo: a página agora é travada e relida antes de gravar (salvar, enviar, tirar e usar a identidade). A conta da imagem é feita antes, fora da trava.
- Tirar a logo enviada com erro na geração respondia 500: agora cai na placa.
- Imagem menor que 3 pixels passou a ter motivo próprio em vez de cair no socorro de erro.
- Origem que promete imagem ausente é resolvida ao salvar e ao usar a identidade.
- As duas `<img>` têm valor padrão fora de um tema; o botão da logo clara fica desligado enquanto a outra sobe.

Segunda passada, sobre as correções: um achado alto, corrigido. Um erro ao gerar podia levar a página para a placa e apagar a logo de fundo escuro que a pessoa tinha enviado; agora a enviada só sai quando a própria pessoa pede.

Conferido e descartado com teste: PNG de 16 bits e PNG em tons de cinza saem certos.

Ficou como está, registrado: dois "salvar" juntos numa página antiga podem gerar a logo de fundo escuro duas vezes (o resultado é o mesmo); falha do armazenamento depois da gravação deixa a origem `uploaded` com o arquivo ausente, e a página pública cai na placa quando a imagem não carrega.

## Fora desta entrega

- Página antiga (`show.html.erb`) e a imagem de prévia do link não mudam de tema.
- O quadro do hCaptcha lê o tema uma vez, ao montar: não acompanha a troca de tema com a página aberta.
- Não validado: build completo do Vite e suíte ampla (ficam para o CI).
