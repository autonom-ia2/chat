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
- mandar mensagem ao cliente, assinada como "Automação", com as variáveis do cliente e do card (nome, valor, etapa);
- avisar alguém da equipe (o responsável, um time ou uma pessoa).

Sem limite de quantidade: o cliente manda quantas mensagens quiser.

**Aceite.**
1. A mensagem chega no WhatsApp do cliente com o nome dele no lugar da variável.
2. Na conversa, a mensagem aparece como enviada por "Automação", não por uma pessoa.
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

## Cinco exemplos complexos que a Automação livre com IA vai permitir

Todos usam só o que as fases acima entregam. Cada um é uma automação que o próprio cliente monta, pelo editor ou pedindo ao Guia.

### 1. Triagem completa do WhatsApp da corretora
**Quando** chega a primeira mensagem de um contato novo:
1. a IA **decide** o assunto: cotação nova, sinistro, segunda via, renovação, reclamação ou nenhum;
2. em cotação, a IA **extrai** o tipo de seguro, a placa ou o CEP e a data de nascimento, e grava no contato;
3. cria o card no funil certo e passa para o corretor daquele ramo;
4. manda ao cliente: "Recebi, Maria. O João, especialista em seguro auto, vai te responder";
5. se faltar dado, a IA **escreve** a pergunta só do que faltou;
6. em reclamação, avisa o gerente na hora, com um **resumo**.

### 2. Recuperar orçamento parado sem parecer robô
**Quando** o card fica 2 dias em "Orçamento enviado":
1. a IA **lê** a conversa e **escreve** uma retomada que cita a dúvida do cliente ("você tinha perguntado da franquia…");
2. o texto sai sozinho; *(se a aprovação humana da F7 for aceita, o corretor pode aprovar com um clique antes)*;
3. **espera até** o cliente responder, com prazo de 3 dias;
4. se ele responde, a IA **decide**: "quer fechar", "quer desconto", "desistiu" ou "outra coisa";
   - "quer fechar": move para Fechamento e avisa o corretor;
   - "quer desconto": cria um retorno para o corretor ligar hoje;
   - "desistiu": marca o card como perdido, com o motivo que a IA tirou da conversa;
5. se não responde: marca como "não fechou — sem resposta".

### 3. Renovação de apólice de ponta a ponta
**30 dias antes** do vencimento gravado no card:
1. move para "Renovação" e manda a mensagem de renovação pelo modelo aprovado do WhatsApp;
2. se a mensagem falhar na entrega e o contato tiver e-mail, manda por e-mail;
3. **espera até** a resposta, com prazo de 10 dias;
4. a IA **extrai** da resposta se houve mudança (carro novo, endereço novo, condutor novo) e atualiza o card;
5. com mudança: cria o retorno "recotar" para o corretor; sem mudança: move para "Renovar igual";
6. 5 dias antes do vencimento, sem resposta: avisa o corretor e o gerente com um **resumo** do histórico.

### 4. Pós-venda que gera indicação
**Quando** o card é ganho:
1. espera 7 dias e manda: "Como foi a experiência, de 0 a 10?";
2. a IA **extrai** a nota e o comentário e grava no contato;
3. nota de 9 ou 10: espera 2 dias e pede indicação, com um texto que a IA **escreve** citando o que o cliente elogiou;
4. nota de 6 ou menos: avisa o gerente com o **resumo** da conversa e cria um retorno urgente;
5. cada indicação que chega com o nome do cliente cria um card novo no funil Comercial, com a origem "indicação de Maria".

### 5. Relatório semanal e integração com outro sistema
**Toda segunda às 8h:**
1. para cada corretor, a IA **resume** a semana: cards novos, ganhos, perdidos e os principais motivos de perda;
2. manda esse resumo ao corretor e ao gerente;
3. os cards ganhos na semana vão pelo **webhook de saída** para a planilha financeira ou o ERP;
4. cards parados há mais de 15 dias ganham a etiqueta "esfriando" e um retorno para o responsável;
5. **quando o responsável de um card muda**, o novo dono recebe o **resumo** da conversa e o que já foi prometido ao cliente.
