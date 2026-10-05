# Instagram #931 — QA de componente real no navegador

Alinhamento #956: a conta sintética tem `instagram_assisted_onboarding=true` por padrão, inclusive na escolha do canal do wizard. `feature=off` desliga somente a flag da conta; `globalFeature=off` controla separadamente a configuração global sintética. `account-feature-off-legacy` agora exige flag OFF explícita e zero requests tester, preservando OAuth novo legado sem corpo. `configuration.enabled=false` com a conta ON exige UNAVAILABLE, zero OAuth e nenhum fallback legado: caso adicional `account-feature-on-configuration-disabled-unavailable`. Permanecem os 37 casos anteriores, com essa mudança de expectativa contratual, mais um caso: 38 componentes e os mesmos 72 casos do wizard. As variantes claro/escuro e tamanhos repetem os cenários para verificar render, não são jornadas backend independentes.

Reautorização recebe a entidade existente do store sintético (caixa 9101). Clique real exige exclusivamente `{ inbox_id: 9101, return_to: 'inbox' }`; fixtures rejeitam outra caixa, ID string, outro destino e selection token extra. Novo OAuth legado OFF continua exigindo corpo ausente. Os manifestos reais ficam nos caminhos abaixo; contagens planejadas não substituem `counts`, hashes estáveis e exit code da execução. Para esta worktree, use `tmp/950-integration/run-local.sh env` antes dos comandos de render e passe as mesmas variáveis Playwright após o wrapper; nenhum banco é utilizado.

Refinement de evidência do toast: o host monta o **`dashboard/components/SnackbarContainer.vue` real**, como `dashboard/App.vue`, com `Snackbar.vue`, event bus e `useAlert` de produção intactos. Não há HTML de toast artificial nem mudança em produto/Banner. O caso existente `legacy-oauth-failure-clears-loading` mantém dois POSTs reais internos com corpo ausente: primeiro aborto de transporte sintético `timedout` (não mede deadline real de Axios), depois resposta sintética 503. Gates permitem provar loading/CTA disabled em voo; em cada falha exige CTA habilitado novamente e mensagem exata `ERROR_AUTH` traduzida pelo i18n real dentro do popover aberto e inteiramente no viewport. Aguarda o desaparecimento normal do primeiro toast antes do retry; não altera a duração de produção. A captura existente `legacy-recovery` exige toast antes e depois da screenshot, sem overlay. `screens[].toastRecovery` registra as duas verificações; `screenshots[].capturedAt` usa timestamp UTC ISO e as posições reais ficam em `toasts`/`toastsAfterCapture`.

O `run.mjs` reprova toast inesperado nos outros casos; erros Vue, console, página, i18n e overlay continuam reprovando. Somente o erro Chromium `net::ERR_TIMED_OUT` no path exato da autorização cujo contrato já foi validado é permitido para a primeira tentativa. Não há ignore global de popover/erro. O wizard continua com os mesmos 72 casos e suas verificações; a montagem do snackbar no host é compartilhada. São **37 casos de componente +72 de wizard**, sem remoções/skips, e 73/76 capturas previstas respectivamente. Essas contagens não são resultado executado destas fontes.

As fontes do harness mudaram após a revisão de arte anterior; resultados/capturas anteriores não fecham este refinement. A copy final foi confirmada em `ui-copy-final-result.md`; a próxima execução completa e sequencial do parent deverá comprovar fontes/CSS estáveis e toast real. Até esse render, nenhuma aprovação nova é declarada e nenhum artefato é publicado em `docs/assets`.

Execute na raiz, com dependências existentes e Chromium já instalado:

```sh
INSTAGRAM_QA_RENDER_READY=1 PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/run.mjs

# Telas do wizard, componentes reais em estados sintéticos separados
INSTAGRAM_QA_RENDER_READY=1 PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/wizard.mjs
```

`INSTAGRAM_QA_RENDER_READY=1` só deve ser definido após o coordenador confirmar dependências locais, build CSS concluído e fontes UI estáveis. Sem o gate, o harness retorna `BLOCKED`. `PLAYWRIGHT_MODULE_PATH` aceita o diretório do módulo instalado ou seu `index.mjs`. Não instala dependências nem baixa navegador. Se necessário, `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` seleciona um Chromium já existente. O coordenador deve gerar primeiro `public/vite-test/assets/dashboard-*.css`; a URL `/vite-test/assets/dashboard-*.css` corresponde a esse arquivo físico dentro de `public/`, enquanto a URL de utilities corresponde ao arquivo gerado em `tmp/instagram-931/qa-evidence/`. O servidor registra esse mapa em `server.json.styleFiles`; sem esse CSS a execução resulta em `BLOCKED`, jamais em aprovação.

