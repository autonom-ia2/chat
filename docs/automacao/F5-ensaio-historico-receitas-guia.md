# F5, o resto: ensaio, histórico, receitas prontas e o Guia no editor novo

Issue #2498, parte do #2414. Decisão do Rodrigo em 03/11/2026. Base: main c548aec836.

## Ponto de partida

O editor novo (`livre/`, flag `automacao_editor`) já monta, salva e liga uma automação. Faltam quatro peças para ele substituir a tela do motor antigo.

O que já existe e o que se aproveita:

| Peça antiga | O que se aproveita | O que não se aproveita |
|---|---|---|
| `AutomacaoEnsaio.vue` (motor antigo, `AutomationRules::Ensaio`) | O layout: o número grande ("3 de 10"), a lista com as iniciais, "casaria" e "não casaria", o link para a conversa, o `role=status` e o esqueleto de carregamento. | A fonte de dados: ela lê a regra antiga (`conditions` e `actions`), não a receita nova. |
| `AutomacaoConversaPage.vue` | O padrão do Guia embutido (`AutonomiaGuideContainer`), as sugestões de um toque, o pedido inicial vindo da lista e o "recarregar quando o Guia mexeu" (`useCriadasPeloGuia.js`). | Os passos reconhecidos: ela olha `automation_rules`. |
| `modelos.js` com 6 modelos e os textos em `crm.json` `AUTOMACOES.MODELOS` | O título, a explicação e o texto da mensagem. | A forma: o modelo é só um pedido ao Guia, não uma receita. |
| `autonomia.automacao.motivos` (pt_BR/en) | Todas as frases de pulo e de falha do histórico. | — |
| `frases.js` (`fraseDoPasso`, `fraseDaCondicao`) | A frase de cada passo no histórico e no ensaio, igual à do editor. | — |

## As 4 peças, um PR cada, nesta ordem

### PR 1: "O que aconteceu" (histórico)

- **Servidor:** `GET automacoes/:id/historico` devolve as execuções mais recentes, paginadas de 20 em 20, e os registros de cada uma: o passo, o resultado, o motivo e a hora. Não devolve texto da conversa, porque o registro não guarda texto (D8). Também devolve a receita da versão em que cada execução entrou, para a frase do passo sair dela. A permissão é a de ver a automação (`automation_view`).
- **Lista:** cada linha ganha um fato da semana, como "Rodou 12 vezes esta semana · 1 parou". O índice da lista leva duas contagens. Elas vêm de uma consulta agrupada, sem N+1.
- **Tela:** um bloco "O que aconteceu" no editor, abaixo do Confira. Cada execução vira uma linha, "Conversa de Maria · ontem 14:02 · concluída", e abre os passos em frases:
  - "Mandou 'Já vamos te responder'";
  - "Pulou: a conversa está no Spam";
  - "Parou para não repetir em looping".
- **Arquivos:**
  - novos: `app/services/autonomia/automacao/historico.rb` e `livre/components/LivreHistorico.vue`;
  - pequenos: `automacoes_controller.rb`, `definicao_policy.rb`, `config/routes.rb`, `api/autonomia/automacoes.js` e `LivreLinha.vue`;
  - **compartilhados:** `LivreEditorPage.vue` (um bloco) e `automacaoLivre.json` en/pt_BR (o bloco `HISTORICO`).

### PR 2: Ensaiar

- **Servidor, duas rotas:**
  - `POST automacoes/:id/ensaio` (`automation_view`), para a automação salva, com a receita do rascunho no corpo, se houver;
  - `POST automacoes/ensaio` (coleção, mesma permissão `automation_view` e mesma visibilidade, por decisão da Automação), para a nova e a receita aberta, que ainda não têm id, com a receita no corpo.

  As duas só leem. Validam o esquema e a `Receita` antes de andar e dão 422 com os problemas em frase. A conversa escolhida é opcional; sem ela, o ensaio roda nas 10 recentes que a pessoa enxerga (`Contexto.recentes`). O porteiro do Guia só conhece a rota com id, porque o Guia sempre salva antes de ensaiar.
