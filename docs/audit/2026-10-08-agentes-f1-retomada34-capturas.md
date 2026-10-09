# F1 — retomada34: conferência visual das capturas desktop

## Escopo e limite

Inspecionei via leitura visual as 17 capturas `chromium-1440` em
`.codex/preview/agents/screenshots/retomada34/screenshots/`: lista e lower em
claro/escuro, vazio, viewer, loading, erro, dois diálogos e mutação. Não
executei navegador, testes, build ou alteração de produto/harness. A execução
informada terminou `25 PASS`, `0 FAIL`, `3 SKIP`, exit 0. Isso não equivale a
aceite humano, aceite global da jornada ou entrega de F2–F7.

## Resultado visual

- **Lista:** as versões clara e escura estão legíveis, sem corte dentro dos
  cartões e sem overflow aparente. As duas capturas `lista-real-lower` mostram
  a continuação completa até Clara, Lia, Ajuda interna e o aviso inferior; não
  há corte do footer nessa resolução.
- **Vazio:** claro e escuro mostram eyebrow, H1 branco, descrição, CTA e três
  cartões de modelo legíveis. O hero não está cortado e a composição mantém a
  hierarquia esperada.
- **Viewer:** claro e escuro mostram a lista em modo somente leitura, com
  “Abrir” e sem controles de escrita. A continuação abaixo da viewport é
  esperada; não há corte horizontal visível.
- **Loading:** claro e escuro exibem o cabeçalho e os skeletons sem transbordo.
  A imagem comprova a composição do estado ocupado, não a duração do atraso.
- **Erro:** claro e escuro exibem alerta, texto e “Tentar de novo” centrados e
  legíveis, sem corte.
- **Diálogos:** os diálogos de exclusão e pausa, em claro e escuro, ficam
  centralizados, com título, explicação e botões legíveis. O desfoque do fundo
  é consistente; a imagem não prova teclado, Escape ou restauração de foco.
- **Mutação:** `mutacoes-reais-chromium-1440-light.png` agora contém a lista
  após a operação, sem a imagem branca da retomada33. A captura é visualmente
  utilizável; persistência e efeitos da operação continuam sendo evidência do
  teste/API, não da imagem isolada.

Não observei texto cortado, conteúdo branco inesperado ou sobreposição entre
menu lateral, conteúdo e aviso inferior nas imagens desktop. O exame de
rodapé/menu em 400 px permanece com a validação móvel coordenada pelo root.

## Diferença de contagem

A lista clara apresenta sete itens para terminar e a escura seis. O payload da
execução confirma que a fixture do rascunho foi excluída pela mutação antes da
captura escura; a diferença é esperada e não indica divergência do produto.

## O que as imagens permitem apresentar

As capturas desktop34 podem ser mostradas como **prévia visual real** da lista,
vazio, viewer, loading, erro, diálogos e pós-mutação, sempre acompanhadas do
resultado `25 PASS / 0 FAIL / 3 SKIP` e da ressalva de que os três skips são
parte da execução. As imagens não encerram o aceite humano, não demonstram a
jornada completa de criação até “Pronto”, não substituem a cobertura móvel e
não autorizam anunciar F1 global ou F2–F7 como concluídos.
