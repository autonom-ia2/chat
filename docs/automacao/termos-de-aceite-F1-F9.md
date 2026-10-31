# Automação livre · Termos de aceite das fases F1 a F9

- **Épico:** #2414 · **Base:** ADR-001 (`docs/automacao/ADR-001-motor-de-automacao-livre.md`)
- **Estado:** rascunho para o Rodrigo aprovar, 31/10/2026.
- **Como ler:** cada fase diz o que entrega, como provamos que ficou pronta (aceite) e um exemplo do dia a dia. Uma fase só é aceita quando todos os itens do aceite passam no painel, e nas contas piloto 1, 16 e 18 depois do deploy.

**Regra que vale para todas as fases (Rodrigo, 31/10):** não existe teto de uso. O cliente paga e usa quanto quiser: sem limite de mensagens por conversa, de execuções por hora ou de chamadas de IA. Ficam só as proteções contra defeito: uma automação nunca dispara a si mesma em laço, Spam corta tudo e erro permanente não é repetido sem fim.

---

## F1 · Fundação segura

**O que entrega.** Nada novo na tela. Prepara o terreno para o motor não fazer besteira:
- anti-loop próprio, que não se perde quando o sistema limpa o contexto entre uma ação e outra;
- cada ação feita pela automação fica registrada em nome de quem ligou;
- a mesma contagem de "cascata" vale para os três motores (Regras, etapas do CRM e o novo);
- o Guia só cria ou liga automação para quem tem a permissão de gerenciar automações (PR de autorização, separado);
- quando uma ação move o cliente para uma etapa, o card dele é criado ou atualizado.

**Aceite.**
1. Uma regra que muda a conversa e dispara outra regra que muda a conversa de volta para no segundo passo, e o histórico diz por quê.
2. Uma ação feita pela automação aparece no registro com o nome de quem a ligou, não "sistema".
3. Uma pessoa sem a permissão de gerenciar automações pede ao Guia "cria uma automação" e recebe a resposta de que não tem acesso. Com a permissão, funciona.
4. Mover pela automação um contato que não tem card cria o card na etapa certa, sem duplicar.
5. As regras de hoje das contas 6, 16 e 17 continuam funcionando igual.

**Exemplo.** A Juliana liga a automação "lead novo vai para Rafael". Seis meses depois, no histórico do card, aparece "movido pela automação de Juliana Prado", e não "sistema".

---

## F2 · Onde guardar

**O que entrega.** As 4 tabelas novas (automações, versões, execuções e registros), numa migration sozinha na fila. Ainda nada na tela.

**Aceite.**
1. A migration sobe e desce sem erro numa cópia do banco.
2. Salvar uma automação duas vezes cria a versão 1 e a versão 2; a versão 1 não muda nunca.
3. Uma automação nasce desligada.
4. Os registros com mais de 30 dias são apagados sozinhos.
5. Duas execuções iguais (mesma automação, mesmo cliente, mesmo gatilho) não podem existir ao mesmo tempo.

**Exemplo.** Alguém troca o texto do lembrete de "2 dias" para "3 dias". Quem já estava esperando continua com o texto antigo; quem entrar depois recebe o novo.

---

## F3 · O motor

**O que entrega.** O que de fato roda a automação:
- passos esperar, esperar até, se e parar;
- passo "fazer uma ação da plataforma", liberado pela lista de ações permitidas (allowlist);
- o arquivo que diz quais ações podem virar passo, com o CI cobrando que nenhuma fique sem classificação;
- Spam corta tudo;
- acordar quem está esperando (a cada minuto) e checar os gatilhos de tempo (a cada hora).

**Aceite.**
1. "Quando a conversa for resolvida, espere 1 dia e adicione a etiqueta pós-venda" roda sozinha na conta piloto.
2. Uma ação fora da lista permitida (ex.: apagar usuário) não aparece como passo e é recusada se alguém tentar por fora.
3. A espera sobrevive a um deploy no meio: quem estava esperando continua depois.
4. Desligar a automação no meio de uma espera para tudo; ninguém recebe nada depois.
5. Conversa marcada como Spam não roda nenhum passo.
6. Erro permanente (ex.: etiqueta apagada) para aquele cliente com motivo claro; erro passageiro tenta 3 vezes.
7. Quem perdeu acesso à caixa: a automação pausa e aparece "Assumir e religar".