- **`Autonomia::Automacao::Ensaio`, só leitura:**
  - confere os filtros do gatilho com a `Condicao`. Em "mensagem criada", o ensaio usa a última mensagem da conversa;
  - anda o `Roteiro`. Em cada passo, diz o que faria:
    - mensagem: o texto montado pelo `Texto`, para o balão;
    - se: avalia a condição agora, e o ensaio segue pelo ramo que valer;
    - esperar: "esperaria 2 horas", e segue como se o tempo tivesse passado;
    - esperar até: diz o que esperaria, e segue pelos dois caminhos possíveis;
    - ação: a frase do passo;
  - **nunca chama o Executor, as AcoesDoMotor nem o PassoDeMensagem.** Nada grava, manda ou enfileira. Um spec prova isso: depois do ensaio, a contagem de Execucao, Registro, Message e jobs é a mesma.
- **Tela:** o botão "Ensaiar" no editor, ao lado de Ligar. Ele abre o bloco com a lista do jeito do `AutomacaoEnsaio.vue`. Ao tocar numa conversa, aparecem os passos em ordem, e a mensagem sai num balão de celular. Também dá para escolher outra conversa com o `ChoiceSelect` das conversas recentes.
- **Arquivos:**
  - novos: `ensaio.rb` e `LivreEnsaio.vue`;
  - pequenos: os mesmos do PR 1;
  - **compartilhados:** `LivreEditorPage.vue` (um bloco) e `automacaoLivre.json` (o bloco `ENSAIO`).

### PR 3: Receitas prontas

- **Dados:** novo `lib/operator_guide/automacao-receitas.yml`, uma receita por chave, no formato da receita salva, mais o título e o texto em i18n. O spec confere que cada receita passa no esquema e na `Receita`, então uma receita quebrada não chega à tela.
- **Quais entram agora:** só as que o catálogo de hoje monta sem trapaça.
  - **Boas-vindas:** conversa criada → mensagem "Já vamos te responder". Saiu do PR 3 e voltou na #2526 com outro gatilho: mensagem chegou, só se for a primeira da conversa e a conversa foi iniciada pelo cliente (`conversa.iniciada_por`, que trata como da equipe a conversa que nasce de comentário).
  - **Agradecer:** conversa resolvida → mensagem de obrigado.
  - As outras 4 não entram. Dividir em rodízio, Fora do horário, Reclamação e Orçamento pedem passo ou valor que não existe; Reclamação e Orçamento pediriam também a IA entendendo a mensagem, e lista de palavras é proibida. **Decisão pedida (D-R1), abaixo.**
- **Tela:** na lista, "Nova" abre duas portas: "Começar de uma receita" e "Montar do zero". A receita abre o editor já preenchido e desligado (`?receita=BOAS_VINDAS`). Ela só vira automação ao salvar.
- **Arquivos:**
  - novos: `automacao-receitas.yml` e `livre/components/LivreReceitas.vue`;
  - **compartilhados:** `catalogo.rb` (um bloco `receitas` no `Catalogo.todos`), `LivreEditorPage.vue` (um bloco: ler `?receita`) e `automacaoLivre.json` (o bloco `RECEITAS`);
  - `LivreListaPage.vue`.

### PR 4: Montar conversando com o Guia

- **Porteiro:** `PorteiroDaAutomacao` passa a conhecer:
  - `POST autonomia/automacoes`, `PATCH`/`PUT autonomia/automacoes/:id`, com a mesma chave do controller (`automation_manage`). O funil fica com o controller (`sem_funil?`), que já recusa;
  - `POST autonomia/automacoes/:id/ensaio`, com `automation_view`.
  - Ligar e desligar ficam fora do Guia: a automação nasce desligada, e quem liga é a pessoa, no botão. **Decisão pedida (D-G1).**
- **Formatos:** `formatos-das-acoes.json` já tem as 4 rotas. Se o corpo da `receita` não vier descrito, regenero com `autonomia:guia:formatos`.
- **Guia:** o bloco em `porques.md` (`montar_automacao_livre`), com o formato da receita e "sempre desligada"; depois o `guia:build`.
- **Tela:** "Montar conversando" no editor abre o Guia embutido à esquerda, como na `AutomacaoConversaPage`. Quando o Guia salva, o editor recarrega a versão nova. Se houver rascunho não salvo, ele avisa antes, sem salvar por cima. `useCriadasPeloGuia.js` passa a reconhecer `autonomia/automacoes`.
- **Arquivos:**
  - `porteiro_da_automacao.rb`, `porques.md` (gerados junto), `useCriadasPeloGuia.js` e `automacoes.routes.js` (meta `guiaEmbutido` nas rotas livre);
  - **compartilhados:** `LivreEditorPage.vue` (um bloco) e `automacaoLivre.json` (o bloco `GUIA`).

