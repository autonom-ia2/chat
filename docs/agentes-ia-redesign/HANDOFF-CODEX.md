# Handoff — Redesign de "Agentes de IA" (Chat2You) → Codex

Escrito pela sessão Claude Code em 07/10/2026, para o Codex continuar o trabalho sem perder contexto.
Leia este arquivo inteiro antes de qualquer ação. Depois leia, nesta ordem: `AGENTS.md` (raiz do repo),
`docs/agentes-ia-redesign/PRD.md` §0, §4, §5, §6, §6.6, §7.0, §10 e §11.7–§11.8.

---

## 1. O que é o projeto

A área **Agentes de IA** do Chat2You (fork do Chatwoot, repo `autonom-ia2/chat`, pasta local
`/Users/rodrigosilva/dev/chat2you`) é a única que ainda não passou pelo redesign "premium e simples" das outras áreas
(Automações #982, Campanhas #990, Primeiros passos, Central). O Rodrigo pediu:

1. visual igual ao padrão Chat2You;
2. jornada de criação mais simples, para uma pessoa com pouca familiaridade com tecnologia ("QI 70");
3. todas as telas reimaginadas (lista, criação, painel, conexão de WhatsApp, peças dentro da conversa), com o backend
   que isso exige;
4. **muito cuidado com os agentes em produção** (Clara na conta 16 da stack hub2you, Lia/Agente de Cotação, agente da
   conta 2 da stack autonomia).

## 2. Onde está cada coisa

Tudo está na branch **`docs/agentes-ia-prd`** (worktree `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`),
ainda **sem PR** e **sem Issue**.

| Arquivo | O que é |
|---|---|
| `docs/agentes-ia-redesign/DIAGNOSTICO.md` | Diagnóstico inicial (bugs B1–B12, atritos, diferença visual). Já está na `main`. |
| `docs/agentes-ia-redesign/PRD.md` | **Fonte da verdade.** PRD v9.1 (~1.400 linhas): decisões D1–D35, telas, máquina de estados, BE-00…BE-32, plano de PRs B1…F10, critérios de aceite, contrato de validação em produção, volta, registro de revisão. |
| `docs/agentes-ia-redesign/PRD-agentes.html` | Página de leitura do PRD (gerada). Publicada em https://claude.ai/artifact/7uxXATxV3EzTsVxKrw64V9 |
| `docs/agentes-ia-redesign/mockup/` | **Protótipo navegável aprovado pelo Rodrigo** — é a fonte da verdade visual. |
| `docs/agentes-ia-redesign/mockup/src/*.js`, `src/styles.css` | Fontes do protótipo (dados reais da conta 16 em `data.js`). |
| `docs/agentes-ia-redesign/mockup/build.sh` | Junta as fontes em `mockup/jornada.html` (uma página só). |
| `docs/agentes-ia-redesign/mockup/jornada.html` | Protótipo pronto. Abra no navegador (precisa de internet só para os ícones Lucide). Publicado em https://claude.ai/artifact/NdjZdAnt8uhTa4P2VziyGM (versão 8 + textos de excluir do #1063). |
| `docs/agentes-ia-redesign/validacao-producao-base.md` | Rascunho **não normativo** das consultas (Q1–Q17) e cenários do tester (T01–T31, P0–P5), com 15 pendências obrigatórias. Cada PR parte dele para escrever o seu plano de validação. |
| `docs/agentes-ia-redesign/revisoes/rodada-1..8.md` | Achados das 8 rodadas de revisão do PRD (IDs R1-xx…R8-xx citados no §7.2 do PRD). |
| `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md` | Causas raiz C1–C15 das rodadas que pararam (regra do Rodrigo). **Leia antes de editar o PRD.** |
| `docs/agentes-ia-redesign/tools/` | `prdedit.py` (editar item inteiro do PRD, causa C9), `build_prd_html.py` + `prd_page.css` (gera a página do PRD), `shots.sh` (capturas do protótipo com Chrome headless). |

### Como usar o protótipo

- Abrir: `open docs/agentes-ia-redesign/mockup/jornada.html`.
- Dentro dele: botão **"Todas as telas"** (mapa de todas as telas e estados), **"Ver como"** (pode editar / só pode ver /
  admin da plataforma) e a barra **"Ver esta tela como"** em cada tela (estados: carregando, erro, vazio etc.).
- Editar: mude `mockup/src/*.js` ou `styles.css` e rode `bash docs/agentes-ia-redesign/mockup/build.sh`.
- Conferir visual (obrigatório antes de entregar, regra do Rodrigo): capturas com
  `bash docs/agentes-ia-redesign/tools/shots.sh <pasta_saida> "teste ligue agente-clara-ajustes" 1440 1500` — os nomes
  aceitos são os do `MAP` em `mockup/src/screens-extra.js` (ex.: `lista`, `conte@pensando`, `agente-lia-ajustes`,
  `interno-teste`, `lista#view`). Janela muito alta (> ~3000 px) sai em branco no Chrome headless; não é bug da página.
- Ler as capturas antes de dizer que está pronto. Nunca entregar tela branca.

## 3. O que já está feito

1. **PR #1036 (em produção, `ac6028c00b`)** — bugs B1–B3: pausar/desligar devolve as conversas para a equipe e inativa o
   espelho (`after_update :sync_mirror_bots`), excluir devolve antes de apagar, limpeza de rascunhos só apaga rascunho
   vazio, `insurance_quote` nunca nasce pelo Construtor.
2. **PRD completo** com 8 rodadas de revisão em 4 lentes (produto, técnica, segurança/produção, testes). Convergência:
   60 → 63 → 59 → 46 → 43 → 27 → 28 → 28 achados; altos 16 → 16 → 17 → 9 → 3 → 5 → **0 → 0**. Todos os achados da rodada 8
   foram corrigidos; a rodada 9 **não** rodou.
3. **Protótipo** aprovado pelo Rodrigo ("ficou muito bom. Isso mesmo") e atualizado a cada rodada.
4. **Atualização pelo #1063** (exclusão lógica, Roberto, em produção desde 06/10, `4d79f25612`): PRD §0, D34, D35, BE-14,
   BE-22 (fora), CA-BE-04 e textos de excluir no protótipo. Análise: sem risco para o plano (SoftDelete chama
   `sync_mirror!(operating: false)`, que devolve as conversas como o #1036; `agents_scope` e reaper usam `.kept`).

**Nada do redesign está implementado em código.** Só o #1036 foi para produção.

## 4. O que falta decidir (bloqueia o início)

O Rodrigo ainda **não respondeu** duas perguntas:

1. **As 35 decisões D1–D35** (tabela da §4 do PRD; resumo no topo da página do PRD). Cada uma tem recomendação. Pergunte se
   ele aprova todas as recomendações de uma vez ou quais quer mudar. Atenção às mais sensíveis:
   - **D1** (Testar = caminho da produção; régua de certeza sai),
   - **D10** (UPDATE de tons ao vivo, por psql),
   - **D12/BE-25** e **BE-19** (falhas de segurança abertas hoje em produção — entram no primeiro PR, B1),
   - **D23** (só a tela nova exige teste para ligar),
   - **D35** (PRs do caminho ao vivo sobem sozinhos vs. lote de até 7 da fila nova).
2. **Critério de saída das revisões do PRD.** A recomendação foi: rodar a rodada 9 com a regra "zero altos e zero médios de
   segurança/produção → PRD aceito; o resto vira pendência do PR que toca o assunto". Alternativas: seguir até uma rodada
   voltar vazia (regra literal dele) ou parar agora.

Não comece código antes dessas respostas. Pode, sim, abrir a Issue épica e o PR só de documentação (ver §6).

## 5. Regras do Rodrigo que valem aqui (não negociáveis)

- Responder em português do Brasil, direto, sem jargão; verdade primeiro; não inventar arquitetura, endpoint, comando.
- **Aprovação explícita** antes de: merge, deploy, qualquer coisa em produção, escrita em banco de produção, apagar
  branch remota, secrets, auth, billing, infra, DNS, permissões.
- **Produção só por leitura via psql:** SSM `AWS-RunShellScript` → `docker exec chatwoot-web psql "$DATABASE_URL"` dentro de
  `BEGIN TRANSACTION READ ONLY`. **Nunca** `rails runner`/`rails console` em produção. Stack hub2you usa `--profile hub2you`.
- **Sem regex para interpretar texto de usuário**, e regex não é a escolha padrão nem para o resto (use métodos de string,
  parser, schema). Se achar que não tem alternativa, pergunte ao Rodrigo antes.
- **Nunca encadear teste e commit** (`rspec && git commit`). Rode a validação, leia a saída inteira, depois commite.
  Depois de `rubocop -a`/`eslint --fix`, leia o `git diff` e rode os testes de novo.
- **Construção aditiva no fork:** arquivos próprios, toque mínimo em arquivo do Chatwoot, sem coluna nova em tabela upstream,
  flag para voltar à tela antiga.
- **Sem `<select>` nativo** na UI: use `components-next/choice-select/ChoiceSelect.vue`.
- **Tailwind só com tokens `n-*`**, sem CSS próprio, sem `<style>`, sem `style=""` (exceção: largura de barra).
- **i18n:** en + pt_BR no catálogo do fork (`config/fork_i18n.json`, `pnpm i18n:fork:check`).
- **Guia da Plataforma:** rota/permissão mudou → `pnpm guia:build`; controller/params mudou →
  `bundle exec rails autonomia:guia:formatos`; tela nova sem bloco em `lib/operator_guide/porques.md` não passa no PR.
- **Worktrees** em `/Users/rodrigosilva/dev/worktrees/chat2you/<issue>-<slug>`; nunca `rm -rf`, `git reset --hard`,
  `git clean`; não suprimir stderr do git. Ver `/Users/rodrigosilva/dev/CLAUDE.md` (espelhado em `AGENTS.md`).
- **Revisão:** uma rodada de revisão (4 lentes); se a rodada seguinte tiver achados, **pare, ache a causa raiz, registre em
  `docs/audit/`, corrija a causa e só então mande para nova revisão.** CI verde não é revisão.
- **Tester em produção** para todo deploy que muda comportamento: lista os testes antes com o motivo, afirmação dura,
  tempo-limite é falha, evidência (HTTP, latência, ids, eventos). Contrato no PRD §11.7–§11.8.
- **Conferir visual antes de entregar** (capturas lidas, nada em branco).
- **Qualidade acima de economia de tokens:** nunca cortar validação ou revisão para economizar.

## 6. Fila de merge e deploy (coordenação)

- A sessão **Automação** coordena todo merge e deploy do `autonom-ia2/chat` (decisão do Rodrigo). Ninguém enfileira sem ela
  dar a vez. Pedido de vaga: **nº do PR, OK do Rodrigo (sim/não), CI verde no head atual (sim/não), tem migration (sim/não)**
  e, para PR do caminho ao vivo de agentes, "subir sozinho por rollback" (D35).
- Desde 07/10: lotes de **até 7 PRs sem migration**; PR com migration vai sozinho com snapshot RDS nas 2 contas e rollback
  escrito; urgência sobe sozinha. Depois do deploy: validar e mandar **"ok, SHA"** para a Automação.
- Não mesclar a `main` "para atualizar" (só se `CONFLICTING`). Um push por PR: rode antes, localmente, tudo que a CI barra
  (rspec da área, rubocop, vitest com `TZ=UTC`, lint de e-mail/i18n, `guia:check`). Teste alheio caiu: fechar e reabrir o
  PR (não usar rerun). PR empilhado: só enfileira depois que o de baixo virar MERGED.
- Deploy é blue-green nas 2 stacks (~40 min por deploy). Ler `docs/processo-de-release.md` antes.

## 7. Próximos passos, em ordem

1. **Retomar com o Rodrigo** as duas perguntas da §4 (decisões e critério de saída). Registrar as respostas na §4 do PRD
   (coluna "Recomendação" vira a decisão tomada) e no §15.
2. Se ele escolher a rodada 9: rodar 4 revisores independentes (produto/UX, técnica, segurança/produção, testes), cada achado
   com prova em `arquivo:linha` conferida no código da `origin/main` do dia. Antes de rodar, preencher o registro de
   conferência (§15.1) para o que mudou desde a rodada 8 (o §0/#1063, D34, D35). Salvar em `revisoes/rodada-9.md`.
3. **Issue épica** no `autonom-ia2/chat` ("Redesign de Agentes de IA", linkando PRD e protótipo) e entrada no Project
   Autonom.ia Dev (https://github.com/users/autonom-ia/projects/3) com Projeto, Status, Tipo, Prioridade, Risco, Próxima ação,
   Ambiente. Se faltar scope: `gh auth refresh -s project,read:project`.
4. **PR de documentação** (esta branch): `Refs #<épica>`, corpo no formato do repo (parágrafo do produto, Closes/Refs,
   How to test). Sem código, sem deploy de comportamento. Pedir vaga à Automação como qualquer PR.
5. Depois do OK nas decisões, implementar **na ordem do §10.1**: **B1** primeiro (BE-19 + BE-25 + BE-31 + BE-14 + BE-10,
   BE-21, BE-15, BE-20) — fecha as falhas de segurança abertas. Antes de qualquer código do B1:
   - consulta só leitura "Antes do B1" do §11.7 (agentes que não atendem com espelho ativo);
   - Q12a (chaves de `config` fora da lista) → lista ao Rodrigo;
   - `design/B1.md` com o desenho técnico, uma spec por caso obrigatório do §7.2 e o **plano de validação** (a partir de
     `validacao-producao-base.md`, resolvendo as pendências do escopo, com as respostas 6(a–d) por escrito).
6. Seguir B2 → B3 → B4/B4b/B5/B6a/B6b → F0…F9 conforme dependências do §10.1, cada PR com o fluxo do §10.2 (entender →
   desenho técnico → implementar com teste primeiro → validar local → conferir visual → revisão §10.3 → aceite → fila).

## 8. Armadilhas já conhecidas (não repita)

- **Edição do PRD:** troque o **item inteiro**, nunca linha solta — editar por linha deixou sobras contraditórias duas vezes
  (C9). Use `tools/prdedit.py` (`item_replace`, `row_replace`, `rep` com assert). Depois de editar, procure cada ID mexido
  em todo o documento (passe de consistência, §10.3 passo 5) e preencha o registro de conferência (§15.1, causa C14).
- **Regra por efeito, não por lista** (C11): "invalida o teste toda mudança que altera o que o agente responde ou por onde
  responde" — não enumere casos como fronteira.
- **Validação de produção não é mecânica** (C15): falha dispara classificação (defeito do lote → volta pré-aprovada na hora;
  não é do lote → lista ao Rodrigo; dúvida → volta). Só invariante olha o que mudou **depois da foto**.
- **Altitude** (C7/C13): o PRD fixa comportamento e casos obrigatórios; mecanismo e consulta exata vão para `design/<PR>.md`
  com o código aberto.
- **Volume real em produção é baixo** (05/10: Clara 3 conversas em 7 dias; Lia 29 em 30 dias): comportamento ao vivo se
  prova no tester, não por estatística.
- O `.env` da instância religada pelo rollback é o do primeiro boot (mudar SSM não basta).
- A fila junta PRs: rollback de um degrau desfaz o lote inteiro (D35, §14).
- Agentes agora têm **exclusão lógica** (#1063): toda consulta e escopo novo usa `kept` / `deleted_at IS NULL`.
- O teste do Construtor/Playground é assíncrono (202 + `poll_url`); a recusa de permissão do repo é **401**
  (`Pundit::NotAuthorizedError`).
- Capturas com Chrome headless: largura mínima ~500 px; altura muito grande dá página branca.

## 9. Contatos de produção (referência)

- Stack hub2you: perfil AWS `hub2you`; conta 16 (Hub2you, Clara), conta 27.
- Stack autonomia: credencial em `~/dev/Appsell/credential.env` (nunca imprimir); conta 2.
- Credenciais locais: `/Users/rodrigosilva/dev/claudete-ops/.secrets/credentials.env` — citar só o **nome** da variável,
  nunca o valor.
