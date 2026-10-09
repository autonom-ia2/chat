# F1 — retomada33: conferência visual das capturas desktop

## Escopo e limite

Inspecionei, em leitura visual, todas as capturas `chromium-1440` em
`.codex/preview/agents/screenshots/retomada33/screenshots/`, incluindo a
captura `lista-real-lower`. Não executei navegador, Axe, teste, build ou
alteração de produto. O job terminou `8 PASS`, `17 FAIL` e `3 SKIP` (exit 1);
esta nota não transforma imagem em aceite nem declara Axe aprovado.

## O que pode ser mostrado como prévia

- **Lista clara e escura:** os cabeçalhos, chips, cartões, selos e ações estão
  legíveis e sem corte dentro dos cartões. A captura clara de `lista-real-lower`
  mostra a continuação da lista e o aviso inferior; a captura superior termina
  no limite normal da viewport, não por corte do layout. Não há captura lower
  escura equivalente.
- **Vazio claro:** o herói, o título branco, a descrição, o CTA e os três
  modelos estão inteiros e legíveis. Serve como prévia da composição desktop.
- **Viewer claro e escuro:** a lista e o rótulo “Abrir” estão legíveis; os
  controles de escrita não aparecem. A lista continua abaixo da viewport, como
  esperado para uma página rolável.
- **Loading claro e escuro:** cabeçalho, CTA e blocos de carregamento aparecem
  sem transbordar ou cortar a viewport. A imagem mostra o estado de espera, não
  prova tempo de resposta ou ausência de mudança de estado.
- **Erro claro e escuro:** alerta central, mensagem e “Tentar de novo” estão
  legíveis, centrados e sem corte.
- **Diálogos claro e escuro:** “Excluir este rascunho?” e “Pausar este agente?”
  aparecem centralizados, com texto e botões legíveis. O desfoque do fundo é
  esperado; a imagem não prova foco, Escape ou retorno de foco.

Essas imagens podem ilustrar a prévia visual desktop, sempre com a indicação de
que a matriz completa continua pendente.

## Problemas visuais observados

1. **Vazio escuro parcialmente ilegível:** em
   `vazio-real-chromium-1440-dark.png`, o H1 aparece branco e legível, mas o
   eyebrow “AGENTES” e a descrição aparecem muito escuros sobre o fundo
   azul-marinho. O CTA continua visível. O correspondente claro está legível.
   A captura escura não deve ser apresentada como tela aprovada; é necessário
   confirmar a correção de cor do eyebrow e da descrição no produto e recapturar.
2. **Mutação sem conteúdo:**
   `mutacoes-reais-chromium-1440-light.png` é uma imagem praticamente toda
   branca, sem lista, diálogo ou estado final visível. Não é uma prévia útil e
   não comprova pausa, religação ou exclusão.
3. **Base visual alterada pela própria mutação:** a diferença de contagem
   `12 → 11` entre capturas é esperada: a fixture do rascunho foi excluída pela
   mutação antes da captura escura, conforme o payload confirmado. Não é desvio
   do produto; as imagens apenas não devem ser comparadas como o mesmo retrato
   temporal da fixture.

Não observei corte de texto ou overflow horizontal nas imagens desktop
inspecionadas. A existência de uma imagem legível também não substitui a
execução pendente dos 400 px, a comparação com o mockup, as asserções de API ou
o resultado do Axe.

## Conclusão de entrega

É seguro apresentar como **prévia sem aceite**: lista desktop clara/escura,
lista lower clara, vazio claro, viewer claro/escuro, loading claro/escuro, erro
claro/escuro e os dois diálogos em claro/escuro. O vazio escuro e a captura de
mutação devem ficar fora da apresentação até correção/recaptura. A primeira
tela real continua sem aceite global; não há base visual para anunciar F1 como
concluída.