## Em todos

- ChoiceSelect, nunca `<select>`; i18n en e pt_BR; Central 12.06 com uma seção por peça; `porques.md`; e `guia:check`, `central:check`, `guia:formatos:check`, `guia:automacao:check` e `i18n:fork:check`.
- Cada PR tem um banco de teste próprio (`chatwoot_test_2498`), um push só, os pareceres de Funções e da qualidade, a revisão da Automação e o OK do Rodrigo.
- Nos arquivos compartilhados (`catalogo.rb`, `automacao-passos.yml`, `automacaoLivre.json`, `LivreAlterar.vue`, `LivreEditorPage.vue` e `LivreSeletorPasso.vue`), só entram blocos novos e pequenos, na ordem que a Automação definir. `LivreAlterar.vue`, `LivreSeletorPasso.vue` e `automacao-passos.yml` **não são tocados** por nenhum dos 4.

## Correções da qualidade (r1, 03/11): entram antes do código

1. **Guia numa automação ligada (D-G1), regra da Automação até o Rodrigo decidir.** A mudança salva a versão nova e **pausa** a automação, com o aviso para ligar de novo. É a mesma regra de quando outra pessoa salva. Assim o que está no ar não muda sem alguém apertar Ligar. Spec: Guia salva numa ligada → versão nova e `ativa = false`; a tela de quem ligou continua como hoje.
2. **O ensaio respeita a caixa de quem pede.** As 10 recentes e a conversa escolhida saem do mesmo filtro de visibilidade das conversas do agente (o `PermissionFilterService` ou o equivalente usado na lista). Um id fora do escopo dá 404. Spec: um agente sem a caixa não ensaia nela.
3. **O histórico também respeita a caixa.** Execução numa conversa que a pessoa não enxerga aparece como "Uma conversa", sem nome e sem link. Spec.
4. **A receita do rascunho é validada antes de andar.** Esquema e `Receita` rodam antes do `Roteiro`. Inválida dá 422 com os problemas em frase, nunca 500. Spec com id repetido e com ramo malformado.
5. **Só leitura de verdade.** Além da contagem de banco e de jobs, o ensaio:
   - não chama `AntiLaco`, `Cadeia` nem o `dispatcher` de eventos (`expect(...).not_to receive`);
   - deixa as chaves Redis iguais antes e depois;
   - não chama o ActionCable.
6. **A última mensagem segue a régua da Escuta.** O ensaio pula `activity`, e a nota privada conta como `mensagem.tipo = nota`. Sem mensagem elegível, a conversa aparece como "não entraria: a conversa não tem mensagem", nunca 500. Spec dos dois casos.
7. **"Esperar até" vira árvore com dois rótulos,** "se chegar" e "se vencer". Um "se" dentro de um ramo de espera é avaliado agora e diz "hoje entraria…", sem prometer o futuro. Contra defeito, sem teto de uso: a caminhada é limitada pelo tamanho da receita (cada passo visitado uma vez por caminho).
8. **Tipo de passo desconhecido ou caro** (o passo "ia" da F1, ou qualquer tipo novo) aparece só com a frase do catálogo, "faria: <frase>". O ensaio nunca chama modelo pago nem executor. Spec com um tipo inventado.
9. **Card (F6).** `Execucao.alvo` já é polimórfico. O histórico nomeia o card: "Card X na etapa Y". Num gatilho de card, o ensaio recusa em frase: "o ensaio de card chega com os gatilhos de card". Combinar com a F3 antes do código.
10. 🟡 O histórico carrega as versões da página de uma vez (por `versao_id` único), não uma consulta por linha.
11. 🟡 O bloco `receitas` fica isolado no fim do `Catalogo.todos`. O spec das receitas roda contra o catálogo real, então pega um gatilho renomeado pela F3.

## Regras entre frentes (fixadas pela Automação, 03/11)