**Exemplo.** Conversa resolvida numa sexta. No sábado, a conversa ganha a etiqueta "pós-venda" e entra no funil de pós-venda, sem ninguém clicar.

---

## F4 · Falar com pessoas

**O que entrega.** Dois passos novos:
- mandar mensagem ao cliente, com as variáveis do cliente e do card (nome, valor, etapa); o cliente recebe uma mensagem normal da empresa, e só dentro da plataforma ela fica marcada como enviada pela Automação;
- avisar alguém da equipe (o responsável, um time ou uma pessoa).

Sem limite de quantidade: o cliente manda quantas mensagens quiser.

**Aceite.**
1. A mensagem chega no WhatsApp do cliente com o nome dele no lugar da variável.
2. O cliente recebe a mensagem como qualquer mensagem da empresa: nada no texto diz "Automação". A marcação "enviada pela Automação" existe só dentro da plataforma, para a equipe saber de onde veio.
3. Variável vazia (cliente sem nome) pula o passo e o histórico diz "faltou o nome"; nunca sai "Olá, ," para o cliente.
4. Fora da janela de 24 h do WhatsApp, o passo usa o caminho já validado (criar retorno com envio automático do modelo aprovado) ou para com o motivo; nunca falha calado. Mandar modelo direto, fora do follow-up, ainda precisa ser confirmado (risco 6 do ADR).
5. O aviso à equipe chega no sino do responsável com o link da conversa.

**Exemplo.** Orçamento enviado. Dois dias sem resposta: o cliente recebe "Oi, Maria, conseguiu ver a proposta do seguro auto?". Se ele não responde em mais 2 dias, o corretor recebe o aviso "Maria não respondeu à retomada".

---

## F5 · A tela

**O que entrega.** A Automação livre que você aprovou no protótipo, agora de verdade:
- lista única com as automações novas e as antigas;
- editor passo a passo e receitas prontas;
- "Conte o que você quer" (o Guia monta a partir do texto);
- ensaio ("e se acontecesse agora com este cliente?"), sem enviar nada;
- histórico de cada execução;
- o Guia e o editor usam o mesmo catálogo de passos, gerado do código, para nunca ficarem diferentes;
- artigo na Central atualizado.

**Aceite.**
1. Tudo o que o Guia monta abre no editor e pode ser alterado; nada fica travado.
2. Tudo o que o editor oferece, o Guia também sabe montar.
3. O ensaio mostra cada passo com o valor real do cliente escolhido e não envia nada.
4. Ligar uma automação que manda mensagem ou usa IA pede confirmação dizendo isso e o custo.
5. Sem `<select>` nativo; funciona no celular; textos em pt_BR.
6. O CI falha se um passo novo não tiver frase em português ou tela no editor.

**Exemplo.** O dono escreve "quando o lead do anúncio chegar, manda boas-vindas e passa para o Rafael". O Guia mostra a automação pronta, ele clica em "Ensaiar com Maria", vê exatamente o que a Maria receberia, e liga.

---

## F6 · Funil e card

**O que entrega.** Automações que começam no CRM:
- gatilhos: card criado, entrou ou saiu da etapa, ganhou, perdeu, arquivado, campo mudou;
- tempo: "parado há X dias na etapa" e "N dias antes de uma data do card" (ex.: vencimento da apólice);
- retorno: criar retorno com envio automático;
- em Configurar › Editar funil › etapa: "Automações desta etapa", com as antigas (selo "jeito antigo") e as novas;
- no card: "Automações deste cartão", com o que está rodando, o histórico e "Parar para este cartão";
- receitas por tipo de negócio (seguros e saúde e benefícios primeiro).

