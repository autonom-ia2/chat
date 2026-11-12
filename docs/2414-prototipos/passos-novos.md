# Protótipo: os 6 passos novos da Automação livre

Issues #2931 a #2936 (épico #2414). Protótipo em tela real, para o Rodrigo
aprovar antes de alguém escrever o motor. Aprovado em 12/11. Três deles já têm
motor de verdade (#2932, #2933 e #2934, seção "Motor" abaixo); os outros três
(#2931, #2935 e #2936) seguem só na tela, com o adaptador falso, e não salvam.

## Como ligar

1. Ligar a flag `automacao_passos_novos` na conta (no painel local, pelo kit
   `bin/demo`). Ela está no fim da `feature_flags_ext_2` de
   `config/features.yml`; o bit está na seção "Motor" abaixo.
   **Exceção à regra de 07/11** (flag nova nasce ligada em todas): esta fica
   **desligada em produção**, ligada só na conta de demonstração, até o motor
   dos passos existir. Ligada num cliente, ele monta passos que não salvam.
2. Abrir **Automações › Montar do zero** (ou uma automação já salva) com quem tem
   `automation_manage`. Escolher qualquer gatilho.
3. Tocar no **+** do Confira. Os 6 passos aparecem misturados aos de hoje, cada
   um no grupo do objetivo dele, com o nome e uma frase embaixo.

Sem a flag, o editor fica idêntico ao de hoje: o catálogo volta o mesmo objeto
do servidor.

## Os três com motor (#2932, #2933, #2934 — 12/11)

"Fazer para cada um de uma lista", "Usar outra automação" e "Buscar informação
em outro sistema" já são de verdade: esquema, salvar, motor, ensaio e histórico.
Sem o aviso "ainda está em teste": salvam e ligam como qualquer passo. Os outros
três (#2931, #2935, #2936) seguem no protótipo, como descrito abaixo.

- **Flag.** `automacao_passos_novos`, no fim de `config/features.yml`. O bit
  reservado é o 47 (1 << 46), depois de `relacionamentos_novo` e
  `carteira_seguros`; enquanto `carteira_seguros` não entra na `main`, ela cai no
  46 (1 << 45), como `spec/models/account_spec.rb` confere. **Desligada em
  produção** (exceção à regra de 07/11). Desligada depois de ligada: o salvar
  recusa a receita com um dos três e o motor para a execução que chega num deles
  (`passos_novos_desligados`). É o rollback: também não abre as filhas de um
  "para cada" cujo job já estava na fila, e a filha da lista ou a execução do
  bloco que já estavam abertas param na próxima reconferência.
- **Para cada** (`repetir_lista`): cards de uma etapa, contatos de uma etiqueta
  ou de um público salvo. Cada item ganha uma execução própria (a "filha da
  lista") que roda o galho `cada` com o item como alvo, até o teto por vez
  (1 a 200) e no ritmo escolhido (um por minuto, ou todos de uma vez). Bloqueado
  ou descadastrado fica de fora, e só entra quem quem ligou alcança. O item que
  já está no meio desta automação não entra de novo (sem laço). A tela conta
  "entrariam hoje" no servidor, pela mesma régua (`contar_lista`), quando a
  pessoa para de digitar o teto. O alcance é uma pergunta às políticas por item:
  a contagem e a rodada leem no máximo o teto mais 300 itens alcançáveis; o
  resto entra na próxima vez.
- **Bloco** (`usar_bloco`): "Usar como bloco" na lista marca a automação (coluna
  `autonomia_automacoes.bloco`, migration `20261112092000`). O bloco não liga
  sozinho. O passo abre uma execução do bloco no mesmo alvo e espera ela acabar;
  o bloco age como quem ligou a automação de cima. Laço (A usa B, que usa A) e
  bloco dentro de bloco além de 3 níveis são recusados ao salvar e de novo ao
  rodar. O histórico mostra "Ver o que aconteceu dentro".
  - Mudar o bloco **pausa** as automações ligadas que chegam nele (direto ou por
    outro bloco), menos as que a própria pessoa ligou: a mesma regra de quem
    salva uma automação ligada por outra pessoa. Sem isso, quem tem menos
    permissões poria passos no bloco que rodariam com as de quem ligou. A tela
    do bloco avisa antes quais pausam. Alguém assume e religa, e o religar
    confere o bloco com essa pessoa. Aprovado pelo Rodrigo em 12/11.
  - Marcar como bloco tira quem tinha ligado (`ligada_por`): o bloco nunca age
    por ela.
  - Dentro do galho de um "para cada" (ou de um "em outro registro") o bloco
    usado também não pode ter "para cada" nem "em outro registro", nem pelos
    blocos que ele usa: o salvar recusa e a rodada confere de novo. Sem isso, um
    "para cada" abriria outro pelo bloco e as execuções se multiplicariam.
- **Buscar em outro sistema** (`consultar`): uma consulta pronta (veja
  "Consultas prontas" abaixo) ou "Outro endereço". O endereço: só https, só com
  `integration_manage`. Endereço interno é recusado depois de resolver o nome
  (o IP resolvido é o que se usa: sem DNS rebinding). Prazo curto, sem seguir
  redirecionamento, resposta até 64 KB. Os dados guardados têm o nome que a
  pessoa deu (o teste sugere um nome do dia a dia, pela IA da conta ou pelo
  caminho). Nos dois casos, cada dado vira `consulta.<passo>.<chave>` nos passos
  seguintes. Galho "Se não conseguir buscar". O endereço não aparece no Confira
  para quem não tem a chave, nem no histórico; o histórico guarda só os nomes
  dos dados. No ensaio, só busca com "Buscar agora".
- **Loja virtual e Boletos** do protótipo não existem como integração na
  plataforma: ficaram de fora, sem item falso.

### Decisões do Rodrigo (12/11, "resolve!!! foco na jornada e experiência do usuário")

A revisão independente de 12/11 listou cinco pontos em que a implementação fugia
do protótipo. O Rodrigo decidiu:

1. **Onde buscar volta a ser uma lista de consultas prontas.** Cada uma tem um
   nome do dia a dia, diz o que a pessoa informa ("O CEP", com "Pôr um dado") e
   já devolve os dados com rótulo pronto (Rua, Bairro, Cidade…), sem IA e sem
   chave de JSON. Elas reaproveitam as Ferramentas prontas dos agentes (veja
   "Consultas prontas" abaixo). **Outro endereço** fica por último, como
   avançado, só para quem tem `integration_manage`, com tudo o que já valia.
   Loja virtual e Boletos não entraram: não existe integração deles na
   plataforma.
2. **Histórico da busca** continua mostrando só os nomes dos dados, sem o valor
   (privacidade).
3. **Ensaio do bloco** continua mostrando os passos reais do bloco.
4. **"Entrariam hoje"** mostra o total de verdade e os primeiros nomes. Passou
   do teto por vez, diz numa frase quantos ficam para depois: "Hoje entram 50 de
   120. Os outros 70 entram nas próximas vezes." Quando a contagem para no
   limite de leitura (teto + 300), diz "mais de".
5. **Mudar um bloco pausa as automações de outras pessoas** que o usam, e a tela
   avisa antes de salvar. Aprovado.

### Consultas prontas (#2934)

`Autonomia::Automacao::ConsultasProntas` lista as consultas; a busca roda por
`ConsultaPronta`, que usa a mesma `FerramentasProntas::Execucao` do agente, numa
ferramenta não salva (como o "Experimente" da vitrine). Vale tudo o que vale
para o agente: provedores com reserva, cache, o **limite do dia da conta naquela
fonte (500, o mesmo que os agentes gastam)**, o corte individual e o log sem o
valor consultado.

| Consulta | Ferramenta pronta | A pessoa informa | Volta |
| --- | --- | --- | --- |
| Busca de CEP | `cep` / `endereco` | o CEP | Rua, Bairro, Cidade, Estado, CEP |
| Consulta de CNPJ | `cnpj` / `empresa` | o CNPJ | Nome da empresa, Nome fantasia, Situação na Receita, Data de abertura, O que a empresa faz, Porte, Cidade e Estado da empresa |
| Valor do carro (tabela FIPE) | `fipe` / `preco` (tipo carro) | a marca, o modelo e o ano | Valor do carro (em reais), Versão, Ano, Combustível, Mês da tabela |
| Conferir CPF | `cpf` / `conferir` | o CPF | CPF válido (Sim/Não), Estados onde foi emitido |

- **Regras de cada ferramenta.** A consulta aparece só se a conta tem a flag das
  prontas (`agente_ferramentas_prontas`) e, no CPF, a da fase
  (`agente_ferramentas_prontas_consultas`). Sem ela, ou com a fonte cortada pela
  equipe, a consulta continua na lista, travada, com o que falta em linguagem
  leiga. O salvar recusa e o motor segue pelo galho "Se não conseguir buscar".
- **Premium (pagas) não entram nesta fatia.** Uma busca que roda em lote (o
  "para cada" faz até 200 de uma vez) gastaria as grátis do mês e cobraria na
  fatura sem ninguém clicar: precisa de decisão do Rodrigo sobre cobrança antes.
- **Quem monta.** Consulta pronta pede só `automation_manage` (dado público e
  grátis). "Outro endereço" segue pedindo `integration_manage`, ao salvar e ao
  rodar.
- **Receita.** `fonte: { de: 'pronta', consulta: 'cep', entradas: { cep: [texto
  com $valor] } }`; `guardar` traz os dados da consulta com o rótulo pronto. As
  entradas passam pela régua de valores de sempre (`Receita::Leitura`).
- **Teste e ensaio.** "Fazer um teste" busca com um exemplo já preenchido e
  avisa que gasta uma das buscas do dia. No ensaio, o servidor diz o que a
  consulta usaria daquela conversa; com o dado vazio, a tela diz o que falta e
  que seguiria por "Se não conseguir buscar". "Buscar agora" só com o OK.
- **Outro endereço.** O teste avisa antes que a IA da conta sugere os nomes dos
  dados e que esse uso entra no custo da IA da conta.

## O que é de verdade e o que é falso (os três ainda no protótipo)

| Parte                                                                               | Situação                                                                                             |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Lista "Adicionar passo", nome e frase                                               | De verdade (catálogo do editor, com `requer` da flag)                                                |
| Formulário de cada passo, começar pronto, "Salvar" do painel                        | De verdade, no rascunho da tela                                                                      |
| Galhos no Confira (aprovado, recusado...)                                           | De verdade (`receita.js`, `RAMOS`)                                                                   |
| Linha do ensaio (botão **Ensaiar**)                                                 | #2932–#2934: servidor. Os outros três: adaptador falso, com a faixa "Ensaio de exemplo" no topo      |
| Linha do histórico                                                                  | #2932–#2934: servidor. Os outros três: exemplo na prévia do painel ("Veja como fica")                |
| Blocos, públicos, contagem da lista, teste da busca                                 | Servidor (`passosNovos/dadosDaConta.js`)                                                             |
| Horários livres, card do pedido de aprovação                                        | Adaptador falso (`passosNovos/adaptadorFalso.js`)                                                    |
| **Salvar tudo / Guardar / Ligar**                                                   | #2932–#2934 salvam. Os outros três: desligados, com a frase "ainda está em teste"                    |

## Roteiro de cada jornada

Em todas: depois de escolher o passo, o painel **Alterar** abre já preenchido.
Embaixo do formulário fica **Veja como fica**, com a linha do ensaio e a do
histórico. **Salvar** (no pé do painel) põe o passo no Confira. O botão
**Ensaiar** (à direita do Confira) mostra o passo nas conversas de exemplo.

### 1. Pedir aprovação (#2931)

1. **+** › grupo **Equipe** › **Pedir aprovação**.
2. Já vem com **Quem aprova: Quem cuida do card**, a pergunta "Posso seguir com
   este pedido?" e **Prazo para responder: 1 dia**.
3. Em **O que perguntar**, toque em **Pôr um dado** e escolha o valor do card.
   Quem não vê valores não tem esse dado na lista.
4. Toque em **Ver como quem aprova**. Abre o pedido como chega para quem aprova:
   a pergunta grande, o prazo, o card ao lado e os botões **Aprovar** e
   **Recusar**.
   - **Aprovar**: "Você aprovou. A automação seguiu."
   - **Recusar**: pede o motivo (opcional) e **Recusar** de novo para confirmar.
   - Quem não vê valores vê "valor oculto" no texto e o card sem valor.
5. **Fechar**, **Salvar**. No Confira aparecem os caminhos **Se aprovar**,
   **Se recusar** e **Se ninguém responder a tempo**, cada um com o seu **+**.
6. Troque **Quem aprova** para uma pessoa: o Confira passa a dizer "Pedir
   aprovação a Maria Souza: …" (com time, "ao time Vendas").
7. **Ensaiar**: "Pediria aprovação a quem cuida do card. No ensaio, ninguém
   recebe o pedido." O caminho aparece como "Se aprovar:".

### 2. Fazer para cada um de uma lista (#2932)

1. **+** › grupo **Tempo e condições** › **Fazer para cada um de uma lista**.
2. Já vem com **Os cards de uma etapa** e a primeira etapa escolhida.
3. O quadro mostra **12 entram hoje** e os 3 primeiros nomes. Com mais itens
   que o teto, diz embaixo: "Hoje entram 50 de 120. Os outros 70 entram nas
   próximas vezes."
4. Troque para **Os contatos com uma etiqueta** (a primeira etiqueta já vem) e
   para **Os contatos de um público** (o primeiro público de exemplo já vem).
   O Confira diz a lista com o nome: "Para cada card da etapa Proposta, até 50
   por vez".
5. **No máximo por vez** (50) e **Ritmo** (aos poucos: um por minuto). Ponha 0
   no máximo para ver o aviso.
6. **Salvar**. No Confira aparece o caminho **Em cada um da lista**; os passos de
   cada um entram pelo **+** dele.
7. **Ensaiar**: "Hoje entrariam 12. Os primeiros: …" (passou do teto: "Hoje
   entrariam 50 de 120. Os outros 70 entrariam nas próximas vezes. Os
   primeiros: …").

### 3. Usar outra automação (#2933)

1. **+** › grupo **Tempo e condições** › **Usar outra automação**.
2. Três blocos de exemplo, cada um com o que faz em uma frase. O primeiro já vem
   marcado; embaixo, **O que este bloco faz** lista os passos dele.
3. Toque em outro bloco para trocar.
4. **Salvar**. Na prévia, **No histórico**, toque em **Ver o que aconteceu
   dentro** para abrir os passos do bloco.

### 4. Buscar informação em outro sistema (#2934)

Aparece para quem monta automações. "Outro endereço" só para quem tem a chave
de integrações (`integration_manage`).

1. **+** › grupo **Outro sistema** › **Buscar informação em outro sistema**.
2. **Onde buscar** é uma lista de cartões: **Busca de CEP** (já escolhida),
   **Consulta de CNPJ**, **Valor do carro (tabela FIPE)** e **Conferir CPF**,
   cada uma com o selo **Grátis** e uma frase do que faz. A que a conta não pode
   usar fica travada, com o que falta. Por último, **Outro endereço**
   (**Avançado**).
3. Em **O que a busca precisa**, diga de onde vem o CEP: **Pôr um dado em “O
   CEP”** e escolha o dado do contato ou do card.
4. **O que volta da busca** mostra Rua, Bairro, Cidade, Estado e CEP: eles
   aparecem no **Pôr um dado** dos próximos passos.
5. **Fazer um teste**: o exemplo já vem preenchido (01310-100). A tela avisa
   que o teste gasta uma das buscas do dia. Aparece cada dado pelo nome, com o
   valor.
6. **Salvar**. Em outro passo (uma mensagem, por exemplo), **Pôr um dado** já
   oferece "Rua". No Confira: "Buscar na consulta “Busca de CEP”: Rua, Bairro…"
   e o caminho **Se não conseguir buscar**.
7. **Ensaiar**: "Buscaria na consulta “Busca de CEP”." Com o CEP preenchido na
   conversa, **Buscar de verdade neste ensaio** › **Buscar agora** mostra os
   dados. Com o CEP vazio, a tela diz o que falta e que seguiria por "Se não
   conseguir buscar".
8. **Outro endereço** (com a chave): o endereço https, o aviso de que a IA da
   conta sugere os nomes no teste (custo da conta), **Fazer um teste**, o toque
   no dado e o nome dele em **Dados guardados**. O endereço nunca aparece no
   Confira nem no histórico.

### 5. Marcar reunião pela conversa (#2935)

1. **+** › grupo **Mensagens** › **Marcar reunião pela conversa**.
2. Já vem com **Na agenda de quem: Quem cuida do card**, **30 minutos** e o
   convite "Oi! Posso te ligar em um destes horários?".
3. **Como o cliente vê** mostra o balão com os 3 horários em botões, e a nota de
   que vão os números 1, 2 e 3 quando o canal não tem botões.
4. **Se a janela de 24 h estiver fechada**: o modelo aprovado que vai no
   lugar, ou "Não mandar nada (a automação para nesta conversa)", como no passo
   mensagem. A prévia e o ensaio dizem o que sai.
5. **Esperar a resposta por** (1 dia).
6. **Salvar**. Caminhos **Se pedir outro horário** e **Se o cliente não
   responder**.
7. **Ensaiar**: os 3 horários que ofereceria, o balão e o que sai com a janela
   fechada.

### 6. Pesquisa de satisfação (#2936)

1. **+** › grupo **Mensagens** › **Pesquisa de satisfação**.
2. Já vem com a pergunta pronta e as faixas 0 a 6, 7 a 8 e 9 a 10.
3. **Como o cliente vê**: a pergunta com os botões de 0 a 10.
4. Mude **A nota baixa vai até** para 7 e **A nota alta começa em** para 8: a
   tela avisa que a nota média ficou vazia.
5. **Se a janela de 24 h estiver fechada**: o modelo ou nada, como na reunião.
6. **Perguntar de novo à mesma pessoa só depois de** (30 dias) e **Esperar a
   resposta por** (2 dias). O ensaio diz "esperaria a resposta por 2 dias" (ou
   "5 horas", com a unidade certa).
7. **Salvar**. Caminhos **Nota baixa**, **Nota média**, **Nota alta** e **Se o
   cliente não responder**.

## Telas e tamanhos

**Ainda não conferido no navegador.** Antes de mostrar ao Rodrigo, abrir pelo
kit `bin/demo` com a flag e passar pelas 6 jornadas em 390 px e em 1440 px:
o pedido de aprovação (Dialog) aberto por cima do painel lateral, com Tab e Esc
dentro dele; a grade de 6 colunas das notas; as faixas da nota com a escolha
compacta; os balões; e o leitor de tela. O esperado: o painel lateral ocupa a
tela no celular; o pedido empilha o card embaixo no celular e põe ao lado no
computador. Todos os botões e escolhas têm 44 px de altura; as escolhas usam o
`ChoiceSelect` (teclado e leitor de tela), sem `<select>`.

## O que fica para a implementação

- O bit final da flag depende da ordem dos merges (ver "Motor").
- O comportamento do motor com a janela de 24 h fechada na reunião e na
  pesquisa: o protótipo segue o passo mensagem (modelo escolhido ou nada); o
  Rodrigo decide na aprovação da tela.
- O esquema da receita, o salvar, o motor e o ensaio de verdade dos três passos
  sem motor (#2931, #2935, #2936), com as regras das Issues: alcance de quem ligou, bloqueados e descadastrados,
  janela de 24 h, trava de horário, proteção contra endereço interno, laço e
  profundidade dos blocos, parecer das funções personalizadas.
- Onde o pedido de aprovação chega de verdade (notificação e painel). Tela nova
  no painel precisa de `porques.md` + `central:check` e `guia:build`.
- O resumo da pesquisa na lista.

## Arquivos

- `app/javascript/dashboard/routes/dashboard/automacoes/livre/passosNovos/`:
  catálogo, começar pronto e regras (`passosNovos.js`), frases
  (`frasesDosNovos.js`), adaptador falso (`adaptadorFalso.js`) e as telas.
- Ganchos pequenos no editor: `LivreEditorPage.vue` (catálogo com a flag),
  `LivreAlterar.vue` (a peça `passo_novo`), `LivreSeletorPasso.vue` (a frase
  embaixo do nome), `LivreEnsaio.vue` (o ensaio pelo adaptador), `receita.js`
  (os galhos), `catalogo.js`, `frases.js`, `ensaio.js` e `LivrePassos.vue`
  (ícones).
- Textos: `automacaoLivrePassosNovos.json` (en e pt_BR) e os nomes dos caminhos
  em `automacaoLivre.json` (`RAMOS`).