O servidor segue o padrão `tests/qa/email-campaigns`: Vite com `configFile:false`, `envFile:false`, loopback **127.0.0.1:39211**, `strictPort:true`. Usa o dashboard CSS do build e utilidades geradas pelo PostCSS/Tailwind do repositório para incluir classes novas. Sem estilos substitutos. Monta os componentes de produção reais (`InboxChannels`, `ChannelList`, `ChannelFactory`, `Instagram`, `TesterOnboarding`, `AddAgents`, `FinishSetup` e `Reauthorize`) com Router/Vuex/Pinia/i18n/Axios reais; somente flags da conta sintética, agentes/inbox de demonstração e respostas HTTP internas são simulados. Não monta mockup de produto, não usa Rails/banco/contas reais e não acessa Meta. Essa evidência é QA de componente, **não backend E2E nem homologação Meta**.

Cada caso usa contexto Chromium headless novo, sem perfil persistente, cookies pessoais, extensão, HAR, trace ou vídeo. Todas as requisições fora da origem exata são abortadas, incluindo imagens, popup e OAuth. Os únicos contratos mockados são `/api/v1/accounts/910/instagram/testers/{configuration,search,status,invite}` e `/instagram/authorization`. O avatar sintético é um SVG estático local. Contratos inesperados falham; métodos e corpos são validados sem gravar tokens/bodies/headers.

Cobertura do `run.mjs`: flag global desligada sem API nova; flag da conta desligada; busca com dois resultados e seleção explícita, resultado único, segundo candidato, teclado/foco/labels, entrada inválida/vazia, resultado vazio/malformado, edição durante busca; ausente → envio → pendente → ainda pendente → aceito sem OAuth automático; instruções completas e link seguro; configuração/sessão indisponíveis; seleção expirada; status inválido; clique duplo; restrição Meta com zero search/status/invite/OAuth; proxy indisponível na busca/status com recuperação sintética; erro de OAuth legado libera loading; callback LimitExceeded/402 no assistido e legado; envio indeterminado e reconciliação sem retry; resposta de convite malformada; inglês. Gates controlados sustentam a concorrência, sem depender de sleeps para simular clique duplo.

Cobertura planejada do `wizard.mjs`: escolha do canal e clique real em Instagram; campo vazio, busca carregando, resultados e vazio; estados ausente, pendente, aceito e erro; falha de configuração; restrição Meta, proxy indisponível na busca/status e limite de caixas; atribuição de agentes com menu fechado após seleção, finalização, reautorização e legado com flag desligada. São **18 cenários × 2 tamanhos × 2 temas = 72 casos, com 76 capturas previstas** se todos concluírem; agentes têm duas capturas por caso. Tamanhos: 1440×900 e 390×844, claro/escuro. Essas são contagens de planejamento; o resultado executado vem de `counts` e `screenshots` do novo manifesto.

O caso `wizard-instagram-legacy-feature-off` verifica zero requests para `/testers` e o CTA OAuth legado visível. Reautorização clica no botão real, aguarda POST para `/api/v1/accounts/910/instagram/authorization` com corpo ausente, resposta interna200 e tentativa de navegação OAuth abortada. Agentes, conclusão e reautorização são montados em contextos sintéticos separados: isso **não comprova uma jornada contínua nem conexão concluída**. Todos os perfis são sintéticos. `tmp/instagram-931/qa-evidence/wizard/results.json` separa requests internos simulados e tentativas externas bloqueadas.

Regressões de `art-final-review.md`: em cada estágio capturado do fluxo novo, mede contraste **≥4,5:1** dos botões sólidos habilitados e do título “Convite aceito”, em estado normal, hover e foco de teclado. Usa as cores computadas do elemento de texto e compõe fundos/alpha/opacidade dos ancestrais, incluindo o filtro `brightness`. Aguarda o fim das transições antes de medir. Cor/filtro/gradiente não suportados falham explicitamente; não são ignorados. Os botões sólidos atuais do design system são identificados pela classe `text-white`, dentro do componente assistido; o legado preservado fica fora dessa medição. O limiar é aplicado ao valor completo, sem arredondamento antes da assertion.

Nos estados selecionados em 320px/390px, mede largura da linha de avatar/identidade, espaço efetivamente disponível para texto, posição e alinhamento do botão “Trocar perfil”; exige linha própria e palavras do nome sem cortes internos. O @ sintético normal de 390px deve caber numa linha. Nas instruções, exige quatro marcadores computados `decimal`/`list-item` visíveis e orientação de suporte depois do CTA tanto no DOM quanto na geometria. Cores, razões, camadas de CSS, larguras e marcadores ficam em `screens[].visualChecks`. O manifesto registra hashes antes/depois de todas as fontes locais transitivas, incluindo composable, API, instruções, catálogos, estilos, inputs Tailwind e harness. O grafo Vite identifica módulos efetivamente carregados. Também registra os hashes dos CSS físicos antes/depois, dos bytes recebidos pelo Chromium e das stylesheets do CSSOM (incluindo style tags injetadas pelo Vite). Fonte ausente ou alterada, CSS ausente e divergência de CSS consumido entre casos reprovam; não há fallback para estilos antigos.

