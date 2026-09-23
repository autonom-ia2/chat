# Central de Ajuda "Plataforma": estado para retomar

Última atualização: 22/09/2026. Épico **#485**, onda 2 (Central de Ajuda). Issues **#501**
(tela de leitura, bloqueios) e **#502** (conteúdo). Leia este arquivo primeiro ao voltar.

## Onde estamos

23/09/2026:
- **Exército concluído.** 149 dos 157 artigos escritos em `lib/central_de_ajuda/`, no PR **#607**
  (um commit por lote). Cada capítulo passou por escritor Sonnet 5, três revisores (fatos,
  didática, coerência), rodada de correção e revisão final do editor (checagem por script de
  estrutura, provas `arquivo:linha`, cabeçalho x mapa, links e tamanho; leitura dos densos).
- **Faltam:** 01.07 "Como usar a Central de Ajuda" (depois da tela de leitura, #501) e o
  capítulo 18, escrito com o Rodrigo.
- **CONFIRMAR NA TELA** (resolver com os prints): 06.02, 08.09, 10.05, 10.08, 13.05, 15.01,
  15.02 (textos de tela); 10.07 (depende do capítulo 18); 10.12 (a ajuda do Dataset ID promete
  derivar da conexão do WhatsApp e o código não faz).
- Roteiro de prints: `pnpm central:prints` (5 prints pedidos hoje).
- No ar: #599 (Central só leitura), #602 (sem 2FA com login único), #603 (seletor acessível).

## Decisões do Rodrigo (não reabrir)

- **Um material só**, nome neutro **"Plataforma"**, sem marca (nada de Chat2You, Hub2You,
  Autonom.ia ou Chatwoot no texto).
- **A fonte é o repositório** (`lib/central_de_ajuda/<cap>/<id>-<slug>.md`), publicada
  automaticamente nas duas stacks após o deploy, como o seed do Guia. Ninguém edita à mão
  no portal: o editor de portais fecha para todos.
- **Portal da Plataforma:** conta **16** (Hub2You) e conta **1** (Autonomia). Sem domínio
  próprio e sem DNS: tudo dentro da funcionalidade Central de Ajuda. O cliente **lê dentro
  do painel**, pelas rotas públicas `/hc/:slug/...` com `show_plain_layout=true`.
- **Sem vídeos.** Cada artigo tem o botão **"Me leve até lá"** (rota + destaque, como o
  Guia) e prints só onde o botão não basta. Os prints saem de um **roteiro de captura único
  na conta de teste local** (dados fictícios, recorte sem marca), nunca de conta de cliente.
- **Formato do artigo:** O que é, Por que importa, Como faz, O que dá errado, Veja também
  (herdado do capítulo 1 do playbook de 09/09).
- **Captain fora** (desligado nas 21 contas, conferido em produção). **Agentes de IA da
  Autonomia dentro** (capítulo 11, 12 artigos).
- **A Central é da Plataforma.** Não pode chegar ao chat do site, à caixa de resposta
  ("inserir artigo") nem ao Copilot. Quem a usa é o **Guia** (ferramenta `ler_da_central`
  e botão "Ler o artigo completo"). Registrado na #501.
- **Custo:** todo agente em **Sonnet 5**. Nunca Opus para agente.
- **Campo `requer` (22/09):** cada artigo diz o recurso de que depende; a tela de leitura e o
  Guia escondem o artigo das contas que não têm o recurso. Motivo: em produção, Empresas está
  ligado em 2 de 21 contas, Importação em 2, Prospecção em 3, Cotação em 1, Agentes de IA em 14.
- **A Central fica aberta para todas as contas durante a construção (22/09).** Nada de esconder
  até ficar pronta: o cliente que clicar já vê a Central sendo montada. O que precisa, e antes de
  tudo, é **travar a edição**: hoje o recurso está ligado nas 21 contas e qualquer administrador
  consegue criar portal e artigo.

## Próximos passos, em ordem

1. **Rodrigo lê e aprova o #607** (merge não dispara deploy: só `lib/central_de_ajuda/` e docs).
2. **Capítulo 18 (conceitos)** com o Rodrigo.
3. **#501 (código):** tela de leitura no painel; "Central de Ajuda" na barra lateral leva a ela;
   esconder artigo cujo `requer` a conta não tem; link "Docs" do menu do perfil; bloqueios
   (nenhuma caixa ligada ao portal da Plataforma, Copilot ignorando esse portal). Depois, o 01.07.
4. **#502 (código):** publicação automática do repositório para os portais das duas stacks.
   Slug com prefixo fixo: o slug de artigo é único no banco inteiro.
5. **Prints:** captura por script na conta de teste local, a partir do roteiro; resolver os
   CONFIRMAR NA TELA na mesma passada.
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
- **O Guia está lento:** 18 a 41 s por resposta em produção. Não dá erro (o limite do job é
  180 s), mas incomoda. Vale uma issue.
- `#493` (convite admin entra como agente) parada: a correção é no SSO, que tem outro dono.
- `#500` (medição de ativação): revisão agendada para 29/09.
