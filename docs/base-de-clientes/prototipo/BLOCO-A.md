# Protótipo — Bloco A: Relacionamentos (E1, E2, E3)

Especificação de tela para o protótipo de tela real do épico #1240 (Issue #2893). Quem constrói segue este
documento; quem julga (banca) compara a tela com ele. Flag: `relacionamentos_novo`. Dados do protótipo: adaptador
falso, com nomes fictícios e números realistas.

**Regra de ouro:** UI-UX e design premium, com uma jornada tão simples que uma pessoa de QI 70, sem conhecimento de
tecnologia, consegue usar.

## Regras para todas as telas

- Uma frase e uma ação principal por tela. O botão principal é o único preenchido.
- Palavra do dia a dia. Nunca: "segmento", "filtro avançado", "atributo", "importação", "lead", "opt-out", "IA".
  Usamos: "grupo", "informação", "trazer", "pessoa", "não quer mensagens".
- Frases curtas, sem CAIXA ALTA, sem texto que explica como o sistema funciona.
- Tela vazia = uma frase + um botão. Carregando = esqueleto. Erro = "Não consegui …. Tente de novo." + botão.
- Em 390 px vira uma coluna; nada rola para o lado, a não ser a fila de grupos. Alvo de toque de 44 px.
- Teclado e leitor de tela em tudo. Gaveta e diálogo prendem o foco e fecham com Esc.
- Sem `<select>` nativo (`ChoiceSelect`). Telefone com `CampoDeTelefone`.
- Visual no padrão novo da casa: herói escuro `#0D2344`, cartões brancos de canto arredondado, muito respiro.
- Textos no catálogo do fork, `pt_BR` e `en` juntos. Nenhuma palavra de seguro neste bloco.

## Tela 1 — Relacionamentos (abre na lista)

O menu "Relacionamentos" abre direto aqui. Não existe mais a página de três cartões.

De cima para baixo:

1. **Herói escuro** com a frase do dia e um botão. A frase é escolhida nesta ordem:
   - sem ninguém na conta → "Traga as pessoas com quem você já fala." · botão **Trazer minha lista**;
   - há quem sumiu há 1 a 3 meses → "42 pessoas não falam com você há mais de um mês." · **Ver quem sumiu**;
   - senão → "Você tem 280 pessoas aqui. 120 já são clientes." · **Ver clientes**.
   No canto do herói, botão discreto **Trazer minha lista** (quando não é o principal).
2. **Abas:** Pessoas · Empresas.
3. **Grupos**, em pílulas com o número de cada um. A selecionada fica preenchida. Embaixo, uma linha diz o que é o
   grupo.

   | Grupo | Linha de explicação |
   |---|---|
   | Todos | Todo mundo que está aqui. |
   | Clientes | Quem já comprou de você. |
   | Falou há pouco | Quem conversou com você nos últimos 30 dias. |
   | Sumiu há 1 a 3 meses | Quem conversava e parou. Boa hora para chamar. |
   | Sumiu há mais de 3 meses | Quem não aparece faz tempo. |
   | Nunca conversou | Quem está aqui e ainda não falou com você. |
   | Não quer mensagens | Quem pediu para não receber. Ninguém daqui recebe campanha. |

4. **Busca** "Buscar por nome, telefone ou documento". Ao lado: **Ordenar** (Última conversa · Nome · Mais novos) e
   **Mais filtros**, que abre uma gaveta (Empresa, Etiqueta, Cidade, Chegou em).
5. **Lista.** Uma pessoa por linha: caixa de marcar · foto ou iniciais · nome · selo **Cliente** · selo **Não quer
   mensagens** quando for o caso. Segunda linha: telefone · empresa · "Falou há 3 dias" ou "Nunca conversou". Passando
   o mouse: botão **Conversar**. Clicar na linha abre a ficha.
6. **Mostrar mais** no fim (carrega mais 25).
7. **Barra de ação em grupo**, que aparece embaixo ao marcar alguém: "12 marcadas" · **Mandar mensagem** (principal) ·
   **Criar cards** · **Etiqueta** · mais (Apagar). Link "Marcar todas as 42 deste grupo".

**Mandar mensagem** (grupo): folha de confirmação — "12 pessoas vão receber. 2 ficam de fora: 1 pediu para não
receber, 1 está sem telefone." · **Continuar** leva à criação da campanha já com esse grupo.

**Criar cards**: diálogo com duas perguntas — "Em qual funil?" e "Em qual etapa?" (a primeira já vem escolhida) ·
**Criar 12 cards**. Depois: "12 cards criados." e, se alguém ficou de fora, a lista com o motivo em palavras simples.