**Aceite.**
1. Card que fica 3 dias parado em "Orçamento enviado" dispara a automação uma vez, não todo dia.
2. "30 dias antes do vencimento" roda no fuso da conta, no dia certo.
3. "Parar para este cartão" para só aquele card; os outros seguem.
4. Arquivar em massa não dispara "saiu da etapa", e a tela avisa isso.
5. As automações de etapa de hoje continuam funcionando e aparecem no mesmo painel.
6. Só quem pode mexer no funil cria automação de funil.
7. *(Proposta, a aprovar.)* Card movido pela automação não é desfeito pela IA do funil na avaliação seguinte. Hoje a IA só respeita movimento feito por pessoa. Decisão do Rodrigo: ajustar a IA do funil ou só deixar automação mover card em funil com "Mover automaticamente" desligado.
8. Card criado pela automação respeita a trava de 30 dias do "não é negócio": contato arquivado pela IA como fornecedor, engano ou duplicado não ganha card de novo.

**Exemplo.** Corretora: 30 dias antes do vencimento da apólice, o card vai para "Renovação", o cliente recebe a mensagem de renovação e o corretor ganha um retorno para ligar em 5 dias se não houver resposta.

---

## F7 · IA como passo

**O que entrega.** A IA vira peça da automação, usando a chave de IA da própria conta:
- **Decidir:** escolhe entre vários caminhos, com "nenhum se aplica";
- **Extrair:** tira dados da conversa (placa, CPF, data, valor) e grava no contato ou no card;
- **Escrever:** gera um texto personalizado para mandar;
- **Resumir:** resume a conversa para a equipe.

O custo de cada passo aparece na tela e no histórico, sem teto. Os testes com IA paga só rodam com orçamento combinado antes.

**Aceite.**
1. *(Régua proposta, a aprovar.)* Com 20 conversas reais anonimizadas, o Decidir acerta o caminho em pelo menos 18 e usa "nenhum se aplica" quando é o caso, em vez de chutar.
2. O Extrair grava o campo certo; quando o dado não está na conversa, deixa vazio e diz isso, sem inventar.
3. O texto do Escrever passa pelo ensaio antes de ligar. *(Proposta, não está no ADR: opção de exigir aprovação humana antes de enviar.)*
4. O histórico mostra o que a IA decidiu, por quê, e quanto custou.
5. As IAs do CRM de hoje não mudam.

**Exemplo.** O cliente manda "bati o carro ontem, e agora?". A IA decide "sinistro", extrai a placa e a data, cria o card no funil de Sinistros e avisa o time de sinistro com um resumo de 3 linhas.

---

## F8 · Gatilhos extras

**O que entrega.**
- recorrente: todo dia, toda semana, todo mês, no fuso da conta;
- mensagem que falhou na entrega (WhatsApp recusou);
- troca de responsável ou de time;
- reunião marcada, remarcada ou cancelada;
- webhook de saída: mandar dados para outro sistema (planilha, n8n, ERP).

**Aceite.**
1. "Toda segunda às 8h" roda uma vez por segunda, no fuso da conta, mesmo com deploy no domingo.
2. Mensagem que falhou dispara a automação, por exemplo para tentar por e-mail quando o contato tem e-mail.
3. Trocar o responsável de uma conversa dispara o aviso ao novo responsável.
4. O webhook de saída manda os campos escolhidos e mostra no histórico se o outro sistema respondeu.

**Exemplo.** Toda segunda às 8h, cada corretor recebe a lista dos seus cards parados há mais de 7 dias. E quando o WhatsApp recusa uma mensagem de cobrança, ela sai por e-mail e o financeiro é avisado.

---

## F9 · Migrar o antigo

**O que entrega.** Converte as Regras de automação e as automações de etapa do CRM para o motor novo, conta a conta, com o seu OK. Faz backup antes. O antigo é desligado, nunca apagado. Depois de um prazo, fecha a criação de regra nova nos motores antigos.

**Aceite.**
1. Para cada conta, um relatório antes: "estas 26 regras viram estas 26 automações".
2. Depois da conversão, um mês de comportamento igual: as mesmas atribuições e os mesmos retornos.
3. Nenhuma mensagem dupla durante a troca (antigo e novo nunca ligados ao mesmo tempo para a mesma coisa).
4. Reverter uma conta religa o antigo e desliga o novo em minutos.
5. Ao fim, existe um motor só, e a lista mostra tudo nele.

