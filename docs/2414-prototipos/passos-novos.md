# Protótipo: os 6 passos novos da Automação livre

Issues #2931 a #2936 (épico #2414). Protótipo em tela real, para o Rodrigo
aprovar antes de alguém escrever o motor. Só a tela e um adaptador falso: nada
disso roda de verdade nem é salvo no servidor.

## Como ligar

1. Ligar a flag `automacao_passos_novos` na conta. **A flag ainda não tem bit**
   em `config/features.yml`: a Orquestração precisa reservar a posição antes do
   merge (o código do painel já lê o nome).
2. Abrir **Automações › Montar do zero** (ou uma automação já salva) com quem tem
   `automation_manage`. Escolher qualquer gatilho.
3. Tocar no **+** do Confira. Os 6 passos aparecem misturados aos de hoje, cada
   um no grupo do objetivo dele, com o nome e uma frase embaixo.

Sem a flag, o editor fica idêntico ao de hoje: o catálogo volta o mesmo objeto
do servidor.

## O que é de verdade e o que é falso

| Parte                                                                               | Situação                                                                                             |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Lista "Adicionar passo", nome e frase                                               | De verdade (catálogo do editor, com `requer` da flag)                                                |
| Formulário de cada passo, começar pronto, "Salvar" do painel                        | De verdade, no rascunho da tela                                                                      |
| Galhos no Confira (aprovado, recusado...)                                           | De verdade (`receita.js`, `RAMOS`)                                                                   |
| Linha do ensaio (botão **Ensaiar**)                                                 | Adaptador falso: duas conversas de exemplo, nada é enviado                                           |
| Linha do histórico                                                                  | Exemplo na prévia do painel ("Veja como fica"), até o motor existir                                  |
| Blocos da conta, integrações, resposta do teste, horários livres, contagem da lista | Adaptador falso (`passosNovos/adaptadorFalso.js`)                                                    |
| **Salvar tudo / Guardar / Ligar**                                                   | O servidor recusa: ele ainda não conhece os passos. O painel avisa: "Este passo ainda está em teste" |

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
6. **Ensaiar**: "Pediria aprovação a quem cuida do card. No ensaio, ninguém
   recebe o pedido."

### 2. Fazer para cada um de uma lista (#2932)

1. **+** › grupo **Tempo e condições** › **Fazer para cada um de uma lista**.
2. Já vem com **Os cards de uma etapa** e a primeira etapa escolhida.
3. O quadro mostra **12 entrariam hoje** e os 3 primeiros nomes.
4. Troque para **Os contatos com uma etiqueta**: a primeira etiqueta já vem.
5. **No máximo por vez** (50) e **Ritmo** (aos poucos: um por minuto). Ponha 0
   no máximo para ver o aviso.
6. **Salvar**. No Confira aparece o caminho **Em cada um da lista**; os passos de
   cada um entram pelo **+** dele.
7. **Ensaiar**: "Hoje entrariam 12. Os primeiros: …".

### 3. Usar outra automação (#2933)

1. **+** › grupo **Tempo e condições** › **Usar outra automação**.
2. Três blocos de exemplo, cada um com o que faz em uma frase. O primeiro já vem
   marcado; embaixo, **O que este bloco faz** lista os passos dele.
3. Toque em outro bloco para trocar.
4. **Salvar**. Na prévia, **No histórico**, toque em **Ver o que aconteceu
   dentro** para abrir os passos do bloco.

### 4. Buscar informação em outro sistema (#2934)

Só aparece para quem tem a chave de integrações (`integration_manage`).

1. **+** › grupo **Outro sistema** › **Buscar informação em outro sistema**.
2. **Onde buscar** já vem com **Loja virtual**. Também há **Busca de CEP**,
   **Boletos** e **Outro endereço** (só https; endereço sem https mostra o aviso
   e trava o teste).
3. Toque em **Fazer um teste**. Aparece a resposta, dado por dado.
4. Toque em **pedido status**. Ele vai para **Dados guardados**; troque o nome
   para "Status do pedido".
5. **Salvar**. Em outro passo (uma mensagem, por exemplo), **Pôr um dado** já
   oferece "Status do pedido". No Confira aparece o caminho **Se não conseguir
   buscar**. O endereço nunca aparece no Confira nem no histórico.

### 5. Marcar reunião pela conversa (#2935)

1. **+** › grupo **Mensagens** › **Marcar reunião pela conversa**.
2. Já vem com **Na agenda de quem: Quem cuida do card**, **30 minutos** e o
   convite "Oi! Posso te ligar em um destes horários?".
3. **Como o cliente vê** mostra o balão com os 3 horários em botões, e a nota de
   que vão os números 1, 2 e 3 quando o canal não tem botões.
4. **Esperar a resposta por** (1 dia).
5. **Salvar**. Caminhos **Se pedir outro horário** e **Se o cliente não
   responder**.
6. **Ensaiar**: os 3 horários que ofereceria e o balão.

### 6. Pesquisa de satisfação (#2936)

1. **+** › grupo **Mensagens** › **Pesquisa de satisfação**.
2. Já vem com a pergunta pronta e as faixas 0 a 6, 7 a 8 e 9 a 10.
3. **Como o cliente vê**: a pergunta com os botões de 0 a 10.
4. Mude **A nota baixa vai até** para 7 e **A nota alta começa em** para 8: a
   tela avisa que a nota média ficou vazia.
5. **Perguntar de novo à mesma pessoa só depois de** (30 dias) e **Esperar a
   resposta por** (2 dias).
6. **Salvar**. Caminhos **Nota baixa**, **Nota média**, **Nota alta** e **Se o
   cliente não responder**.

## Telas e tamanhos

Conferir em 390 px e em 1440 px: o painel lateral ocupa a tela no celular; o
pedido de aprovação empilha o card embaixo no celular e põe ao lado no
computador. Todos os botões e escolhas têm 44 px de altura; as escolhas usam o
`ChoiceSelect` (teclado e leitor de tela), sem `<select>`.

## O que fica para a implementação

- Bit da flag em `config/features.yml` (Orquestração).
- O esquema da receita, o salvar, o motor e o ensaio de verdade de cada passo,
  com as regras das Issues: alcance de quem ligou, bloqueados e descadastrados,
  janela de 24 h, trava de horário, proteção contra endereço interno, laço e
  profundidade dos blocos, parecer das funções personalizadas.
- Onde o pedido de aprovação chega de verdade (notificação e painel). Tela nova
  no painel precisa de `porques.md` + `central:check` e `guia:build`.
- Marcar uma automação como bloco (sem gatilho próprio) na lista.
- A linha do histórico de verdade em `LivreHistorico.vue` e o resumo da pesquisa
  na lista.

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
