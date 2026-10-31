# Automação livre · Termos de aceite das fases F1 a F9

- **Épico:** #2414 · **Base:** ADR-001 (`docs/automacao/ADR-001-motor-de-automacao-livre.md`)
- **Página:** `docs/automacao/termos-de-aceite.html` (gerada dos mesmos dados; mudou aqui, mude lá).
- **Estado:** rascunho para o Rodrigo aprovar, 31/10/2026.
- **Como ler:** cada fase diz o que entrega, como provamos que ficou pronta (aceite) e um exemplo do dia a dia. Uma fase só é aceita quando todos os itens do aceite passam no painel, e nas contas piloto 1, 16 e 18 depois do deploy. Cada item tem código (ex.: F3.4) para o PR citar.

**Regra que vale para todas as fases (Rodrigo, 31/10):** não existe teto de uso. O cliente paga e usa quanto quiser: sem limite de mensagens por conversa, de execuções por hora ou de chamadas de IA. Ficam só as proteções contra defeito: uma automação nunca dispara a si mesma em laço, Spam corta tudo e erro permanente não é repetido sem fim.

---

## F1 · Fundação segura

**O que entrega.**
- Anti-loop próprio, que não se perde quando o sistema limpa o contexto entre uma ação e outra.
- Cada ação feita pela automação fica registrada em nome de quem a ligou.
- A mesma contagem de cascata vale para os três motores: Regras, etapas do CRM e o novo.
- O Guia só cria ou liga automação para quem tem a permissão de gerenciar automações (PR de autorização, separado).
- Quando uma ação move o cliente para uma etapa, o card dele é criado ou atualizado.

**Aceite.**
1. **F1.1** Uma regra que muda a conversa e dispara outra regra que a muda de volta para no segundo passo, e o histórico diz por quê.
2. **F1.2** Uma ação feita pela automação aparece no registro com o nome de quem a ligou, não “sistema”.
3. **F1.3** Uma pessoa sem a permissão de gerenciar automações pede ao Guia “cria uma automação” e ouve que não tem acesso. Com a permissão, funciona.
4. **F1.4** Mover pela automação um contato sem card cria o card na etapa certa, sem duplicar.
5. **F1.5** As regras de hoje das contas 6, 16 e 17 continuam funcionando igual.

**Exemplo.** A Juliana liga a automação “lead novo vai para o Rafael”. Seis meses depois, o histórico do card mostra “movido pela automação de Juliana Prado”, e não “sistema”.

---

## F2 · Onde guardar

**O que entrega.**
- As 4 tabelas novas: automações, versões, execuções e registros.
- Uma migration, sozinha na fila.

**Aceite.**
1. **F2.1** A migration sobe e desce sem erro numa cópia do banco.
2. **F2.2** Salvar uma automação duas vezes cria a versão 1 e a versão 2; a versão 1 nunca muda.
3. **F2.3** Toda automação nasce desligada.
4. **F2.4** Os registros com mais de 30 dias são apagados sozinhos.
5. **F2.5** Não podem existir duas execuções iguais ao mesmo tempo (mesma automação, mesmo cliente, mesmo gatilho).

**Exemplo.** Alguém troca o lembrete de “2 dias” para “3 dias”. Quem já estava esperando segue com o texto antigo; quem entrar depois recebe o novo.

---

## F3 · O motor

**O que entrega.**
- Passos esperar, esperar até, se e parar.
- Passo “fazer uma ação da plataforma”, liberado pela lista de ações permitidas.
- O arquivo que diz quais ações podem virar passo, com o CI cobrando que nenhuma fique sem classificação.
- Spam corta tudo.
- Acordar quem está esperando, a cada minuto, e checar os gatilhos de tempo, a cada hora.

**Aceite.**
1. **F3.1** “Quando a conversa for resolvida, espere 1 dia e adicione a etiqueta pós-venda” roda sozinha na conta piloto.
2. **F3.2** Uma ação fora da lista permitida (ex.: apagar usuário) não aparece como passo e é recusada se alguém tentar por fora.
3. **F3.3** A espera sobrevive a um deploy no meio: quem estava esperando continua depois.
4. **F3.4** Desligar a automação no meio de uma espera para tudo; ninguém recebe nada depois.
5. **F3.5** Conversa marcada como Spam não roda nenhum passo.
6. **F3.6** Erro permanente (ex.: etiqueta apagada) para aquele cliente com motivo claro; erro passageiro tenta 3 vezes.
7. **F3.7** Quem ligou perdeu acesso à caixa: a automação pausa e aparece “Assumir e religar”.
8. **F3.8** A automação cria e altera configuração da conta (etiqueta, atributo do card, contato, empresa ou conversa, etapa, atribuição, agente na caixa). Cada mudança aparece no histórico e pode ser desfeita, como no Guia.
9. **F3.9** Apagar funil, etapa, caixa, agente, etiqueta ou atributo não vira passo: fica só no Guia, com confirmação.

**Exemplo.** Conversa resolvida numa sexta. No sábado ela ganha a etiqueta “pós-venda” e entra no funil de pós-venda, sem ninguém clicar.

---

## F4 · Falar com pessoas

**O que entrega.**
- Mandar mensagem ao cliente, com as variáveis do cliente e do card (nome, valor, etapa). O cliente recebe uma mensagem normal da empresa; só dentro da plataforma ela fica marcada como enviada pela Automação.
- Avisar alguém da equipe: o responsável, um time ou uma pessoa.
- Sem limite de quantidade: o cliente manda quantas mensagens quiser.

**Aceite.**
1. **F4.1** A mensagem chega no WhatsApp do cliente com o nome dele no lugar da variável.
2. **F4.2** O cliente recebe a mensagem como qualquer mensagem da empresa: nada no texto diz “Automação”. A marcação “enviada pela Automação” existe só dentro da plataforma, para a equipe saber de onde veio.
3. **F4.3** Variável vazia (cliente sem nome) pula o passo e o histórico diz “faltou o nome”; nunca sai “Olá, ,” para o cliente.
4. **F4.4** Fora da janela de 24 h do WhatsApp, o passo usa o caminho já validado (retorno com envio automático do modelo aprovado) ou para com o motivo; nunca falha calado. Mandar o modelo direto, fora do follow-up, ainda precisa ser confirmado (risco 6 do ADR).
5. **F4.5** O aviso à equipe chega no sino do responsável, com o link da conversa.