**Exemplo.** As 26 regras "caixa X vai para a dona" da conta 17 viram 26 automações novas. A dona não percebe diferença nenhuma, e passa a ver o histórico de cada atribuição.

---

## Convive com as IAs do CRM, não refaz

Confirmado com o chat Multifunnel em 31/10, na origin/main 2ad360cf5c.

- **Triagem do assunto:** já é da IA de assunto, configurada por caixa. Uma triagem pela Automação livre só roda na caixa com a IA de assunto desligada.
- **Retomar conversa parada:** já é dos Retornos automáticos, por funil. Uma automação que fale com cliente parado só roda no funil com eles desligados.
- **Mover card:** a IA do funil hoje só respeita movimento feito por pessoa. Falta decidir: ajustar a IA para respeitar a automação, ou só deixar a automação mover card em funil com "Mover automaticamente" desligado (item F6.7).
- **As IAs do CRM não mudam de comportamento.** A Automação livre cobre o que nenhuma delas faz.

## Dez automações que nenhuma IA do CRM faz hoje

Cada uma cobre um buraco que as IAs do CRM deixam hoje, conferido no código. Todas usam só o que as fases acima entregam, e o próprio cliente monta cada uma, no editor ou pedindo ao Guia.

### 1. Renovação de apólice de ponta a ponta
**Quando:** 30 dias antes da data de vencimento gravada no card.
**Por que é novo:** Nenhuma IA do CRM lê um campo personalizado de data, como o vencimento da apólice. A cobrança do funil de Atender usa só a data prevista de fechamento.

1. Move o card para “Renovação” e manda a mensagem de renovação pelo modelo aprovado do WhatsApp.
2. Se o WhatsApp recusar a mensagem e o contato tiver e-mail, manda por e-mail.
3. Espera até a resposta, com prazo de 10 dias.
4. A IA **extrai** da resposta se algo mudou (carro novo, endereço, condutor) e atualiza o card.
5. Mudou: cria o retorno “recotar” para o corretor. Não mudou: move para “Renovar igual”.
6. 5 dias antes do vencimento, sem resposta: avisa o corretor e o gerente com um **resumo** do histórico.
*Usa: F4, F6, F7, F8.*

### 2. Reativar quem não fechou há 11 meses
**Quando:** Todo dia 1º do mês.
**Por que é novo:** Só o “adiou” agenda retorno, em até 180 dias. Quem recusou ou fechou com outro nunca mais é procurado.

1. Acha os cards perdidos há 11 meses com o motivo “fechou com outro” ou “achou caro”: o seguro feito em outro lugar está perto de vencer.
2. A IA **lê** o motivo da perda (“achou caro”, “fechou com o banco”) e **escreve** uma oferta que responde a esse motivo.
3. Cria um card novo no funil Comercial, com a origem “reativação”, e manda a mensagem.
4. Cliente respondeu: passa para o corretor que atendeu da primeira vez.
5. Sem resposta em 15 dias: arquiva o card novo, sem mais mensagens.
*Usa: F4, F6, F7, F8.*

### 3. Pós-venda que gera indicação
**Quando:** O card é ganho.
**Por que é novo:** No funil de Vender, o card ganho não recebe nada, e não existe pedido de indicação. O “deu tudo certo?” é só do funil de Atender.

1. Espera 7 dias e pergunta: “Como foi a experiência, de 0 a 10?”.
2. A IA **extrai** a nota e o comentário e grava no contato.
3. Nota 9 ou 10: espera 2 dias e pede indicação, com um texto que a IA **escreve** citando o que o cliente elogiou.
4. Nota 6 ou menos: avisa o gerente com o **resumo** da conversa e cria um retorno urgente.
5. Cada indicação que chega com o nome do cliente vira um card no funil Comercial, com a origem “indicação de Maria”.
*Usa: F3, F4, F6, F7.*

### 4. Documentação que falta para emitir
**Quando:** O card entra na etapa “Documentação”.
**Por que é novo:** O leitor de mídia lê foto e PDF com texto, mas nada confere a lista do que falta para emitir nem cobra só o que falta.

