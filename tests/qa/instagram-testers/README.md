# Instagram #910 — QA de componente real no navegador

Execute na raiz, com dependências existentes e Chromium já instalado:

```sh
PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/run.mjs

# Wizard completo, componentes reais e estados sintéticos
PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright node tests/qa/instagram-testers/wizard.mjs
```

`PLAYWRIGHT_MODULE_PATH` aceita o diretório do módulo instalado ou seu `index.mjs`. Não instala dependências nem baixa navegador. Se necessário, `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` seleciona um Chromium já existente. O coordenador deve gerar primeiro `public/vite-test/assets/dashboard-*.css`; sem esse CSS a execução resulta em `BLOCKED`, jamais em aprovação.

O servidor segue o padrão `tests/qa/email-campaigns`: Vite com `configFile:false`, `envFile:false`, loopback **127.0.0.1:39211**, `strictPort:true`. Usa o dashboard CSS do build e utilidades geradas pelo PostCSS/Tailwind do repositório para incluir classes novas. Sem estilos substitutos. Monta os componentes de produção reais (`InboxChannels`, `ChannelList`, `ChannelFactory`, `Instagram`, `TesterOnboarding`, `AddAgents`, `FinishSetup` e `Reauthorize`) com Router/Vuex/Pinia/i18n/Axios reais; somente flags da conta sintética, agentes/inbox de demonstração e respostas HTTP internas são simulados. Não monta mockup de produto, não usa Rails/banco/contas reais e não acessa Meta. Essa evidência é QA de componente, **não backend E2E nem homologação Meta**.

Cada caso usa contexto Chromium headless novo, sem perfil persistente, cookies pessoais, extensão, HAR, trace ou vídeo. Todas as requisições fora da origem exata são abortadas, incluindo imagens, popup e OAuth. Os únicos contratos mockados são `/api/v1/accounts/910/instagram/testers/{configuration,search,status,invite}` e `/instagram/authorization`. O avatar sintético é um SVG estático local. Contratos inesperados falham; métodos e corpos são validados sem gravar tokens/bodies/headers.

Cobertura do `run.mjs`: flag global desligada sem API nova; flag da conta desligada; busca com dois resultados e seleção explícita, resultado único, segundo candidato, teclado/foco/labels, entrada inválida/vazia, resultado vazio/malformado, edição durante busca; ausente → envio → pendente → ainda pendente → aceito sem OAuth automático; instruções completas e link seguro; configuração/sessão indisponíveis; seleção expirada; status inválido; clique duplo; restrição Meta; envio indeterminado e reconciliação sem retry; resposta de convite malformada; inglês. Gates controlados sustentam a concorrência, sem depender de sleeps para simular clique duplo.

Cobertura do `wizard.mjs`: escolha do canal Instagram no wizard real; campo vazio, busca carregando, resultados e vazio; estados ausente, pendente, aceito e erro; falha de configuração; atribuição de agentes, finalização, reautorização e a tela legada com a flag desligada. Cada tela é capturada em 1440×900 e 390×844, claro/escuro (**56 casos, 60 imagens**: 52 casos com a flag ligada geram 56 imagens porque a atribuição tem estado aberto e selecionado, e 4 casos com a flag desligada geram uma imagem cada). O caso `wizard-instagram-legacy-feature-off` verifica zero requests para `/testers` e o CTA OAuth legado visível. O avatar e todos os perfis são sintéticos. O arquivo `tmp/instagram-910/visual/wizard/results.json` separa os requests internos simulados e as tentativas externas bloqueadas.

Regressões de `art-final-review.md`: em cada estágio capturado do fluxo novo, mede contraste **≥4,5:1** dos botões sólidos habilitados e do título “Convite aceito”, em estado normal, hover e foco de teclado. Usa as cores computadas do elemento de texto e compõe fundos/alpha/opacidade dos ancestrais, incluindo o filtro `brightness`. Aguarda o fim das transições antes de medir. Cor/filtro/gradiente não suportados falham explicitamente; não são ignorados. Os botões sólidos atuais do design system são identificados pela classe `text-white`, dentro do componente assistido; o legado preservado fica fora dessa medição. O limiar é aplicado ao valor completo, sem arredondamento antes da assertion.

