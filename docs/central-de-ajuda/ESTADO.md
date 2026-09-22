# Central de Ajuda "Plataforma": estado para retomar

Última atualização: 22/09/2026. Épico **#485**, onda 2 (Central de Ajuda). Issues **#501**
(tela de leitura, bloqueios) e **#502** (conteúdo). Leia este arquivo primeiro ao voltar.

## Onde estamos

22/09/2026:
- **#598** (mapa de 157 artigos, kit, campo `requer`) e **#600** (capítulo 02, exemplo-ouro
  aprovado pelo Rodrigo) estão no main.
- **#599** no ar: a Central é só leitura para todas as contas (conferido em produção).
- **#602** no ar: sem verificação em duas etapas onde a entrada é pelo login único; runbook
  das chaves em `docs/production-env-secrets.md`. **#603** no ar: seletor acessível no perfil.
- **Ensaio do exército feito no capítulo 05** (7 artigos), neste PR. Mapa corrigido: 5 botões
  apontavam para `settings_home` (fora do escopo). Roteiro de prints: `pnpm central:prints`.

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

1. **Rodrigo lê o capítulo 05** (ensaio) e diz se o exército pode sair.
2. **Exército**, um capítulo por escritor Sonnet 5, em lotes de 3 a 4 capítulos por vez
   (custo e revisão sob controle). Processo validado no ensaio:
   1. escritor lê kit + capítulo 02 + mapa + estudo + `porques.md` e escreve;
   2. três revisores em paralelo: **fatos** (um por artigo, confere cada frase no código),
      **didática** (kit + ouro), **coerência** (mapa, links, outros capítulos);
   3. o mesmo escritor aplica as três revisões numa rodada;
   4. o editor (sessão principal) confere por script e lê os artigos mais densos.
   O revisor de fatos tem de gravar o relatório em arquivo (no ensaio ele não gravou).
3. **Capítulo 18 (conceitos)** é escrito com o Rodrigo, não pelo exército.
4. **Prints:** captura por script na conta de teste local (precisa do painel local no ar),
   a partir de `docs/central-de-ajuda/prints/roteiro.json`.
5. **#501 (código):** tela de leitura no painel; "Central de Ajuda" na barra lateral leva a
   ela; esconder artigo cujo `requer` a conta não tem; link "Docs" do menu do perfil;
   bloqueios (nenhuma caixa ligada ao portal da Plataforma, Copilot ignorando esse portal).
6. **#502 (código):** publicação automática do repositório para os portais das duas stacks.
   Slug com prefixo fixo: o slug de artigo é único no banco inteiro.
7. **Issue nova:** o Guia lendo a Central (`ler_da_central` + botão "Ler o artigo completo").
8. **Ligar** nas duas stacks, com o OK do Rodrigo, e conferir numa conta de cada stack.

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