**Exemplo.** Orçamento enviado. Dois dias sem resposta: o cliente recebe “Oi, Maria, conseguiu ver a proposta do seguro auto?”. Mais 2 dias sem resposta, e o corretor recebe “Maria não respondeu à retomada”.

---

## F5 · A tela

**O que entrega.**
- A Automação livre aprovada no protótipo da F0, agora de verdade.
- Lista única com as automações novas e as antigas.
- Editor passo a passo e receitas prontas.
- “Conte o que você quer”: o Guia monta a partir do texto.
- Ensaio (“e se acontecesse agora com este cliente?”), sem enviar nada.
- Histórico de cada execução.
- Guia e editor usam o mesmo catálogo de passos, gerado do código, para nunca ficarem diferentes.
- Artigo da Central atualizado.

**Aceite.**
1. **F5.1** Tudo o que o Guia monta abre no editor e pode ser alterado; nada fica travado.
2. **F5.2** Tudo o que o editor oferece, o Guia também sabe montar.
3. **F5.3** O ensaio mostra cada passo com o valor real do cliente escolhido e não envia nada.
4. **F5.4** Ligar uma automação que manda mensagem ou usa IA pede confirmação, dizendo isso e o custo.
5. **F5.5** Sem  nativo, funciona no celular, textos em português.
6. **F5.6** O CI falha se um passo novo não tiver frase em português ou tela no editor.

**Exemplo.** O dono escreve “quando o lead do anúncio chegar, manda boas-vindas e passa para o Rafael”. O Guia mostra a automação pronta, ele clica em “Ensaiar com Maria”, vê exatamente o que a Maria receberia, e liga.

---

## F6 · Funil e card

**O que entrega.**
- Gatilhos do card: criado, entrou ou saiu da etapa, ganhou, perdeu, arquivado, campo mudou.
- Tempo: “parado há X dias na etapa” e “N dias antes de uma data do card ou do contato” (ex.: vencimento da apólice, aniversário).
- Retorno: criar retorno com envio automático.
- Em Configurar › Editar funil › etapa: “Automações desta etapa”, com as antigas (selo “jeito antigo”) e as novas.
- No card: “Automações deste cartão”, com o que está rodando, o histórico e “Parar para este cartão”.
- Receitas por tipo de negócio, começando por seguros e saúde e benefícios.

