# Central de Ajuda "Plataforma": estado para retomar

Última atualização: 22/09/2026. Épico **#485**, onda 2 (Central de Ajuda). Issues **#501**
(tela de leitura, bloqueios) e **#502** (conteúdo). Leia este arquivo primeiro ao voltar.

## Onde estamos

**Fase 0 concluída e aguardando aprovação do Rodrigo**, no PR **#598**, branch
`docs/502-central-fase-0` (worktree `~/dev/worktrees/chat2you/502-central-fase-0`).
O PR é só documentação e não dispara deploy.

Aprovar em #598:
1. `mapa-de-artigos.md` / `.json`: **159 artigos em 19 capítulos**. A prova de cobertura
   está no fim: 126/126 telas, 284/284 assuntos, 11/11 funcionalidades sem tela, 144/159
   com botão.
2. `kit-do-escritor.md`: formato, tom, vocabulário, regra de verdade, prints, checklist.

Apoio, na mesma pasta:
- `estudo/2026-09-08-apuracao.json`: estudo de 08/09 (14 agentes, 284 assuntos, 1.156
  armadilhas, 1.637 evidências de código), recuperado de
  `~/.claude/projects/.../workflows/wf_e6acc683-dbe.json`;
- `pesquisa-central-do-chatwoot.md`;
- `cobertura.md` / `.json`.

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

## Próximos passos, em ordem

1. **Rodrigo aprova o #598** (mapa e kit). Pode pedir ajuste: o `.json` é a fonte, e o
   `.md` descreve.
2. **Exemplo-ouro:** escrever à mão o capítulo **02 Configurações pessoais** (8 artigos),
   com os prints e os botões, reaproveitando o capítulo 1 do playbook de 09/09
   (artefato https://claude.ai/artifact/AEf1koykddcv1R654nrc43, cópia local em
   `~/.claude/projects/-Users-rodrigosilva-dev-projetos-noindex-chat2you/a9e1eafb-5894-4277-af99-55ee38fe4e69/tool-results/artifact-4aca57e3-1788947096-62f3.html`).
   Tudo reconferido no código de hoje. Rodrigo aprova o tom e o formato.
3. **Roteiro de captura de prints** (script, conta de teste local).
4. **Ensaio do exército:** 1 escritor + 3 revisores (fatos no código, didática pelo kit,
   coerência) no capítulo **05 Times**. Comparar com o ouro e ajustar o kit.
5. **Exército:** um escritor Sonnet 5 por capítulo restante, em paralelo, e depois 3
   revisores por capítulo. Por último, a leitura final e PRs por lote.
6. **Capítulo 18 (conceitos)** é escrito com o Rodrigo, não pelo exército.
7. **#501 (código):** configuração do portal da Plataforma; tela de leitura no painel;
   "Central de Ajuda" na barra lateral leva a ela; editor fechado; link "Docs" do menu do
   perfil aponta para ela; **bloqueios** (nenhuma caixa ligada ao portal da Plataforma e
   Copilot ignorando esse portal). Tudo desligado até o conteúdo estar pronto.
8. **#502 (código):** publicação automática do repositório para os portais das duas
   stacks. Slug com prefixo fixo: o slug de artigo é único no banco inteiro.
9. **Issue nova:** o Guia lendo a Central (`ler_da_central` + botão "Ler o artigo completo").
10. **Ligar** nas duas stacks, com o OK do Rodrigo (é configuração de produção), e conferir
    numa conta de cliente de cada stack.

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