- **Ensaio por tipo de passo.** O ensaio nunca chama modelo de IA, webhook nem envio. Também não toca Redis `AntiLaco` nem `Cadeia`, não despacha e não publica no Cable. Ele mostra o que faria. "Testar este passo" (pago) é da F1 e fica no painel do passo de IA; no ensaio, o passo de IA pode levar só um atalho para ele.
- **Alvo genérico.** O histórico e o ensaio leem `execucao.alvo` (conversa ou card), nunca `conversation_id` fixo.
- **Visibilidade.** Só aparecem conversas e cards das caixas e funis que quem está vendo enxerga.
- **Alvo: `Autonomia::Automacao::Contexto` (da F3, #2499).** Para cada alvo, expõe `rotulo` (i18n), `link` e `visivel_para?(usuario)`. Também oferece, em lote, `de_varios(alvos, usuario)`, para o histórico paginado não fazer uma consulta por linha, e `recentes(conta:, usuario:, tipo:, limite: 10)`, que dá os candidatos do ensaio. A execução que a pessoa não alcança não aparece. O fato da semana conta todas, sem nome. Webhook no ensaio: "aqui chamaria o webhook", só com o host. Gatilho de tempo não grava nada.
- `receita.rb`: a F1 muda a travessia dos ramos num PR pequeno, que entra antes. Esta frente não toca `receita.rb`. Se precisar, avisa a Automação antes.

### Contrato: como um passo declara o ensaio e o histórico

**Ensaio.** Cada classe de passo responde `self.ensaiar(passo, leitura)` e devolve dados, nunca efeito. `leitura` só lê: o alvo, os valores e a hora. Ela não tem cliente de IA, executor, Redis nem dispatcher. A resposta:

```ruby
{ faria: 'mensagem',              # chave i18n AUTOMACAO_LIVRE.ENSAIO.FARIA.<chave>
  dados: { texto: 'Oi, Maria…' },   # o que a frase usa (só valores para a tela)
  ramos: nil }                      # ou [{ chave: 'entao', rotulo: 'se valer' }, …] para mostrar caminhos
```

- O `Ensaio` despacha por um mapa fechado `tipo → classe`. Tipo fora do mapa (novo ou desconhecido) recebe só `{ faria: 'catalogo' }`, ou seja, "faria: <frase do catálogo>". Passo novo sem `ensaiar` nunca roda nada.
- `se`: avalia agora (`ramos` com o escolhido marcado). `esperar_ate`: devolve os dois ramos, "se chegar" e "se vencer". IA decidir: devolve todos os caminhos com as chaves, "aqui a IA escolheria o caminho". Extrair, escrever e resumir: `ramos: nil`, e `dados` traz os campos e o destino.
- O spec do mapa: todo `tipo` do catálogo tem entrada ou cai no `catalogo` de propósito; um tipo inventado só ganha a frase.

**Histórico.** O registro guarda em `dados` só chaves e ids, nunca texto da conversa. O `Historico` repassa uma lista fechada de chaves:

| chave em `dados` | frase na tela |
|---|---|
| `ramo` | "Seguiu por: <rótulo do caminho>" (ou "Nenhum caminho valeu") |
| `campos: { gravados, ausentes, ja_tinha }` | "Gravou: Nome, CPF · Já tinha: E-mail · Não achou: Placa" (rótulos do catálogo) |
| `mensagem_id` / `nota_id` | link "Ver a mensagem" / "Ver a nota" (só se enxerga a conversa) |
| `ia: { custo_usd, modelo, tokens_entrada, tokens_saida }` | segunda linha pequena: "IA: US$ 0,0021". Modelo e tokens ficam em "Ver detalhes" |

- O custo aparece em US$, no formato pt-BR (`Intl.NumberFormat`), com até 4 casas. Na lista, o fato da semana pode somar: "Rodou 12 vezes · IA US$ 0,03".
- Uma chave fora da lista não aparece na tela: o passo novo declara a frase dela no PR dele.

## Protótipo antes do código

Uma demo `bin/demo` (`2498-f5`), com as flags iguais às de produção, mostra:

- a lista com o fato da semana e as duas portas;
- o editor com Ensaiar (lista, passos e balão);
- O que aconteceu (execução aberta, com um pulo e uma falha);
- uma receita aberta;
- o Guia embutido.

Os dados do protótipo vêm de semente local. Prints em 1440 e 390. Nenhum código de produção antes do OK do Rodrigo.

## Decisões pedidas

- **D-R1, as 4 receitas que o catálogo não monta.**
  - (a) Ficam fora agora, e abro uma Issue para cada passo que falta: rodízio, horário de atendimento e a IA entendendo a mensagem.
  - (b) Aparecem como "Pedir ao Guia", só com o texto do pedido.
  - **Recomendo (a).** Com (b), o Guia prometeria o que o motor novo não sabe fazer, e o resultado seria uma falha silenciosa.
- **D-G1, ligar pelo Guia.**
  - (a) O Guia só monta, e quem liga é a pessoa.
  - (b) O Guia liga com confirmação.
  - **Recomendo (a).** É igual ao "nasce desligada" de hoje, e o botão Ligar já pede a confirmação.
- **D-E1, a lista do ensaio.**
  - (a) As 10 conversas mais recentes que a pessoa enxerga, e a escolha de outra pelo ChoiceSelect.
  - (b) Só as que casam no gatilho.
  - **Recomendo (a).** "Não casaria" também ensina, como no ensaio antigo.

## Decisões fechadas (Rodrigo, 03/11)

- **D-R1 (a):** as 4 receitas que o catálogo não monta ficam fora. Rodízio vai para a #2502 e Fora do horário para a #2503. Reclamação e Orçamento esperam o passo "decidir" da IA (F7, #2500). As receitas que mandam mensagem dependem de `automacao_mensagens`, que está desligada em produção: com ela desligada, a porta mostra a receita com o aviso de que mensagem automática ainda não está ligada, em vez de deixar salvar e recusar.
- **D-G1 (a):** o Guia só monta, e quem liga é a pessoa. Se o Guia muda uma automação ligada, ele salva a versão nova e pausa, com o aviso.
- **D-E1 (a):** o ensaio mostra as 10 conversas mais recentes e deixa escolher outra.

## Ordem dos blocos compartilhados (Automação, 03/11)

- `LivreEditorPage.vue`: o PR 1 (histórico) entra primeiro, e a F3 troca o seletor de gatilho depois, em cima.
- `catalogo.rb`: cada frente num método próprio. O bloco `receitas` não depende de ninguém.
- `automacaoLivre.json`: cada frente na própria chave de topo (`HISTORICO`, `ENSAIO`, `RECEITAS`, `GUIA`).
- `receita.rb` e `executor.rb`: esta frente não toca. A ordem é F3, depois F7.
- Quem entra depois na main traz a main antes do push. `prototipo.js` sai antes do PR.
- "New automation" em pt-BR é corrigido pela F3 (#2499), no PR dela. Se o PR 3 entrar antes, traz a correção da main ou combina com a F3, sem fazer uma segunda correção.

## Qualidade r2 sobre o protótipo (03/11)

- 🟠 **Conta sem mensagem automática:** o aviso aparece na porta (a receita fica desabilitada, com o porquê), no editor (uma faixa) e no ensaio ("Não sairia: a mensagem automática ainda não está ligada nesta conta"). No protótipo, isso se simula com `?sem_mensagens=1`. No PR, vem da flag `automacao_mensagens` da conta.
- 🟠 **Guia numa automação ligada:** o painel avisa "Quando o Guia salvar a mudança, ela pausa até você ligar de novo".
- 🟠 **"Esperar até" no ensaio:** dois caminhos rotulados. "Se chegar a tempo" segue o resto; "Se o prazo vencer" faz o ramo e depois o resto.
- 🟠 **Rota de coleção do ensaio,** acima.
- 🟡 Trocar de conversa pelo ChoiceSelect também rola até os passos no celular. O histórico mostra "Seguiu por: Senão" no "se". A conversa de uma caixa que a pessoa não vê aparece como "Uma conversa", sem nome e sem link.
- 🟡 Automação: com o Guia aberto numa automação ligada, aparece só o aviso do Guia; a faixa "Salvar tudo" some. Entra no PR 4.
- Qualidade r2: LIBERADO para pedir o OK ao Rodrigo. 🟡 que vão para o código:
  - PR 2: com a rota de coleção, uma pessoa sem a caixa recebe 404 na conversa escolhida; uma receita inválida dá 422. As duas coisas ficam provadas em spec.
  - PR 4: com `automacao_mensagens` desligada, o Guia avisa em frase que não monta mensagem, como faz a porta da receita. Isso entra no `porques.md` e num spec. O 422 do controller também vira frase no Guia.
  - PR 3: no print final, conferir que "New automation" já saiu corrigido pela F3.