**Aceite.**
1. **F6.1** Card parado 3 dias em “Orçamento enviado” dispara a automação uma vez, não todo dia.
2. **F6.2** “30 dias antes do vencimento” roda no fuso da conta, no dia certo.
3. **F6.3** “Parar para este cartão” para só aquele card; os outros seguem.
4. **F6.4** Arquivar em massa não dispara “saiu da etapa”, e a tela avisa isso.
5. **F6.5** As automações de etapa de hoje continuam funcionando e aparecem no mesmo painel.
6. **F6.6** Só quem pode mexer no funil cria automação de funil.
7. **F6.7** Card movido pela automação não é desfeito pela IA do funil na avaliação seguinte, mesmo com “Mover automaticamente” ligado. Decidido em 31/10: a IA do funil passa a respeitar o movimento da automação como respeita o de uma pessoa. O ajuste é um PR separado do Multifunnel (Issue #2428), com spec, antes do F6, e conserta também as regras antigas que movem card. A automação grava a origem do movimento (“automação”, com o id) para a IA do funil saber quem moveu.
8. **F6.8** Card criado pela automação respeita a trava de 30 dias do “não é negócio”: contato arquivado pela IA como fornecedor, engano ou duplicado não ganha card de novo.

**Exemplo.** Corretora: 30 dias antes do vencimento da apólice, o card vai para “Renovação”, o cliente recebe a mensagem de renovação e o corretor ganha um retorno para ligar em 5 dias, se não houver resposta.

---

## F7 · IA como passo

**O que entrega.**
- Decidir: escolhe entre vários caminhos, com “nenhum se aplica”.
- Extrair: tira dados da conversa (placa, CPF, data, valor) e grava no contato ou no card.
- Escrever: gera um texto personalizado para mandar.
- Resumir: resume a conversa para a equipe.
- Usa a chave de IA da própria conta. O custo aparece na tela e no histórico, sem teto.
- Testes com IA paga só rodam com orçamento combinado antes.

**Aceite.**
1. **F7.1** *(Proposta, a aprovar.)*  Com 20 conversas reais anonimizadas, o Decidir acerta o caminho em pelo menos 18 e usa “nenhum se aplica” quando é o caso, em vez de chutar.
2. **F7.2** O Extrair grava o campo certo; quando o dado não está na conversa, deixa vazio e diz isso, sem inventar.
3. **F7.3** O texto do Escrever passa pelo ensaio antes de ligar. *(Proposta, a aprovar.)*  Opção de exigir aprovação humana antes de enviar.
4. **F7.4** O histórico mostra o que a IA decidiu, por quê e quanto custou.
5. **F7.5** As IAs do CRM de hoje não mudam.

**Exemplo.** O cliente manda “bati o carro ontem, e agora?”. A IA decide “sinistro”, extrai a placa e a data, cria o card no funil de Sinistros e avisa o time de sinistro com um resumo de 3 linhas.

---

## F8 · Gatilhos extras

**O que entrega.**
- Recorrente: todo dia, toda semana, todo mês, no fuso da conta, agindo em cada card ou contato que atende a um filtro (ex.: perdidos há 11 meses com o motivo “fechou com outro”).
- Etiqueta posta ou tirada da conversa ou do contato.
- Mensagem que falhou na entrega (o WhatsApp recusou).
- Troca de responsável ou de time.
- Reunião marcada, remarcada ou cancelada.
- Webhook de saída: mandar dados para outro sistema (planilha, n8n, ERP) e usar a resposta dele nos passos seguintes.

**Aceite.**
1. **F8.1** “Toda segunda às 8h” roda uma vez por segunda, no fuso da conta, mesmo com deploy no domingo.
2. **F8.2** Mensagem que falhou dispara a automação, por exemplo para tentar por e-mail quando o contato tem e-mail.
3. **F8.3** Trocar o responsável de uma conversa dispara o aviso ao novo responsável.
4. **F8.4** O webhook de saída manda os campos escolhidos e mostra no histórico se o outro sistema respondeu.
5. **F8.5** Um valor da resposta do outro sistema (ex.: número da proposta) pode ser gravado no card, e a recusa vira caminho “deu erro” com o motivo.
6. **F8.6** O recorrente com filtro age em cada card ou contato que atende ao filtro naquele dia, uma vez cada.
7. **F8.7** Pôr ou tirar uma etiqueta dispara a automação, e o “se” consegue perguntar se o contato tem uma etiqueta.

**Exemplo.** Toda segunda às 8h, cada corretor recebe a lista dos seus cards parados há mais de 7 dias. E quando o WhatsApp recusa uma mensagem de cobrança, ela sai por e-mail e o financeiro é avisado.

---

## F9 · Migrar o antigo

**O que entrega.**
- Converte as Regras de automação e as automações de etapa do CRM para o motor novo, conta a conta, com o OK do Rodrigo.
- Backup antes. O antigo é desligado, nunca apagado.
- Depois de um prazo, fecha a criação de regra nova nos motores antigos.

**Aceite.**
1. **F9.1** Para cada conta, um relatório antes: “estas 26 regras viram estas 26 automações”.
2. **F9.2** Depois da conversão, um mês de comportamento igual: as mesmas atribuições e os mesmos retornos.
3. **F9.3** Nenhuma mensagem dupla durante a troca: antigo e novo nunca ligados ao mesmo tempo para a mesma coisa.
4. **F9.4** Reverter uma conta religa o antigo e desliga o novo em minutos.
5. **F9.5** Ao fim, existe um motor só, e a lista mostra tudo nele.
6. **F9.6** Fechamento do épico: os 20 exemplos desta página rodam de ponta a ponta no ambiente de testes, montados do jeito que o dono montaria, cada um com teste automático que confere o resultado prometido.
7. **F9.7** Nesse teste, o que sai para fora (WhatsApp oficial e Híbrido, Instagram, e-mail, webhook para outro sistema) é chamado de verdade, com o mesmo pedido que iria para produção, num receptor de teste que grava a chamada. O teste confere o destino, o modelo aprovado e os campos.
8. **F9.8** As esperas de dias e meses rodam com o relógio adiantado, e os passos de IA rodam uma vez com a IA de verdade, com orçamento combinado antes. Exemplo que não passar volta para a fase que falhou; o épico só fecha com os 20 passando.

**Exemplo.** As 26 regras “caixa X vai para a dona” da conta 17 viram 26 automações novas. A dona não percebe diferença nenhuma, e passa a ver o histórico de cada atribuição.

---

## Convive com as IAs do CRM, não refaz

Confirmado com o chat Multifunnel em 31/10, na origin/main 2ad360cf5c.

- **Triagem do assunto:** já é da IA de assunto, configurada por caixa. Uma triagem pela Automação livre só roda na caixa com a IA de assunto desligada.
- **Retomar conversa parada:** já é dos Retornos automáticos, por funil. Uma automação que fale com cliente parado só roda no funil com eles desligados.
- **Mover card:** a IA do funil hoje só respeita movimento feito por pessoa. Decidido: a IA do funil passa a respeitar o card movido pela automação, num PR do Multifunnel antes do F6 (item F6.7).
- **As IAs do CRM não mudam de comportamento.** A Automação livre cobre o que nenhuma delas faz.

## 20 automações que nenhuma IA do CRM faz hoje

Cada exemplo começa pelo pedido como o dono do negócio fala, sem termo técnico. O Guia transforma o pedido na automação, e a pessoa confere no ensaio antes de ligar. Todos cobrem um buraco que as IAs do CRM deixam hoje e usam só o que as fases acima entregam. "Pelo modelo aprovado" = mensagem fora da janela de 24 h do WhatsApp.

Cada ação vale quando o recurso estiver marcado como passo na lista de ações permitidas (F3). Aplicar SLA a uma conversa ainda não tem ação no catálogo do Guia e entra como passo nativo.

### 1. Renovação do seguro sem esquecer ninguém · Corretora de seguros

> "Quando faltar um mês pro seguro do cliente vencer, o sistema chama ele. Se ele trocou de carro, me avisa. Se não responder, manda ele marcar um horário comigo."  
> — Marcos, corretor

**Começa quando:** Faltam 30 dias para o vencimento da apólice, gravado no card.

1. Move o card para “Renovação” e põe a etiqueta “renovação”.
2. Manda a mensagem de renovação pelo modelo aprovado do WhatsApp, com o nome do cliente e o carro.
3. Se o WhatsApp recusar e o cliente tiver e-mail, manda por e-mail.
4. Espera a resposta, por até 7 dias.
5. A IA **extrai** da resposta se mudou carro, endereço ou condutor, e atualiza o card.
6. A IA **decide**: “mudou algo”, “quer renovar igual”, “quer cancelar” ou “nenhum desses”.
7. Mudou algo: cria o retorno “recotar” para o Marcos, para hoje.
8. Quer renovar igual: move para “Renovar igual” e avisa o Marcos.
9. Quer cancelar: avisa o Marcos com um **resumo** da conversa e cria retorno para ligar.
10. Sem resposta em 7 dias: manda, pelo modelo aprovado, o link da agenda do Marcos para 15 minutos de conversa.
11. Reunião marcada: move para “Reunião marcada”. Reunião cancelada: manda o link de novo.
12. Faltando 5 dias e ainda sem resposta: avisa o Marcos com um **resumo** de tudo o que foi tentado.

**Resultado:** Toda manhã o Marcos abre o CRM e a coluna “Renovação” já está separada: quem mudou de carro tem retorno para hoje, quem quer renovar igual está pronto, quem sumiu recebeu o link da agenda, e os 5 dias finais chegam com o resumo pronto. Nenhuma apólice vence sem ser procurada.

**Por que é novo:** Nenhuma IA do CRM lê um campo de data como o vencimento da apólice, nem junta mensagem, agenda e retorno numa sequência só.

*Páginas: CRM, Modelos do WhatsApp, Agendamento, Etiquetas, E-mail · Usa: F4, F6, F7, F8.*

### 2. Lead do anúncio atendido em 5 minutos · Imobiliária

> "O povo preenche o formulário do anúncio e quando eu ligo já esfriou. Quero que alguém fale com ele na hora e, se ele quiser ver o apartamento, já marque a visita."  
> — Márcio, dono da imobiliária

**Começa quando:** Card criado pelo formulário de um anúncio.

1. Põe no contato a etiqueta com o nome do anúncio.
2. Manda pelo modelo aprovado do WhatsApp: “Oi, Ana! Vi que você se interessou pelo apartamento do Jardim. Posso te ajudar?”.
3. Espera a resposta, por até 2 horas.
4. Sem resposta: cria um retorno para o corretor responsável por esse anúncio ligar ainda hoje.
5. Respondeu: passa a conversa para a Sofia, a agente de IA da imobiliária, que tira dúvidas de preço, vaga e condomínio.
6. A cada resposta da Ana, a IA **decide**: “quer visitar”, “quer outro imóvel”, “só curiosidade” ou “ainda conversando”.
7. Quer visitar: manda o link da agenda do corretor do anúncio.
8. Visita marcada: move o card para “Visita marcada” e avisa o corretor com um **resumo** do que a Ana perguntou à Sofia.
9. Quer outro imóvel: a IA **extrai** bairro, quartos e valor, grava no card e cria retorno para o corretor mandar opções.
10. Só curiosidade: põe a etiqueta “frio” e coloca a Ana na campanha mensal de lançamentos.

**Resultado:** O Márcio não liga mais para lead frio. Quando o corretor chega na visita, o card já diz o que a Ana perguntou, quanto pode pagar e qual apartamento quer ver.

**Por que é novo:** Hoje o lead do formulário vira card e para aí. Nada junta o primeiro contato, a agente de IA e a agenda do corretor.

**Convive:** A agente de IA responde do jeito de sempre. A automação só decide quando passar a conversa para ela e o que fazer com a resposta.

*Páginas: Anúncios, CRM, Agentes, Agendamento, Etiquetas · Usa: F3, F4, F6, F7, F8.*

### 3. Pós-procedimento da clínica · Clínica de estética

> "Depois que a cliente faz o procedimento, eu queria mandar os cuidados, saber se ficou tudo bem e lembrar ela da manutenção. Se der alguma reação, eu tenho que saber na hora."  
> — Dra. Patrícia, dona da clínica

**Começa quando:** O card entra na etapa “Atendida” (o pós-reunião da agenda já move quando a reunião acontece).

1. A IA **extrai** da agenda e da conversa qual procedimento foi feito (botox, limpeza, preenchimento) e grava no card.
2. No dia seguinte, a IA **escreve** os cuidados certos daquele procedimento e manda pelo modelo aprovado “Cuidados”.
3. No 3º dia pergunta, pelo modelo aprovado: “Como você está? Pode mandar uma foto se quiser”.
4. A IA **decide** a resposta: “tudo bem”, “vermelhidão ou dor” ou “dúvida”.
5. Vermelhidão ou dor: põe a etiqueta “atenção”, marca a conversa como prioridade e avisa a Dra. Patrícia na hora.
6. Dúvida: cria retorno para a recepção responder ainda hoje.
7. Tudo bem: põe a etiqueta “satisfeita”.
8. No 25º dia, manda pelo modelo aprovado o link da agenda para a manutenção.
9. Sem agendar em 7 dias: coloca a cliente na campanha de e-mail “Manutenção” da clínica.
10. Agendou: move o card para “Retorno marcado” e tira da campanha.

**Resultado:** Nenhuma reação passa sem a doutora saber no mesmo dia, e a agenda de manutenção enche sozinha: quem não marcou recebe a campanha, e quem marcou já aparece no CRM.

**Por que é novo:** O pós-reunião de hoje só move o card. Nenhuma IA acompanha a cliente nos dias seguintes nem reconhece uma reação.

**Convive:** Começa depois do pós-reunião da agenda, que continua movendo o card.

*Páginas: Agendamento, CRM, Etiquetas, Campanhas, E-mail · Usa: F4, F6, F7, F8.*

### 4. Aluno que começa a faltar · Escola de idiomas

> "Quando o aluno falta duas aulas no mês ele acaba desistindo. Quero saber antes e tentar segurar ele."  
> — Rogério, coordenador da escola

**Começa quando:** A recepção arrasta o card do aluno para “Faltou”.

1. Se o aluno ainda não tem a etiqueta “faltou 1x”: põe a etiqueta, manda “Sentimos sua falta! Quer remarcar?” com o link da agenda e, 30 dias depois, tira a etiqueta. Para aqui.
2. Se já tinha: troca para a etiqueta “risco de sair” e cria um card no quadro “Retenção”.
3. A IA **escreve** uma pergunta carinhosa sobre o motivo das faltas e manda pelo modelo aprovado.
4. A resposta vai para a Clara, a agente de IA da escola, que continua a conversa.
5. A IA **decide** o motivo: “horário”, “dinheiro”, “dificuldade” ou “mudou de cidade”.
6. Horário: manda o link da agenda com as turmas de outros horários.
7. Dinheiro: avisa o Rogério com um **resumo** e cria retorno para oferecer uma condição.
8. Dificuldade: manda o link da agenda do professor para uma aula de reforço.
9. Mudou de cidade: oferece a turma online e põe a etiqueta “online”.
10. Espera 30 dias. Se nesse tempo não entrou de novo em “Faltou”, tira as etiquetas de risco e fecha o card de retenção como resolvido.

**Resultado:** O Rogério tem uma coluna “Retenção” com os alunos em risco antes de eles cancelarem, e já sabe o motivo de cada um.

**Por que é novo:** Nada no sistema conta faltas nem cria trabalho de retenção. A automação usa a própria etiqueta como contador.

*Páginas: Agendamento, Etiquetas, CRM, Agentes · Usa: F3, F4, F6, F7, F8.*

### 5. Revisão do carro no tempo certo · Oficina mecânica

> "Cliente que fez revisão aqui some. Quero lembrar ele da próxima revisão e já deixar marcado. Se ele enrolar, oferece uma lavagem de graça."  
> — Seu Zé, dono da oficina

**Começa quando:** Card do serviço marcado como ganho.

1. A IA **extrai** da conversa e da nota do mecânico o carro, a placa, a quilometragem e o que ficou para a próxima vez.
2. Grava tudo no contato e escreve uma nota: “Na próxima: trocar pastilhas”.
3. Grava no card a data da próxima revisão: 6 meses depois.
4. 15 dias antes dessa data, a IA **escreve** o lembrete citando o que ficou para a próxima vez, e manda pelo modelo aprovado com o link da agenda.
5. Marcou: move para “Revisão marcada” e põe a etiqueta “cliente fiel”.
6. Não marcou em 5 dias: manda de novo pelo modelo aprovado, oferecendo a lavagem grátis.
7. Não marcou de novo em 5 dias: cria retorno para o Seu Zé ligar.
8. Revisão marcada e cancelada: manda o link da agenda de novo no dia seguinte.

**Resultado:** O cliente volta sozinho a cada 6 meses, lembrado do que o mecânico anotou. O Seu Zé só liga para quem ignorou duas mensagens.

**Por que é novo:** Nenhuma IA do CRM grava uma data futura e volta a falar com o cliente meses depois de um card ganho.

*Páginas: CRM, Agendamento, Modelos do WhatsApp, Etiquetas, Contatos · Usa: F4, F6, F7, F8.*

### 6. Aniversário que vira horário marcado · Salão de beleza

> "No aniversário da cliente eu quero mandar um parabéns com um mimo e ela já marcar o horário. Se ela vier, quero uma foto pro Instagram."  
> — Jéssica, dona do salão

**Começa quando:** É o dia do aniversário gravado no contato.

1. A IA **escreve** um parabéns no jeito do salão, citando o último serviço que ela fez.
2. Manda pelo modelo aprovado “Aniversário”, com o presente: hidratação grátis este mês, e o link da agenda.
3. Põe a etiqueta “aniversariante do mês” e cria um card no quadro “Aniversário”.
4. A IA **decide** a resposta: “vai marcar”, “agradeceu” ou “não pode este mês”.
5. Não pode este mês: estende o presente para o mês seguinte e grava a nova data no card.
6. Marcou: avisa a profissional e grava no card “hidratação de presente”.
7. Não marcou em 10 dias: lembra uma vez, pelo modelo aprovado.
8. Atendida: no dia seguinte pede, pelo modelo aprovado, uma foto do resultado e autorização para postar.
9. A IA **extrai** se ela autorizou. Autorizou: põe a etiqueta “pode postar” e avisa a Jéssica.
10. Fim do mês sem marcar (ou fim do mês seguinte, se ela adiou): fecha o card e coloca a cliente na campanha “Saudade”.

**Resultado:** Todo mês as aniversariantes recebem o parabéns no dia certo. A Jéssica vê quem marcou, quem adiou para o mês seguinte e quais clientes já autorizaram foto para o Instagram.

**Por que é novo:** Nenhuma IA lê a data de nascimento do contato. Hoje isso é feito à mão ou não é feito.

*Páginas: Contatos, Agendamento, Etiquetas, Campanhas, CRM · Usa: F4, F6, F7, F8.*

### 7. Black Friday para os clientes antigos primeiro · Loja de roupas

> "Quero que quem já comprou comigo veja a promoção um dia antes de todo mundo. Quem só perguntar, a moça do robô responde. Quem pedir pra não receber, nunca mais recebe."  
> — Vanessa, dona da loja

**Começa quando:** Quinta-feira antes da Black Friday, às 9h.

1. Monta a campanha de WhatsApp para quem tem a etiqueta “já comprou” e manda o modelo aprovado “Pré-Black”.
2. Na sexta às 8h, monta a mesma campanha para todos os outros contatos.
3. Cada resposta à campanha: a IA **decide** “quer comprar”, “só dúvida” ou “não quer receber”.
4. Quer comprar: a IA **extrai** peça, cor e tamanho e grava no card, para a vendedora já saber o que separar.
5. Só dúvida: põe a etiqueta “perguntou na Black” e passa a conversa para a Bia, agente de IA, que sabe preço, tamanho e entrega.
6. Não quer receber: confirma “Pronto, você não recebe mais promoções”, põe a etiqueta “não enviar campanha” e tira a pessoa de todas as campanhas.
7. Domingo às 18h: quem tem a etiqueta “perguntou na Black” e não comprou recebe a campanha “Últimas horas”.
8. Card ganho: põe a etiqueta “comprou na Black 2026” e “já comprou”.

**Resultado:** Na sexta de manhã as vendedoras já sabem a peça e o tamanho de quem quer comprar. As dúvidas ficaram com a Bia, quem pediu para sair nunca mais recebe nada, e no domingo só quem demonstrou interesse recebe a última chamada.

**Por que é novo:** A campanha manda e para aí. Nada lê a resposta, separa quem quer comprar de quem só pergunta ou tira de vez quem pediu para sair.

**Convive:** O card de quem quer comprar continua sendo criado pela IA de assunto e distribuído pela passagem para a equipe. A automação só completa o card e cuida de quem não vai comprar.

*Páginas: Campanhas, Etiquetas, Agentes, CRM, Contatos · Usa: F3, F4, F6, F7, F8.*

### 8. Funcionário novo no plano da empresa · Corretora de saúde e benefícios

> "O RH da empresa cliente me manda os funcionários novos pelo WhatsApp. Quero que cada um vire um pedido e que o sistema peça os documentos de cada um."  
> — Luciana, corretora de planos empresariais

**Começa quando:** Duas automações encadeadas. A primeira começa com a mensagem do RH; a segunda com cada card que a primeira cria.

1. 1ª automação · A IA **decide** se a mensagem do RH é uma lista de inclusão. Se não for, para.
2. A IA **extrai** nome, data de nascimento e telefone de cada funcionário, da mensagem ou da foto da lista.
3. Importa os contatos de uma vez, ligados à empresa, pela mesma importação da tela Contatos, e cria um card para cada um no quadro “Inclusão de vidas”.
4. Responde ao RH: “Recebi os 4 nomes. Já vou pedir os documentos a cada um”.
5. 2ª automação, para cada card novo · Manda ao funcionário, pelo modelo aprovado, a lista de documentos (RG, CPF, comprovante).
6. A cada documento que chega, a IA **extrai** qual é e marca no card.
7. Faltando algo em 3 dias: a IA **escreve** o pedido só do que falta.
8. Card completo: move para “Enviar à operadora” e manda os dados para o sistema da operadora.
9. Toda sexta, para cada empresa com inclusão aberta, avisa o RH quem ainda não mandou documento.

**Resultado:** O RH manda uma lista e esquece. A Luciana vê uma coluna com cada vida nova e o que falta de cada uma. As completas já seguiram para a operadora.

**Por que é novo:** Hoje uma mensagem gera no máximo um card. Nada transforma uma lista em vários contatos e cards, nem cobra documento de cada pessoa.

*Páginas: Contatos, Empresas, CRM, Etiquetas, E-mail · Usa: F3, F4, F6, F7, F8.*

### 9. Prospecção que roda sozinha toda semana · Escritório de contabilidade

> "Quero achar empresas novas da minha cidade toda semana, mandar uma apresentação e só falar com quem tiver interesse."  
> — André, sócio do escritório

**Começa quando:** Toda segunda às 8h.

1. Roda a busca salva “Empresas abertas este mês em Campinas”.
2. Usa a conferência de WhatsApp da própria prospecção e descarta quem não tem.
3. Cria um card para cada empresa no quadro “Prospecção”, com a etiqueta “prospecção novembro”.
4. Monta a campanha com o modelo aprovado “Apresentação do escritório” e manda.
5. Cada resposta: a IA **decide** “interesse”, “já tem contador” ou “não quer contato”.
6. Interesse: manda o link da agenda do André para uma conversa de 20 minutos.
7. Já tem contador: põe a etiqueta “tem contador” e cria retorno para daqui a 6 meses.
8. Não quer contato: registra a recusa na prospecção, e a empresa nunca mais recebe nada.
9. Reunião marcada: move para “Reunião” e avisa o André com um **resumo** da empresa.
10. Reunião cancelada: manda o link de novo. Cancelou duas vezes: põe a etiqueta “frio”.

**Resultado:** Toda segunda o André recebe empresas novas sem fazer nada. Ele só aparece na reunião com quem pediu, e quem recusou fica protegido para sempre.

**Por que é novo:** A prospecção hoje é feita à mão, busca por busca. Nada encadeia busca, campanha, triagem da resposta e agenda.

*Páginas: Prospecção, Campanhas, CRM, Etiquetas, Agendamento · Usa: F3, F4, F6, F7, F8.*

### 10. Cliente bravo vai direto para a gerente · Qualquer empresa com equipe

> "Se um cliente estiver muito bravo, eu quero saber na hora e tirar ele da mão do robô."  
> — Fernanda, gerente de atendimento

**Começa quando:** Toda mensagem do cliente, em qualquer canal.

1. A IA **decide**: “reclamação séria”, “irritado” ou “normal”. Normal: para aqui.
2. Reclamação séria: tira a conversa da agente de IA e passa para a Fernanda.
3. Marca a conversa como prioridade e põe a etiqueta “reclamação”.
4. A IA **resume** o problema em 3 linhas para a Fernanda, com o que já foi prometido ao cliente.
5. Manda ao cliente: “Entendi, Paulo. A Fernanda, gerente, já está vendo seu caso”.
6. Espera a Fernanda responder, por até 30 minutos. Sem resposta: avisa o dono da empresa com o mesmo resumo.
7. Irritado: põe a etiqueta “atenção” e avisa o responsável, sem tirar da agente.
8. Conversa resolvida com a etiqueta “reclamação”: cria um card no quadro “Melhorias” com o **resumo** do problema, para a Fernanda tratar a causa.

**Resultado:** Nenhuma reclamação séria fica com o robô nem espera na fila. A Fernanda recebe o caso resumido, o dono só é chamado se ela não puder, e as causas viram uma lista de melhorias.

**Por que é novo:** A passagem de hoje acontece quando o cliente pede ou quando a agente não sabe. Nenhuma IA mede a irritação nem escala por gravidade.

**Convive:** Não refaz a triagem de assunto: não cria nem troca o card do pedido. Só olha o tom da mensagem.

*Páginas: Agentes, CRM, Etiquetas, Equipe · Usa: F3, F4, F6, F7.*

### 11. Indicação que vira presente · Pet shop

> "Quando um cliente me indica alguém, quero dar um desconto pro amigo. E se o amigo virar cliente, quero mandar um banho grátis pro cachorro de quem indicou."  
> — Lu, dona do pet shop

**Começa quando:** Toda mensagem de cliente (a IA decide se é indicação).

1. A IA **decide** se é uma indicação, com nome e telefone de alguém. Se não for, para.
2. A IA **extrai** nome do amigo, telefone e o nome do pet, se vier.
3. Cria o contato do amigo e um card no quadro “Indicações”, com “indicado por Maria” gravado no card.
4. Agradece a Maria: “Obrigada! Vou falar com o João com todo carinho”.
5. Manda ao João, pelo modelo aprovado: “Oi, João! A Maria indicou a gente. O primeiro banho do seu pet tem 20% de desconto”, com o link da agenda.
6. João marcou: move o card dele para “Agendado”.
7. Card do João ganho: manda à Maria “O João virou cliente! O próximo banho do Thor é por nossa conta”, com o link da agenda.
8. Põe na Maria a etiqueta “indicou e fechou” e avisa a Lu.
9. Card do João perdido: agradece a Maria do mesmo jeito, sem presente.

**Resultado:** A Lu vê quem indica e quem fecha. O presente sai sozinho com o horário já oferecido, sem planilha.

**Por que é novo:** Nada liga hoje o card de um cliente ao de quem o indicou, nem age sobre os dois.

**Convive:** O card do amigo é de outro contato. A conversa da Maria continua com a IA de assunto como sempre.

*Páginas: CRM, Contatos, Etiquetas, Agendamento · Usa: F3, F4, F6, F7.*

### 12. Visita que aconteceu decide o próximo passo · Imobiliária

> "Depois da visita o corretor esquece de anotar e de mandar a proposta. Quero que o sistema faça isso."  
> — Márcio, dono da imobiliária

**Começa quando:** O card entra na etapa “Visita feita” (o pós-reunião da agenda já move quando a visita acontece).

1. Manda à Ana: “Obrigado pela visita! O que achou do apartamento?”.
2. Cria um retorno para o corretor: “Como foi a visita com a Ana? Escreva uma frase no campo ‘Como foi a visita’ do card”.
3. Espera até a Ana responder ou o campo ser preenchido, por até 24 horas.
4. A IA **decide** pelo que os dois disseram: “gostou”, “quer outra opção” ou “não gostou”.
5. Gostou: move para “Proposta”, manda à Ana por e-mail a lista de documentos para a proposta e cria retorno de 2 dias.
6. Quer outra opção: a IA **extrai** o que faltou (vaga, andar, preço), grava no card e cria retorno para mandar 3 opções.
7. Não gostou: põe a etiqueta “procurando”, fecha o card e coloca a Ana na campanha de lançamentos.
8. Nada em 24 horas: avisa o Márcio.

**Resultado:** Toda visita tem próximo passo no mesmo dia. O Márcio vê no quadro quem está em proposta, quem quer outra opção e quem voltou para a campanha.

**Por que é novo:** O pós-reunião de hoje só move o card. Ninguém pergunta ao corretor nem à cliente o que achou.

*Páginas: Agendamento, CRM, E-mail, Etiquetas, Campanhas · Usa: F4, F6, F7, F8.*

### 13. Festa do contrato ao depoimento · Buffet infantil

> "Depois que fecha a festa, quero que o sistema cuide de tudo até o dia: confirmar convidados, mandar o cardápio, lembrar a equipe e depois pedir a avaliação."  
> — Rose, dona do buffet

**Começa quando:** Card da festa marcado como ganho, com a data da festa no card.

1. Manda por e-mail o link do contrato gravado no card e põe a etiqueta “festa novembro”.
2. 30 dias antes, pelo modelo aprovado: pergunta quantos convidados e quantas crianças.
3. A IA **extrai** os números e grava no card.
4. 15 dias antes, pelo modelo aprovado: manda o cardápio e pergunta sobre alergias. A IA **extrai** as alergias e grava no card.
5. 7 dias antes: avisa a cozinha e a decoração com um **resumo**: data, convidados, alergias e tema.
6. 1 dia antes, pelo modelo aprovado: lembra a família do horário e do endereço.
7. 1 dia depois, pelo modelo aprovado: agradece e pede uma nota de 0 a 10.
8. Nota 9 ou 10: pede um depoimento e fotos, e põe a etiqueta “depoimento”.
9. Nota 6 ou menos: avisa a Rose na hora, com o **resumo**.
10. 11 meses depois, pelo modelo aprovado: oferece a festa do próximo aniversário.

**Resultado:** A equipe chega no dia sabendo quantas crianças e quais alergias. A Rose junta depoimentos sem pedir um por um, e a família recebe a oferta do próximo ano no mês certo.

**Por que é novo:** Nenhuma IA acompanha um card ganho até uma data futura nem fala com a equipe interna sobre ele.

*Páginas: CRM, Agendamento, Etiquetas, E-mail, Campanhas · Usa: F4, F6, F7, F8.*

### 14. Documentação completa para emitir · Corretora de seguros

> "Quando o cliente fecha, eu perco dias esperando documento. Quero que o sistema peça, confira e me avise só quando estiver tudo certo."  
> — Dona Cida, dona da corretora

**Começa quando:** O card entra na etapa “Documentação”.

1. Manda pelo modelo aprovado a lista do ramo: no seguro auto, CNH, documento do carro e comprovante de endereço.
2. A cada foto ou PDF que chega, a IA **extrai**, do que o leitor de mídia leu, qual documento é e se os dados dão para ler.
3. Não deu para ler: pede de novo, explicando (“não consegui ler o CPF, pode mandar outra foto?”).
4. Faltando algo: a IA **escreve** o pedido só do que falta.
5. 2 dias sem documento novo: lembra uma vez, pelo modelo aprovado. 4 dias: cria retorno para o corretor ligar.
6. Tudo recebido: põe a etiqueta “docs ok” e move para “Emissão”.
7. Manda os dados para o sistema da seguradora e grava no card o número da proposta que ele devolve.
8. A seguradora recusou: avisa a Dona Cida com o motivo que veio na resposta.

**Resultado:** A Dona Cida só olha o card quando está tudo certo ou quando há um problema real. O cliente sabe exatamente o que falta.

**Por que é novo:** O leitor de mídia lê foto e PDF com texto, mas nada confere a lista do que falta nem cobra só o que falta.

*Páginas: CRM, Etiquetas, E-mail · Usa: F3, F4, F6, F7, F8.*

### 15. Cliente grande, atendimento de dono · Distribuidora

> "Pedido grande eu quero que eu mesmo atenda, rápido, e que ninguém deixe esfriar."  
> — Carlos, dono da distribuidora

**Começa quando:** Card criado ou atualizado com valor acima de R$ 50 mil.

1. Se o contato já tem a etiqueta “cliente grande”, para aqui: a automação roda uma vez por cliente.
2. Tira a conversa da agente de IA e passa para o Carlos.
3. Põe a etiqueta “cliente grande” no contato e marca a conversa como prioridade.
4. A IA **resume** para o Carlos o que o cliente pediu, o prazo e a forma de pagamento.
5. Manda ao cliente: “Seu pedido é especial. O Carlos, dono da empresa, vai te atender pessoalmente”.
6. Manda o link da agenda do Carlos para uma ligação ainda hoje.
7. Espera o Carlos responder, por até 1 hora. Sem resposta: manda o resumo de novo ao Carlos e avisa o gerente comercial.
8. Card ganho: põe a etiqueta “conta grande” e cria retorno de pós-venda para 15 dias.
9. Card perdido: a IA **resume** o motivo para o Carlos.

**Resultado:** Pedido grande nunca cai no rodízio nem fica com o robô. O Carlos recebe o resumo e o cliente já tem a ligação marcada.

**Por que é novo:** A passagem para a equipe escolhe por caixa, pessoa, rodízio ou quem está online, mas nenhuma regra olha o valor do card.

*Páginas: CRM, Agentes, Etiquetas, Agendamento, Equipe · Usa: F3, F4, F6, F7.*

### 16. Reconquistar quem foi para o concorrente · Corretora de seguros

> "Quem fechou com outro no ano passado tá vencendo agora. Quero chamar de volta com uma oferta melhor."  
> — Juliana, corretora

**Começa quando:** Todo dia 1º do mês, para cada card perdido há 11 meses com o motivo “fechou com outro” ou “achou caro”.

1. Põe a etiqueta “reconquista” no contato.
2. Monta a campanha com o modelo aprovado “Seu seguro está vencendo” para todos com essa etiqueta.
3. Cada resposta: a IA **decide** “quer cotação”, “ficou satisfeito lá” ou “não quer contato”.
4. Quer cotação: a IA **escreve** uma resposta que fala do motivo da perda gravado no card antigo (“da outra vez o preço pesou; este ano consigo melhor”).
5. Cria um card novo no Comercial, com a origem “reconquista”, e passa para o corretor que atendeu da outra vez.
6. Ficou satisfeito: agradece e grava um retorno para daqui a 11 meses.
7. Não quer contato: registra e nunca mais manda.
8. Card novo sem resposta do corretor em 4 horas: manda ao cliente o link da agenda.

**Resultado:** Todo mês a Juliana tem uma lista nova de clientes perdidos que pediram cotação, cada um com o corretor que já conhece a história.

**Por que é novo:** Só o “adiou” agenda retorno hoje. Quem recusou ou fechou com outro nunca mais é procurado.

*Páginas: CRM, Campanhas, Agentes, Etiquetas, Agendamento · Usa: F4, F6, F7, F8.*

### 17. Vendedora de férias, cliente bem cuidado · Qualquer empresa com equipe

> "Quando alguém sai de férias eu passo os clientes para outra pessoa, mas o cliente fica perdido e a colega não sabe o que foi combinado. E quando ela volta, quero que os clientes voltem pra ela."  
> — Paula, gerente comercial

**Começa quando:** O responsável do card muda e a responsável anterior está marcada como ausente (a Paula troca todos os cards da Júlia de uma vez, pela Lista do CRM).

1. A IA **resume** para a nova responsável: o que o cliente quer, o que foi prometido, valores e próximo passo.
2. Manda ao cliente: “Oi, Maria! A Júlia está de férias e a Renata vai cuidar de você até ela voltar. Ela já está a par de tudo”.
3. Grava no card quem é a responsável original e põe a etiqueta “cobertura de férias”.
4. A cada mensagem do cliente, espera a Renata responder por até 2 horas. Sem resposta: passa a conversa para a agente de IA, que avisa “A Renata já te responde” e tira dúvidas simples.
5. Toda manhã, para cada card com a etiqueta “cobertura de férias”: se a responsável original já está disponível de novo, devolve o card a ela e tira a etiqueta.
6. A IA **resume** para a Júlia o que aconteceu durante as férias.

**Resultado:** Ninguém repete pergunta para o cliente. A Paula só troca os cards de uma vez, como já faz hoje, e o resto acontece sozinho, inclusive a volta.

**Por que é novo:** O resumo por IA só existe como botão no card. O novo dono não recebe nada sozinho, e o cliente não é avisado.

*Páginas: CRM, Equipe, Agentes, Etiquetas · Usa: F4, F7, F8.*

### 18. Seleção de candidatos sem planilha · Clínica que está contratando

> "Abri vaga de recepcionista e chegam currículos pelo WhatsApp. Quero que o sistema separe os bons e marque a entrevista."  
> — Dra. Patrícia, dona da clínica

**Começa quando:** Mensagem com currículo (PDF ou foto) na caixa de vagas.

1. A IA **extrai** do currículo nome, bairro, experiência e se tem curso de atendimento.
2. Cria o card no quadro “Seleção – Recepcionista”.
3. A IA **decide**: “atende o perfil”, “talvez” ou “não atende”, pelos requisitos que a doutora escreveu.
4. Atende o perfil: manda o link da agenda de entrevistas e põe a etiqueta “entrevista”.
5. Talvez: avisa a doutora com um **resumo** de 3 linhas para ela decidir.
6. Não atende: agradece com educação e fecha o card.
7. Perguntas sobre salário e horário: passa para a agente de IA, que responde com o texto da vaga.
8. 1 dia antes da entrevista, pelo modelo aprovado: lembra a candidata do endereço.
9. A recepção arrasta o card para “Não compareceu”: fecha o card com esse motivo.

**Resultado:** A doutora abre o quadro e vê só as candidatas com perfil, já com entrevista marcada. Todas recebem resposta.

**Por que é novo:** Nada no sistema lê currículo nem conduz uma seleção. Funciona porque a automação serve qualquer quadro, não só o de vendas.

**Convive:** Na caixa de vagas, a IA de assunto fica desligada (ela é configurada por caixa), e o quadro de seleção fica sem “Mover automaticamente”, para a IA não arquivar o currículo como “não é negócio”.

*Páginas: CRM, Etiquetas, Agendamento, Agentes · Usa: F3, F4, F6, F7, F8.*

### 19. Cliente que sumiu do WhatsApp · Qualquer empresa

> "Às vezes a mensagem não chega porque o cliente trocou de número. Quero que o sistema tente achar ele de outro jeito."  
> — Fernanda, gerente de atendimento

**Começa quando:** O WhatsApp recusa uma mensagem para o cliente.

1. Põe a etiqueta “número com problema” no contato.
2. Tem e-mail: manda por e-mail o mesmo conteúdo e pergunta “Você trocou de WhatsApp? Me responde com o número novo”.
3. Respondeu: a IA **extrai** o número novo e atualiza o contato.
4. A IA **escreve** o recado que tinha falhado e manda ao número novo dentro do modelo aprovado “Retomar contato”.
5. Chegou: tira a etiqueta e grava uma nota no contato: “número trocado em 03/11”.
6. Sem e-mail, ou sem resposta em 3 dias: cria um retorno para alguém ligar e avisa o responsável.
7. Falhou de novo no número novo: avisa a Fernanda com um **resumo** de tudo o que foi tentado.

**Resultado:** A mensagem que falhou chega ao cliente no número novo, e o cadastro fica certo. A Fernanda só é chamada quando não há outro jeito de achar a pessoa.

**Por que é novo:** Hoje só um tipo de erro é reenviado pela API oficial. A mensagem comum que falha fica só no balão, sem aviso e sem outro canal.

*Páginas: Contatos, E-mail, Etiquetas, CRM · Usa: F4, F7, F8.*

### 20. Venda fechada já entra no sistema da empresa · Empresa de software

> "Quando a gente fecha, alguém tem que copiar tudo para o sistema de cobrança e mandar as boas-vindas. Quero que isso aconteça sozinho."  
> — Ricardo, dono da empresa

**Começa quando:** O card é ganho.

1. A IA **extrai** da conversa o CNPJ, o e-mail do financeiro e o plano escolhido, se faltarem no card.
2. Faltou algum dado: pergunta ao cliente só o que falta e espera a resposta, por até 2 dias.
3. Manda os dados para o sistema de cobrança e grava no card o número de cliente que ele devolve.
4. O sistema de cobrança recusou: avisa o financeiro com o motivo que veio na resposta.
5. Manda o e-mail de boas-vindas com o link da agenda para a reunião de implantação.
6. Reunião marcada: move para “Implantação” e põe a etiqueta “cliente novo”.
7. 30 dias depois, pelo modelo aprovado: pergunta como está o uso, e a IA **decide** “bem”, “com dificuldade” ou “quer cancelar”.
8. Com dificuldade: manda o link da agenda para um treinamento. Quer cancelar: avisa o Ricardo com um **resumo**.
9. Bem: coloca o cliente na campanha de e-mail “Dicas do mês”.

**Resultado:** O cliente novo recebe boas-vindas e reunião no mesmo dia, sem ninguém copiar dados. No 30º dia, quem está com problema já aparece para o Ricardo.

**Por que é novo:** O ganho já vai para a Meta e o Google Ads, mas não para sistema de cobrança, ERP ou planilha. A implantação não tem acompanhamento.

*Páginas: CRM, E-mail, Agendamento, Etiquetas, Campanhas · Usa: F4, F6, F7, F8.*