Nos estados selecionados em 320px/390px, mede largura da linha de avatar/identidade, espaço efetivamente disponível para texto, posição e alinhamento do botão “Trocar perfil”; exige linha própria e palavras do nome sem cortes internos. O @ sintético normal de 390px deve caber numa linha. Nas instruções, exige quatro marcadores computados `decimal`/`list-item` visíveis e orientação de suporte depois do CTA tanto no DOM quanto na geometria. Cores, razões, camadas de CSS, larguras e marcadores ficam em `screens[].visualChecks`. O manifesto de hashes inclui `TesterAcceptanceInstructions.vue`.

Regressão de `art-current-main.md`: no estágio inicial `profile`, com campo vazio e `:placeholder-shown`, exige contraste **≥4,5:1** do `::placeholder` em estado normal e foco. Lê a cor e a opacidade do pseudo-elemento, compõe sobre o fundo real do input e usa os mesmos helpers de superfície/filtros dos outros textos; não usa a cor regular do input como substituta. Aplica em todos os dez casos iniciais claro/escuro, incluindo 1440px e 320px. Medidas ficam como `kind: placeholder`, com `pseudoElement` e `pseudoOpacity`. As novas imagens iniciais usam prefixo `placeholder-regression-` para preservar as imagens examinadas anteriormente.

PT-BR: 1440×900, 1024×768, 390×844, 320×568, claro/escuro; desktop com CSS zoom 200% nos dois temas. CSS zoom verifica reflow e alvos, mas **não é zoom da barra do navegador**. Capturas de página inteira mantêm a largura do viewport e incluem conteúdo vertical fora da primeira dobra. Os casos narrow/zoom usam nome e @ longos. O `run.mjs` concentra a regressão do componente; o `wizard.mjs` cobre o shell real do wizard.

Artefatos em `tmp/instagram-910/visual/`:

- `results.json`: casos explícitos PASS/FAIL/BLOCKED, viewports, requests por método/path, erros, estilos efetivamente carregados, dimensões e manifest de screenshots desta execução.
- `server.json`: origem, PID e CSS utilizado.
- `art-regression-*.png`: somente dados sintéticos; entrada, candidatos, ausente, pendente, aceito, erro, legado e envio indeterminado. O prefixo preserva as imagens antigas examinadas pelo diretor de arte.
- `current-utilities.css` e `vite-cache/`: derivados locais reconstruíveis.
- `wizard/results.json`: resultado e manifesto das telas reais do wizard, com limitações da API sintética.
- `wizard/*.png`: capturas versionáveis de escolha de canal, estados do tester, tela legada com a flag desligada, agentes, finalização e reautorização.

Resultados HTTP de erro intencionalmente injetados geram diagnósticos de transporte do Chromium. O relatório os separa por path/status exatos esperados; qualquer outro erro de console, erro Vue, pageerror, tradução ausente, overlay, tela vazia ou contrato inesperado reprova. Na navegação OAuth, a saúde é validada antes da navegação e a tentativa externa é comprovadamente abortada; não se declara a página de erro esperada do navegador como UI saudável. Não há aprovação parcial: setup bloqueado mantém todos os casos não executados como BLOCKED; qualquer assertion falha gera saída não zero. Nenhuma chamada real Meta/OAuth foi validada.

A rodada atual do wizard gerou 60 capturas em 56 casos; galeria e hashes foram conferidos pelo coordenador e pelo revisor UI. A revisão visual final de Rodrigo permanece anterior à publicação. Medidas de geometria/contraste computado não comprovam sozinhas qualidade estética, contraste dos pixels antialiasados ou homologação externa. Use `docs/assets/instagram-testers-910/manifest.json`; as quatro imagens anteriores estão arquivadas fora do índice atual.

Validação offline dos contratos sintéticos, sem iniciar navegador/servidor:

```sh
node --test tests/qa/instagram-testers/fixtures.test.mjs tests/qa/instagram-testers/visual-helpers.test.mjs
node --check tests/qa/instagram-testers/server.mjs
node --check tests/qa/instagram-testers/run.mjs
node --check tests/qa/instagram-testers/wizard.mjs
node --check tests/qa/instagram-testers/entry.js
```

Esses checks não substituem os casos de navegador em `results.json`.
