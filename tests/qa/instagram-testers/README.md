# Instagram #910 — QA de componente real no navegador

Execute na raiz, com dependências existentes e Chromium já instalado:

```sh
PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/run.mjs
```

`PLAYWRIGHT_MODULE_PATH` aceita o diretório do módulo instalado ou seu `index.mjs`. Não instala dependências nem baixa navegador. Se necessário, `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` seleciona um Chromium já existente. O coordenador deve gerar primeiro `public/vite-test/assets/dashboard-*.css`; sem esse CSS a execução resulta em `BLOCKED`, jamais em aprovação.

O servidor segue o padrão `tests/qa/email-campaigns`: Vite com `configFile:false`, `envFile:false`, loopback **127.0.0.1:39211**, `strictPort:true`. Usa o dashboard CSS do build e utilidades geradas pelo PostCSS/Tailwind do repositório para incluir classes novas. Sem estilos substitutos. Monta **Instagram.vue e filhos reais** com Router/Vuex/Pinia/i18n/Axios reais; apenas flags da conta e respostas HTTP internas são sintéticas. Sem wizard/sidebar completo, Rails, banco, contas reais ou integração Meta. Essa evidência é QA de componente, **não backend E2E**.

Cada caso usa contexto Chromium headless novo, sem perfil persistente, cookies pessoais, extensão, HAR, trace ou vídeo. Todas as requisições fora da origem exata são abortadas, incluindo imagens, popup e OAuth. Os únicos contratos mockados são `/api/v1/accounts/910/instagram/testers/{configuration,search,status,invite}` e `/instagram/authorization`. O avatar sintético é um SVG estático local. Contratos inesperados falham; métodos e corpos são validados sem gravar tokens/bodies/headers.

Cobertura: flag global desligada sem API nova; flag da conta desligada; busca com dois resultados e seleção explícita, resultado único, segundo candidato, teclado/foco/labels, entrada inválida/vazia, resultado vazio/malformado, edição durante busca; ausente → envio → pendente → ainda pendente → aceito sem OAuth automático; instruções completas e link seguro; configuração/sessão indisponíveis; seleção expirada; status inválido; clique duplo; restrição Meta; envio indeterminado e reconciliação sem retry; resposta de convite malformada; inglês. Gates controlados sustentam a concorrência, sem depender de sleeps para simular clique duplo.

Regressões de `art-final-review.md`: em cada estágio capturado do fluxo novo, mede contraste **≥4,5:1** dos botões sólidos habilitados e do título “Convite aceito”, em estado normal, hover e foco de teclado. Usa as cores computadas do elemento de texto e compõe fundos/alpha/opacidade dos ancestrais, incluindo o filtro `brightness`. Aguarda o fim das transições antes de medir. Cor/filtro/gradiente não suportados falham explicitamente; não são ignorados. Os botões sólidos atuais do design system são identificados pela classe `text-white`, dentro do componente assistido; o legado preservado fica fora dessa medição. O limiar é aplicado ao valor completo, sem arredondamento antes da assertion.

Nos estados selecionados em 320px/390px, mede largura da linha de avatar/identidade, espaço efetivamente disponível para texto, posição e alinhamento do botão “Trocar perfil”; exige linha própria e palavras do nome sem cortes internos. O @ sintético normal de 390px deve caber numa linha. Nas instruções, exige quatro marcadores computados `decimal`/`list-item` visíveis e orientação de suporte depois do CTA tanto no DOM quanto na geometria. Cores, razões, camadas de CSS, larguras e marcadores ficam em `screens[].visualChecks`. O manifesto de hashes inclui `TesterAcceptanceInstructions.vue`.

PT-BR: 1440×900, 1024×768, 390×844, 320×568, claro/escuro; desktop com CSS zoom 200% nos dois temas. CSS zoom verifica reflow e alvos, mas **não é zoom da barra do navegador**. Capturas de página inteira mantêm a largura do viewport e incluem conteúdo vertical fora da primeira dobra. Os casos narrow/zoom usam nome e @ longos. Não representam o layout completo do wizard.

Artefatos em `tmp/instagram-910/visual/`:

- `results.json`: casos explícitos PASS/FAIL/BLOCKED, viewports, requests por método/path, erros, estilos efetivamente carregados, dimensões e manifest de screenshots desta execução.
- `server.json`: origem, PID e CSS utilizado.
- `art-regression-*.png`: somente dados sintéticos; entrada, candidatos, ausente, pendente, aceito, erro, legado e envio indeterminado. O prefixo preserva as imagens antigas examinadas pelo diretor de arte.
- `current-utilities.css` e `vite-cache/`: derivados locais reconstruíveis.

Resultados HTTP de erro intencionalmente injetados geram diagnósticos de transporte do Chromium. O relatório os separa por path/status exatos esperados; qualquer outro erro de console, erro Vue, pageerror, tradução ausente, overlay, tela vazia ou contrato inesperado reprova. Na navegação OAuth, a saúde é validada antes da navegação e a tentativa externa é comprovadamente abortada; não se declara a página de erro esperada do navegador como UI saudável. Não há aprovação parcial: setup bloqueado mantém todos os casos não executados como BLOCKED; qualquer assertion falha gera saída não zero. Nenhuma chamada real Meta/OAuth foi validada.

As imagens novas ainda precisam da revisão final do diretor de arte independente. Medidas de geometria/contraste computado não comprovam qualidade estética, contraste dos pixels antialiasados ou o wizard completo. Use o manifest atual; imagens antigas podem permanecer no diretório.

Validação offline dos contratos sintéticos, sem iniciar navegador/servidor:

```sh
node --test tests/qa/instagram-testers/fixtures.test.mjs tests/qa/instagram-testers/visual-helpers.test.mjs
node --check tests/qa/instagram-testers/server.mjs
node --check tests/qa/instagram-testers/run.mjs
node --check tests/qa/instagram-testers/entry.js
```

Esses checks não substituem os casos de navegador em `results.json`.
