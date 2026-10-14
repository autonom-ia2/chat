# Multifunil — teste manual na conta 16

Conta **16** (chat.hub2you.ai), funil **Comercial**. Use um celular seu como "cliente" falando com o WhatsApp da
conta, e o painel aberto no computador. Cada parte diz o que fazer e o que você deve ver. Se algo não bater, anote o
número do passo e mande um print.

**Antes de começar**
- Conversa de teste: mande "teste multifunil" do seu celular para o WhatsApp da conta 16. Ela aparece na lista de
  conversas. Use sempre essa conversa.
- No fim, a parte 5 limpa tudo.

---

## Parte 1 — Vários assuntos na mesma conversa (já está no ar)

**Ideia:** um mesmo cliente pode pedir duas coisas. Cada pedido é um card próprio, e a conversa mostra os dois.

1. **Abra a conversa de teste.** No painel da direita, procure o bloco **Assuntos**.
   - Deve aparecer **1 assunto** (o card que a caixa criou sozinha).
2. **Dê nome ao primeiro assunto.** Clique no assunto, abra o card e troque o título para **Agentes de IA**. Salve.
3. **Crie o segundo assunto.** No bloco Assuntos, clique em **Novo assunto**. Funil: **Comercial**. Título:
   **Chat2You**. Confirme.
   - Agora há **2 assuntos**. **Chat2You** aparece como **assunto atual**.
4. **Veja no Kanban.** Abra **CRM → Kanban → Comercial**.
   - Os **dois cards** aparecem, do mesmo contato, cada um com seu título.
5. **Escolha em qual assunto vai a resposta.** Volte à conversa. Acima da caixa de resposta está escrito
   "Este envio fica no assunto: **Chat2You**". Troque para **Agentes de IA** e mande uma mensagem qualquer.
6. **Recarregue a página** (F5).
   - **Agentes de IA** continua como assunto atual, no painel e acima da caixa de resposta.
7. **Olhe a lista de conversas.** O selo da conversa mostra a etapa de **Agentes de IA** e indica que há **2 assuntos**.
8. **Mova só um card.** No Kanban, arraste **Chat2You** para outra etapa.
   - **Agentes de IA** não se mexe.

## Parte 2 — Lead vira cliente (já está no ar)

**Ideia:** fechar uma venda transforma o contato em cliente.

9. **Ganhe uma venda.** No Kanban, abra **Agentes de IA** e marque como **Ganho**.
   - Abra o contato (clique no nome dele na conversa): aparece **"Cliente desde hoje"**.
   - Na conversa, o assunto atual passa a ser **Chat2You** (o ganho saiu de "em andamento").
10. **Desfaça.** Na ficha do contato, clique em **Não é cliente**.
    - Ele volta a lead e **continua aparecendo** em **Contatos**.

## Parte 3 — Acertos (depois do deploy do PR da #1197)

11. **"Conta como venda" salva.** CRM → Kanban → Comercial → **Editar funil → Ajustes**. Anote como está "Fechar com
    sucesso aqui conta como venda", troque, **Salvar**, feche e abra de novo.
    - A troca ficou. **Volte ao valor original** e salve.
12. **Cliente só com nome não some.** Em Contatos, crie um contato só com nome ("Teste cliente"). Abra e clique em
    **Marcar como cliente**.
    - Ele continua na lista de Contatos. Depois apague esse contato.

## Parte 4 — A IA identifica o assunto (depois do deploy do PR da #1145)

**Ideia:** em vez de você criar e nomear os cards, a IA percebe do que o cliente está falando.

13. **Ensine o funil.** Editar funil **Comercial → Ajustes → Quando usar**:
    "Venda dos nossos produtos: Agentes de IA e Chat2You." **Salvar**.
14. **Ligue a IA na caixa.** **CRM → Configurar caixas**, caixa do WhatsApp → **IA identifica o assunto:
    Automática**. **Salvar**.
15. **Comece uma conversa nova** (do celular, um número que não tenha card aberto, ou arquive os cards de teste antes).
    - Mande **"Oi, bom dia"**. Espere **30 segundos**: **nada muda** (cumprimento não é assunto).
16. Mande **"Quero saber dos agentes de IA para o meu atendimento"**. Espere 30 s.
    - O card da conversa passa a se chamar **Agentes de IA** (não nasce outro card).
17. Mande **"E o Chat2You, quanto custa para 5 atendentes?"**. Espere 30 s.
    - Nasce um **2º card, Chat2You**, na primeira etapa do Comercial, e ele vira o **assunto atual**.
18. Mande **"Voltando aos agentes: quero fechar o plano anual"**. Espere 30 s.
    - O assunto atual volta para **Agentes de IA**. Nenhum card novo.
19. **Teste o modo Sugerir.** Volte em Configurar caixas e escolha **Sugerir**. Mande "Vocês fazem site também?".
    - **Nenhum card novo nasce.** (O aviso para confirmar aparece na tela só no próximo PR, o 5b.)
20. **Desligue.** Configurar caixas → **Desligada** → Salvar. Até medirmos o custo, a caixa fica desligada.

## Parte 5 — Limpeza

21. No Kanban, **arquive os cards de teste**. Se o contato de teste virou cliente, clique em **Não é cliente**.
22. Me avise: "teste ok" ou o número do passo que falhou, com print.