1. Manda ao cliente a lista do que precisa para aquele ramo (ex.: CNH, CRLV, comprovante de endereço).
2. A cada anexo que chega, a IA **extrai** do texto lido qual documento é e se está legível, e marca no card.
3. Faltando algo, a IA **escreve** o pedido só do que falta (“só falta o comprovante de endereço”).
4. Tudo recebido: move para “Emissão” e avisa o corretor.
5. 3 dias sem novo documento: cria um retorno para o corretor ligar.
*Usa: F3, F4, F6, F7.*

### 5. Cliente de alto valor
**Quando:** Card criado ou atualizado com valor acima de R$ 50 mil.
**Por que é novo:** A passagem para a equipe escolhe por caixa, pessoa, rodízio ou quem está online, mas nenhuma regra olha o valor do card.

1. Passa o card para o corretor sênior, em vez do rodízio.
2. Adiciona a etiqueta “alto valor” no contato e na conversa.
3. Aplica a política de SLA de 1 hora.
4. Avisa o gerente com o link do card.
5. Se o card ficar 24 h sem resposta da equipe, avisa o gerente de novo.
*Usa: F3, F4, F6.*

### 6. Mensagem que não chega
**Quando:** O WhatsApp recusa uma mensagem para o cliente.
**Por que é novo:** Só o erro 131047 é reenviado pela API oficial. A mensagem comum que falha fica só no balão, sem aviso e sem outro canal.

1. Contato tem e-mail: manda o mesmo conteúdo por e-mail.
2. Adiciona a etiqueta “número com problema” no contato.
3. Avisa o responsável: “A mensagem para a Maria não chegou. Confira o número”.
4. Na segunda falha seguida, cria um retorno para alguém ligar ao cliente.
*Usa: F4, F8.*

### 7. Troca de responsável sem perder nada
**Quando:** O responsável do card muda (férias, saída, redistribuição).
**Por que é novo:** O resumo por IA só existe como botão no card. O novo dono não recebe nada sozinho, e a nota da passagem não diz o que foi prometido.

1. A IA **resume** a conversa para o novo dono: o que o cliente quer, o que já foi prometido e o próximo passo.
2. Manda ao cliente: “Oi, Maria. A partir de hoje quem te atende é o Rafael, e ele já está a par de tudo”.
3. Passa os retornos abertos do antigo para o novo responsável.
*Usa: F4, F7, F8.*

### 8. Reunião cancelada não some
**Quando:** O cliente cancela ou remarca a reunião.
**Por que é novo:** O pós-reunião só age em “Aconteceu”. Cancelar ou remarcar grava a atividade e avisa o responsável, mas o card fica em “Reunião marcada”.

1. Cancelou: move o card de volta para “Qualificado” e manda o link para escolher outro horário.
2. Remarcou: atualiza a data no card e avisa o responsável.
3. 2 dias sem novo horário: cria um retorno para o responsável ligar.
4. A IA **escreve** ao responsável o contexto da reunião que caiu, para ele não começar do zero.
*Usa: F4, F6, F7, F8.*

### 9. Venda fechada vai para o outro sistema
**Quando:** O card é ganho.
**Por que é novo:** O ganho já vai para a Meta e o Google Ads (Resultados dos anúncios), mas não para ERP, planilha ou outro CRM. Alguém redigita os dados.

1. A IA **extrai** da conversa os dados que faltam no card (CPF, placa, forma de pagamento).
2. Manda os campos escolhidos pelo webhook de saída para a planilha, o n8n ou o ERP.
3. O outro sistema respondeu com erro: avisa o financeiro com o motivo.
4. Deu certo: grava no card o número que o outro sistema devolveu.
*Usa: F6, F7, F8.*

### 10. Relatório semanal de cada corretor
**Quando:** Toda segunda às 8h.
**Por que é novo:** Não existe resumo por pessoa. Só há o resumo diário de anúncios no WhatsApp, por conta.

1. Para cada corretor, a IA **resume** a semana: cards novos, ganhos, perdidos e os principais motivos de perda.
2. Manda o resumo ao corretor e ao gerente.
3. Cards parados há mais de 15 dias ganham a etiqueta “esfriando” e um retorno para o responsável.
*Usa: F4, F6, F7, F8.*
