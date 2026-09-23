# Central de Ajuda "Plataforma": estado para retomar

Última atualização: 23/09/2026. Épico **#485**, onda 2 (Central de Ajuda). Issues **#501**
(tela de leitura, bloqueios) e **#502** (conteúdo e publicação). Leia este arquivo primeiro ao
voltar.

## Onde estamos

23/09/2026:
- **161 de 162 artigos escritos** em `lib/central_de_ajuda/`. O #607 (exército, 149 artigos) está
  no `main`. O capítulo 18 (12 artigos de conceito) foi escrito com o Rodrigo a partir das
  reuniões de implantação e conferido no código.
- **Falta:** 01.07 "Como usar a Central de Ajuda", depois da tela de leitura (#501).
- **CONFIRMAR NA TELA** (resolver com os prints): 06.02, 08.09, 10.05, 10.08, 13.05, 15.01,
  15.02 (textos de tela); 10.12 (a ajuda do Dataset ID promete derivar da conexão do WhatsApp e
  o código não faz). O 10.07 foi resolvido pelo capítulo 18: o texto por etapa que a IA lê é o
  **critério**, e a etapa não tem outra descrição na tela.
- **CONFIRMAR COM O RODRIGO** (fatos da Meta ou orientação dele, fora do código): 18.02 (limite
  de 20 contatos por disparo no WhatsApp API; o limite de mensagens comerciais sobe com o uso),
  18.03 ("sem taxa em cima", "o funil custa pouco por mês").
- **Lacunas achadas no capítulo 11** (recurso sem artigo próprio): **Público-alvo** e **Horário
  de atuação** do agente de IA (aba **Ajustar**) e a opção **Resposta errada** no menu de uma
  mensagem do agente. O capítulo 18 cita os dois; falta o passo a passo no 11. O 11.07
  declara o assunto da aba **Testar**, mas não explica o que ela mostra (Confiança,
  Conhecimento utilizado, aviso de transferência).
- Roteiro de prints: `pnpm central:prints`.
- No ar: #599 (Central só leitura), #602 (sem 2FA com login único), #603 (seletor acessível).

## Decisões do Rodrigo (não reabrir)

- **Um material só**, nome neutro **"Plataforma"**, sem marca (nada de Chat2You, Hub2You,
  Autonom.ia ou Chatwoot no texto).
- **A fonte é o repositório** (`lib/central_de_ajuda/<cap>/<id>-<slug>.md`), publicada
  automaticamente nas duas stacks após o deploy, como o seed do Guia. Ninguém edita à mão
  no portal: o editor de portais fecha para todos.
- **Portal da Plataforma:** conta **16** (Hub2You) e conta **1** (Autonomia). Sem domínio
  próprio e sem DNS.
- **Tela de leitura nossa, dentro do painel (23/09).** Substitui a ideia de embutir a página
  pública `/hc/...`. Motivo: a página pública não sabe em que conta a pessoa está, então o
  "Me leve até lá" não tem para onde levar, o destaque não acende, o Guia não abre e o filtro
  do `requer` não se aplica. Os artigos publicados são os mesmos; a página pública continua
  existindo para quem recebe um link.
- **Vídeos curtos de trajeto (23/09).** Substitui o "sem vídeos". Vídeo de 15 a 40 segundos,
  sem voz e sem marca, com legenda e destaque, gravado na conta de teste local e montado no
  estúdio HyperFrames; regerado quando a tela muda. Um storyboard-modelo aprovado uma vez pelo
  Rodrigo vale para todos. O C01-V08 (e-mail, senha, duas etapas) fica fora: mostra a
  verificação em duas etapas, que saiu do produto no #602.
- **"Me leve até lá"** em cada artigo com tela (rota + destaque, como o Guia) e prints só onde
  o botão não basta. Prints e vídeos saem da **conta de teste local** (dados fictícios, recorte
  sem marca), nunca de conta de cliente.
- **Formato do artigo:** O que é, Por que importa, Como faz, O que dá errado, Veja também.
- **Captain fora** (desligado nas 21 contas, conferido em produção). **Agentes de IA da
  Autonomia dentro** (capítulo 11).
- **A Central é da Plataforma.** Não pode chegar ao chat do site, à caixa de resposta
  ("inserir artigo") nem ao Copilot. Quem a usa é o **Guia** (ferramenta `ler_da_central`
  e botão "Ler o artigo completo"). Registrado na #501.
- **Custo:** agentes em **Sonnet 5**. Revisor pode subir para **Opus 5.5** quando o Sonnet
  errar a revisão (autorizado em 23/09). Nunca Opus como padrão.
- **Campo `requer` (22/09):** cada artigo diz o recurso de que depende; a tela de leitura e o
  Guia escondem o artigo das contas que não têm o recurso. Motivo: em produção, Empresas está
  ligado em 2 de 21 contas, Importação em 2, Prospecção em 3, Cotação em 1, Agentes de IA em 14.
- **A Central fica aberta para todas as contas durante a construção (22/09).**
- **Atualização automática (23/09):** a Central segue o Guia. Tela nova sem artigo barra o PR;
  tela removida arquiva o artigo (some para o cliente, fica no histórico); linha de código
  citada que mudou e botão renomeado mandam o artigo para revisão; depois do merge um robô abre
  PR com o rascunho, escrito por chamada direta ao GPT, como o do Guia. Nada entra no ar sem PR
  revisado.

## O que o público pede da tela (evidência das reuniões de implantação)

Tirado das transcrições do Fireflies (setembro/2026), sem dado de cliente:
- Descrevem o menu pela posição ou por letra ("cliquei no A, B, C"); não leem texto pequeno;
  não sabem compartilhar a tela; confundem ChatGPT com chave de API.
- Conectar o primeiro WhatsApp levou de 11 a 17 minutos; o QR Code expirou várias vezes.
- Medo de perder o número ou o histórico em quase toda conexão.
- Um cliente procurou ajuda sozinho antes da reunião e achou a Central vazia.

Consequência para a #501: letra grande com controle A-/A+, "Me leve até lá" com destaque,
vídeo de trajeto no topo, aviso "isso não apaga nada" antes das ações que assustam, e
"Pergunte ao Guia" no fim de cada artigo.

## Próximos passos, em ordem

1. **Capítulo 18** — PR de texto, sem deploy; Rodrigo confirma os pontos marcados.
2. **#502 (código):** publicação automática do repositório para os portais das duas stacks, com
   job lazy versionado por hash (como o seed do Guia), artigo por artigo, arquivando sem apagar.
   Slug com prefixo fixo: o slug de artigo é único no banco inteiro.
3. **#501 (código):** tela de leitura nossa no painel; "Central de Ajuda" na barra lateral leva
   a ela; filtro do `requer` no servidor; bloqueios (esconder os botões de editar, que já não
   funcionam; nenhuma caixa ligada ao portal da Plataforma; Copilot ignorando esse portal); link
   "Docs" do menu do perfil. Depois, o 01.07.
4. **Prints e vídeos:** captura por script na conta de teste local; resolver os CONFIRMAR NA
   TELA na mesma passada.
5. **Atualização automática** da Central (trava, aprendiz, checagem de provas e rótulos).
6. **Issue nova:** o Guia lendo a Central (`ler_da_central` + botão "Ler o artigo completo").
7. **Ligar** nas duas stacks, com o OK do Rodrigo, e conferir numa conta de cada stack.

## Ambiente de teste real local (para prints e para testar o Guia)

Conta **"Corretora Desnorteada"** no banco de dev local (conta 9, com caixas, funis,
times, etiquetas, contatos, conversas e agentes de IA de exemplo). Para rodar:
`SSL_CERT_FILE=/etc/ssl/cert.pem AUTONOMIA_AGENTS_ENABLED=true CRM_KANBAN_ENABLED=true
bundle exec rails runner -e development <script>`. Cada pergunta ao Guia gasta a chave da
OpenAI do Rodrigo: diagnosticar sem modelo primeiro e rodar poucas perguntas.

## Pendências fora da Central

- **Ruleset `trava` no `main`:** ação do Rodrigo (Settings → Rules). Sem isso a trava do
  Guia avisa, mas não impede o merge.
- **Robô que abre PR:** depende do segredo `OPENAI_API_KEY` no GitHub e de "Allow GitHub
  Actions to create and approve pull requests" ligado.
- **O Guia está lento:** 18 a 41 s por resposta em produção. Não dá erro (o limite do job é
  180 s), mas incomoda. Vale uma issue.
- `#493` (convite admin entra como agente) parada: a correção é no SSO, que tem outro dono.
- `#500` (medição de ativação): revisão agendada para 29/09.