Regressão de `art-current-main.md`: no estágio inicial `profile`, com campo vazio e `:placeholder-shown`, exige contraste **≥4,5:1** do `::placeholder` em estado normal e foco. Lê a cor e a opacidade do pseudo-elemento, compõe sobre o fundo real do input e usa os mesmos helpers de superfície/filtros dos outros textos; não usa a cor regular do input como substituta. Aplica em todos os dez casos iniciais claro/escuro, incluindo 1440px e 320px. Medidas ficam como `kind: placeholder`, com `pseudoElement` e `pseudoOpacity`. As novas imagens iniciais usam prefixo `placeholder-regression-` para preservar as imagens examinadas anteriormente.

PT-BR: 1440×900, 1024×768, 390×844, 320×568, claro/escuro; desktop com CSS zoom 200% nos dois temas. CSS zoom verifica reflow e alvos, mas **não é zoom da barra do navegador**. Capturas de página inteira mantêm a largura do viewport e incluem conteúdo vertical fora da primeira dobra. Os casos narrow/zoom usam nome e @ longos. O `run.mjs` concentra a regressão do componente; o `wizard.mjs` cobre o shell real do wizard.

Artefatos regeneráveis e exclusivos desta execução em **`tmp/instagram-931/qa-evidence/`** (output para coleta no CI):

- `results.json`: casos explícitos PASS/FAIL/BLOCKED, viewports, requests por método/path, erros, estilos efetivamente carregados, dimensões e manifest de screenshots desta execução.
- `server.json`: origem, PID, URLs CSS e mapa `styleFiles` para arquivos físicos.
- `art-regression-*.png`: somente dados sintéticos; entrada, candidatos, ausente, pendente, aceito, erro, legado e envio indeterminado. O prefixo preserva as imagens antigas examinadas pelo diretor de arte.
- `current-utilities.css` e `vite-cache/`: derivados locais reconstruíveis.
- `wizard/results.json`: resultado e manifesto das telas reais do wizard, com limitações da API sintética.
- `wizard/*.png`: capturas sintéticas em scratch de escolha de canal, estados do tester, tela legada com a flag desligada, agentes, finalização e reautorização.

Resultados HTTP de erro intencionalmente injetados geram diagnósticos de transporte do Chromium. O relatório os separa por path/status exatos esperados; qualquer outro erro de console, erro Vue, pageerror, tradução ausente, overlay, tela vazia ou contrato inesperado reprova. Na navegação OAuth, a saúde é validada antes da navegação e a tentativa externa é comprovadamente abortada; não se declara a página de erro esperada do navegador como UI saudável. Não há aprovação parcial: setup bloqueado mantém todos os casos não executados como BLOCKED; qualquer assertion falha gera saída não zero. Nenhuma chamada real Meta/OAuth foi validada.

O build e os comandos de render acima regeneram esses artefatos; não copie imagens da galeria antiga para completar uma rodada. O CI deve coletar `results.json`, `wizard/results.json`, `server.json` e somente as PNGs listadas nos manifestos desta execução. `current-utilities.css` e `vite-cache/` são derivados locais reconstruíveis. Não publique `docs/assets` antes de render limpo, hashes estáveis e revisão visual independente. A galeria anterior `docs/assets/instagram-testers-910/` é evidência histórica e não comprova aprovação de #931. Medidas de geometria/contraste computado não comprovam sozinhas qualidade estética ou homologação externa.

Validação offline dos contratos sintéticos, sem iniciar navegador/servidor:

```sh
node --test tests/qa/instagram-testers/fixtures.test.mjs tests/qa/instagram-testers/evidence.test.mjs tests/qa/instagram-testers/visual-helpers.test.mjs
node --test tests/qa/instagram-testers/toast-helpers.test.mjs
node --check tests/qa/instagram-testers/server.mjs
node --check tests/qa/instagram-testers/run.mjs
node --check tests/qa/instagram-testers/wizard.mjs
node --check tests/qa/instagram-testers/entry.js
```

Esses checks não substituem os casos de navegador em `results.json`.

No snapshot isolado de #931, use o wrapper fornecido pelo coordenador:

```sh
tmp/instagram-931/run-local.sh node --test tests/qa/instagram-testers/fixtures.test.mjs tests/qa/instagram-testers/evidence.test.mjs tests/qa/instagram-testers/visual-helpers.test.mjs
tmp/instagram-931/run-local.sh node --test tests/qa/instagram-testers/toast-helpers.test.mjs
tmp/instagram-931/run-local.sh env INSTAGRAM_QA_RENDER_READY=1 PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/run.mjs
tmp/instagram-931/run-local.sh env INSTAGRAM_QA_RENDER_READY=1 PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/wizard.mjs
```

O wrapper limpa o ambiente; passe as envvars Playwright depois dele, incluindo `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` se necessário. Execute `run.mjs` e `wizard.mjs` sequencialmente, pois compartilham porta, CSS gerado e output. Se o listener for negado pelo sandbox, pare e entregue a execução ao coordenador; não escolha outra porta ou transporte.