**Estados:** conta vazia ("Ainda não tem ninguém aqui." + **Trazer minha lista**) · grupo vazio ("Ninguém neste grupo
agora.") · busca sem resultado ("Não achei ninguém com “…”." + **Limpar busca**) · carregando · erro.

**Aba Empresas:** mesmo desenho. Grupos: Todas · Com clientes · Sem pessoas · Sem conversa há 3 meses. Linha: marca ou
iniciais · nome · "3 pessoas" · selo **Cliente** se alguma pessoa dela é cliente · última conversa.

## Tela 2 — Ficha da pessoa

Responde primeiro "quem é e o que tem comigo". Editar é um passo a mais, de propósito.

**Cabeçalho (cartão):** foto · nome · selo **Cliente desde mar. de 2024** (ou botão discreto "Marcar como cliente") ·
telefone com copiar · e-mail · empresa (leva à ficha dela) · etiquetas.
Ações: **Conversar** (principal) · **Novo card** · **Lembrete** · "⋯" (Alterar informações · Juntar com outra pessoa ·
Bloquear · Apagar).

**Faixa âmbar**, só quando pediu para parar: "Pediu para não receber mensagens em 12/09. Veio de: resposta a uma
campanha." · **Liberar** (só aparece nas origens que hoje já permitem).

**Coluna principal:**
- **Conversas:** as 3 últimas (canal, trecho, quando, situação) · **Ver todas**. Vazio: "Ainda não conversaram." +
  **Conversar**.
- **Cards:** título · funil e etapa · valor · situação. Clicar abre o card numa gaveta, com **Abrir no CRM**. Vazio:
  "Nenhum card ainda." + **Novo card**.
- **Notas:** caixa "Escreva uma nota" e a lista.
- **Arquivos:** o que foi trocado nas conversas.

**Coluna do lado:**
- **Informações:** lista "nome da informação: valor" — Telefone, E-mail, CPF, Cidade, Empresa e as informações criadas
  pela conta. O que falta mostra "Não informado". Um botão **Alterar** abre a gaveta com o formulário (o único editor).
  Redes sociais só aparecem quando preenchidas; no formulário ficam recolhidas.
- **De onde veio:** "Veio da lista “Clientes 2025”, em 03/11" ou "Chegou pelo WhatsApp em 12/08".

Em 390 px: cabeçalho, faixa, Conversas, Cards, Informações, Notas, Arquivos, De onde veio.

**Ficha da empresa:** cabeçalho (nome, CNPJ com copiar, site) · **Pessoas** dela · Conversas · Cards · Informações.

## Tela 3 — Trazer minha lista

Uma entrada só, no lugar das quatro de hoje. Etapas no topo: **Enviar → Conferir → Pronto**.

**Enviar.** Título "Traga sua lista. A gente organiza." · área "Arraste a planilha aqui ou clique para escolher" ·
"Excel ou CSV. Precisa ter nome e telefone ou e-mail." Enquanto lê: "Lendo sua planilha…".

**Perguntas, uma por tela, só quando precisa:**
- "Essas pessoas já são suas clientes?" — **Sim, todas** · **Ainda não** · **Algumas** (aí: "Qual coluna diz quem é
  cliente?").
- Quando uma coluna de telefone é duvidosa: "A coluna “Fone 2” é telefone de quem?" — **Da pessoa** · **Da empresa** ·
  **Não usar**.
Cada pergunta tem **Continuar** e **Voltar**.

**Conferir.** Frase: "Achei 200 pessoas. 180 são novas, 15 já estavam aqui e vão ser completadas, 5 precisam de você."
- Três fichas de exemplo, como vão ficar.
- **Precisam de você (5):** cada linha com o problema em palavras simples e o conserto ali mesmo — "Linha 14: falta
  um número no telefone" + campo para corrigir + **Deixar de fora**.
- **O que vou guardar:** cada coluna da planilha e para onde vai ("Cel" → Telefone), com **Trocar**. Coluna que não
  conhecemos vira uma informação da pessoa com o nome da coluna; dá para escolher **Não guardar**.
- "Você pode desfazer por 7 dias."
- Botão **Trazer 195 pessoas**.

**Pronto.** "195 pessoas chegaram." · **Ver as pessoas** · **Trazer outra lista**. Em lista grande, enquanto trabalha:
"Trazendo… 40%. Pode fechar esta tela; eu aviso quando terminar."

**O que eu já trouxe** (histórico, abaixo ou em aba): arquivo · quando · quem · "195 pessoas" · situação (Pronto ·
Trazendo 40% · Desfeito) · **Desfazer** com "até 18/11".
Desfazer abre um diálogo que mostra antes o que sai: "Isto tira 180 pessoas que vieram nesta lista e devolve 15 ao
que eram antes. As conversas que já aconteceram ficam." Se alguém já recebeu campanha: "3 pessoas já receberam uma
campanha. A mensagem enviada não volta." · **Desfazer** · **Cancelar**.

## Dados do protótipo

Conta fictícia com 280 pessoas e 38 empresas, nomes inventados, distribuídas nos grupos com os números acima. Uma
planilha de exemplo de 200 linhas com 5 problemas. `?demo=vazio` mostra a conta sem ninguém.

## O que a banca julga

A régua de 10 itens do plano (seção "Banca dos mockups"), nas três jornadas: achar um grupo e mandar mensagem; abrir
uma pessoa e conversar; trazer uma planilha e desfazer.
