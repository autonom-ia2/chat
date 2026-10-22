# Roteiro do teste final — funções personalizadas (épico #1784)

Guardado em 18/10/2026 por decisão do Rodrigo: "deixa esse teste guardado e seguimos e no fim fazemos o teste completo".
Roda no fim do épico, na conta 16 (Hub2you, stack hub2you, chat.hub2you.ai). Cobre os lotes #1791, #1796, #1798, #1803, #1835, 5a (#1845) e 5b (#1849); os lotes seguintes acrescentam testes aqui.

**Quem prepara:** criar a pessoa de teste e a função exige escrita em produção. Ou o Rodrigo faz a preparação e entra com a pessoa no Chrome que o Claude controla, ou libera a escrita para o Claude. O Claude não cria conta nem digita senha.

## Preparação (uma vez)

1. Entre como administrador, na conta Hub2you.
2. Crie a pessoa de teste em **Configurações → Usuários → Adicionar**: nome "Teste Funções", um e-mail seu que receba o convite, perfil **Agente**.
3. Aceite o convite pelo e-mail e defina a senha.
4. Ponha essa pessoa em **uma caixa só**, a caixa A (por exemplo, o WhatsApp principal), em **Configurações → Canais → (caixa A) → Colaboradores**. As outras caixas, que aqui chamo de B, ficam sem ela.
5. Para testar como ela, use uma **janela anônima**. Na janela normal você continua como administrador para trocar a função entre um teste e outro.

## Teste 1: quem só lê conversas (#1803 e #1835)

1. Como administrador, em **Configurações → Funções personalizadas → Nova função**, escolha **Começar do zero**.
2. Dê o nome "Teste – só lê". Em **Conversas**, marque **Ver** e clique em **Criar função**.
3. Em **Usuários**, edite a pessoa de teste e escolha a função "Teste – só lê".
4. Na janela anônima, entre como ela. O esperado:
   - a lista mostra só a aba **Todos**, com as conversas da caixa A, e nenhuma da caixa B;
   - não aparece o botão de **Nova conversa**, nem a seleção de várias conversas;
   - ao abrir uma conversa, aparece no topo a faixa cinza "Você pode ler esta conversa, mas não responder…";
   - não há caixa de resposta, nem Resolver, Passar para ou o menu no cabeçalho;
   - com o botão direito numa mensagem, só aparecem **Copiar** e **Copiar link**;
   - no painel da direita aparecem o **Resumo da conversa** (quem atende, time, prioridade e etiquetas) e os **Participantes**, sem nada para clicar e mudar.
5. Teste a menção: na janela normal, numa conversa da caixa A, escreva uma **nota interna** mencionando "@Teste Funções". Na janela anônima, a conversa deve aparecer em **Menções**, e a pessoa, nos participantes.

## Teste 2: atende as próprias e lê as outras (o caso "Vendas")

1. Edite a função "Teste – só lê". Em **Conversas**, marque **Atender** e depois **Só as próprias**.
2. Abra os **Ajustes finos** de Conversas, ligue **"Lê as outras conversas da caixa"** e salve.
3. Na janela normal, atribua uma conversa de teste à pessoa (por exemplo, uma do seu próprio número).
4. Na janela anônima (recarregue a página), o esperado:
   - na conversa atribuída a ela: caixa de resposta normal, e ela pode responder;
   - numa conversa de outra pessoa: a faixa cinza, sem caixa de resposta;
   - se você a adicionar como participante numa conversa de outra pessoa, ela passa a poder responder nessa também.

## Teste 3: regras de distribuição (#1798)

1. Edite a função. Em **Configurações da conta → Atribuição de agentes**, marque **Editar** e salve.
2. Na janela anônima, abra **Configurações → Atribuição**. O esperado:
   - ela vê, cria e edita as regras de distribuição e de capacidade;
   - ela consegue ligar uma regra a uma caixa.
3. Volte a função para **Sem acesso** em Atribuição. A tela de Atribuição deve sumir do menu dela.

## Teste 4: Anúncios da Meta só para ver (#1796)

Esse teste só funciona se a conta 16 tiver os Anúncios da Meta conectados.

1. Edite a função. Em **Marketing → Anúncios da Meta**, marque **Ver** e salve.
2. Na janela anônima, abra o painel de **Anúncios da Meta**. O esperado:
   - ela vê o painel, os anúncios por dentro e a IA do dia;
   - ela não tem como conectar, desconectar, configurar o destino dos anúncios nem o resumo no WhatsApp;
   - nas listas que levam a uma conversa, aparecem só conversas da caixa A.

## Teste 5: Agentes de IA respeitam a caixa da pessoa (#1791)

1. Edite a função. Em **Autonom.ia → Agentes Autonom.ia**, marque **Editar** e salve.
2. Na janela anônima, abra **Agentes → (um agente) → Onde e quando**. O esperado:
   - as caixas B aparecem desabilitadas, com o texto "Você não faz parte deste canal…";
   - ela não consegue escolher uma caixa B como principal;
   - se o agente já estava numa caixa B, ele continua lá depois de salvar.
3. Em **CRM → Caixas**, ela não consegue trocar o agente de IA da caixa B.
4. Na aba **Desempenho** do agente, a lista "conversas atendidas" mostra só conversas da caixa A.

## Teste 6: exportar e excluir contatos (#1845)

1. Edite a função. Em **Contatos e empresas**, marque **Editar** e salve, sem ligar nenhum ajuste fino.
2. Na janela anônima, abra **Contatos**. O esperado:
   - no menu do topo aparecem **Adicionar** e **Importar**, mas não **Exportar**;
   - na ficha de um contato não aparece a área **Excluir contato**; na conversa, o painel do contato não mostra a lixeira;
   - ao marcar vários contatos, a barra não mostra **Excluir**;
   - numa empresa não aparece **Excluir empresa**.
3. Volte à função. Em **Ajustes finos** de Contatos, ligue **Exportar** (pede confirmação, porque é dado pessoal) e salve. Na janela anônima, recarregue: **Exportar** aparece e o arquivo chega por e-mail.
4. Ligue também **Excluir** e salve. Na janela anônima: a área **Excluir contato**, a lixeira no painel da conversa, o **Excluir** em massa e o **Excluir empresa** aparecem e funcionam. Use um contato e uma empresa criados só para o teste.
5. Troque Contatos para **Ver**. O ajuste **Excluir** some (só vale para quem edita); **Exportar** continua.
6. Conferência da migração (só leitura, pela Orquestração ou por psql): todo cargo que tinha `contact_manage` antes do deploy tem `contact_export` depois.

## Teste 7: quem não vê contatos (#1849)

1. Edite a função. Em **Contatos e empresas**, escolha **Sem acesso**. Em **Conversas**, deixe **Atender** e **Só as próprias**. Salve.
2. Na janela normal, atribua à pessoa uma conversa de teste.
3. Na janela anônima (recarregue a página), o esperado:
   - o menu não tem **Contatos**, **Empresas** nem **Nova conversa**;
   - a busca global não tem a aba **Contatos**, mas acha a conversa pelo nome ou telefone do cliente;
   - na conversa, o painel da direita mostra só nome, telefone e e-mail do cliente, com **Nova mensagem** e **Ligar**, mais a **Origem** e as **conversas anteriores**. Não aparecem atributos, notas, editar, mesclar nem o link para a ficha;
   - **Nova mensagem** abre a Nova conversa já com esse cliente;
   - no CRM, a gaveta do card mostra a pessoa só com nome, telefone e e-mail, sem empresa; ao criar oportunidade, **Escolher dos contatos** fica desligado;
   - num cartão de contato recebido pelo WhatsApp, não aparecem **Salvar contato** nem **Conversar**.
4. Volte a função para **Ver** em Contatos. Tudo volta: lista, ficha completa, busca, **Nova conversa** e filtro de empresa no Kanban.

## Teste 8: arquivar cards e ação em massa do CRM (#1874)

1. Edite a função. Em **CRM**, escolha **Só olha** e salve.
2. Na janela anônima (recarregue a página), abra o CRM em **Lista**: as linhas não têm caixa de seleção e não aparece barra de ações em massa. Abra um card: a gaveta não tem **Arquivar**.
3. Volte à função, troque o CRM para **Pode mexer** e salve. Em **Ajustes finos** aparece **Arquivar cards do CRM**, desligado.
4. Na janela anônima, recarregue a Lista e marque dois cards de teste: a barra mostra **Mover**, **Quem cuida** e **Situação**, sem **Arquivar**. A gaveta do card também fica sem **Arquivar**.
5. Ligue **Arquivar cards do CRM** e salve. Na janela anônima, a barra e a gaveta mostram **Arquivar**. Arquive um card de teste pela gaveta e outro pela barra.
6. Troque o CRM para **Só olha**. O ajuste **Arquivar cards do CRM** some (só vale para quem mexe).
7. Conferência da migração (só leitura, pela Orquestração ou por psql): todo cargo que tinha `crm_manage_cards` antes do deploy tem `crm_delete_cards` depois, inclusive os cargos gerenciados de token de integração do CRM.

## Teste 9: apagar mensagem (#1893)

1. Edite a função. Em **Conversas**, deixe **Atender** e **Só as próprias**, sem ligar **Apagar mensagens**. Salve.
2. Na janela anônima, abra uma conversa de teste atribuída à pessoa. No menu da mensagem (botão direito ou os três pontos), **Apagar** não aparece. Responder, copiar e os outros itens seguem lá. Numa conversa de e-mail, o ⋮ do e-mail também não tem **Excluir**.
3. Volte à função. Em **Ajustes finos** de Conversas, ligue **Apagar mensagens** (pede confirmação) e salve. Na janela anônima, recarregue: **Apagar** aparece e apaga. Use uma mensagem enviada só para o teste.
4. Troque Conversas para **Todas**: o ajuste **Apagar mensagens** continua visível e ligado. Troque para **Só olha**: o ajuste some e, ao voltar para **Atender**, vem desligado.
5. Com uma pessoa sem função (agente comum), **Apagar** segue aparecendo como antes.
6. Conferência da migração (só leitura, pela Orquestração ou por psql): todo cargo que tinha alguma das três chaves de atender conversa antes do deploy tem `conversation_message_delete` depois; quem tinha só `conversation_view` não ganhou.

## Teste 10: montar sem disparar campanhas (#1898)

1. Edite a função. Em **Marketing**, deixe **Campanhas** em **Editar**, sem ligar **Disparar campanhas** em **Ajustes finos**. Salve.
2. Na janela anônima, abra **Campanhas > Campanha > Nova campanha** e monte uma campanha de SMS (ou WhatsApp) para um público de teste. Na revisão, o esperado:
   - o botão é **Deixar pronta para disparar**, com o aviso de que quem pode disparar confere e envia;
   - clicar não pede a confirmação de envio, não manda nada e volta para a lista, onde a campanha aparece com **Pronta para disparar · montada por** e o nome da pessoa.
3. Ainda na janela anônima: numa campanha de e-mail, a revisão também mostra **Deixar pronta para disparar** e não mostra **Enviar agora** nem **Agendar**. Uma campanha pausada não tem **Retomar** (no resultado, em **Modelos > Campanhas paradas** e na lista do WhatsApp API). Nas telas antigas de SMS, WhatsApp e WhatsApp API, o botão **Nova campanha** não aparece.
4. Na janela normal (administrador), abra a campanha pronta pela lista. A revisão mostra quem a montou e **Enviar agora**, com a confirmação. Envie para o público de teste: a linha **Pronta para disparar** some e a campanha aparece como enviada.
5. Volte à função e ligue **Disparar campanhas** (pede confirmação, porque gera custo). Na janela anônima, recarregue: a revisão volta a mostrar **Enviar agora** e **Agendar**, e **Retomar** aparece nas pausadas.
6. Troque Campanhas para **Ver**: o ajuste **Disparar campanhas** some.
7. Conferência da migração (só leitura, pela Orquestração ou por psql): todo cargo que tinha `campaign_manage` antes do deploy tem `campaign_send` depois.

## Teste 11: Pessoas, quem cuida do cadastro sem ser administrador (#1931)

Precisa de uma segunda pessoa de teste, "Teste Atendente" (perfil Agente, sem função), criada pelo administrador.

1. Edite a função da pessoa de teste em **Configurações → Funções personalizadas**. No grupo **Configurações da conta**, na linha **Pessoas**, escolha **Editar** e salve, sem ligar os ajustes finos. Deixe também **Conversas: Ver**.
2. Na janela anônima (recarregue), abra **Configurações**: aparecem **Usuários** e **Times** (no menu novo, no grupo **Pessoas e acesso**). **Funções personalizadas** não aparece.
3. Em **Usuários**, o esperado:
   - os administradores e a própria pessoa de teste têm um cadeado no lugar de editar e excluir, com o motivo;
   - "Teste Atendente" tem editar e excluir;
   - em **Adicionar agente**, a opção **Administrador** aparece desabilitada com "Só um administrador torna alguém administrador", e as funções com chaves que ela não tem também aparecem desabilitadas.
4. Edite "Teste Atendente" e dê a ele uma função que só tenha **Conversas: Ver**: salva. Tente uma função com CRM: a opção aparece desabilitada.
5. Em **Times**, crie o time "teste-funcoes", ponha "Teste Atendente" nele e depois apague o time.
6. Na janela normal, ligue em Pessoas o ajuste **Montar funções** (pede confirmação). Na anônima, recarregue: **Funções personalizadas** aparece. A função da própria pessoa tem cadeado "É a sua função". Crie a função "Teste – montada" só com **Conversas: Ver**: salva. Abra uma função com mais chaves: as linhas que ela não tem ficam travadas, com o motivo.
7. Na janela normal, ligue **Pode entregar acesso acima do próprio** (pede confirmação). Na anônima, recarregue: ela consegue dar a "Teste Atendente" uma função com CRM. **Administrador** continua desabilitado.
8. Na janela normal, abra **Configurações → Auditoria** e confira as linhas: a troca de função de "Teste Atendente", a criação de "Teste – montada" e o time criado e apagado, com o nome da pessoa de teste como autora.

## Teste 12: Financeiro, custos sem plano nem faturas (#1969)

Precisa de uma conta com a IA do CRM e a nova tela de Modelos do WhatsApp ligadas.

1. Edite a função da pessoa de teste. Deixe **CRM** com **Relatórios** ligado e o novo grupo **Financeiro** em **Sem acesso**. Salve.
2. Na janela anônima (recarregue), abra **Gasto com IA** (menu antigo: CRM → Gestão de IA). O esperado:
   - um aviso diz que ela vê quanto a IA foi usada e que os valores aparecem para quem tem Financeiro;
   - só o cartão de **Usos** aparece; não há gasto, economia nem custo médio;
   - o gráfico e a lista por recurso contam usos, sem R$ nem US$;
   - o histórico não tem a coluna de custo, e o relatório baixado também não.
3. Volte à função, ponha **Financeiro** em **Ver** e salve. Recarregue a anônima: os valores voltam (cartões, gráfico em reais, coluna de custo e as colunas de custo no relatório).
4. Na anônima, abra **Configurações → Custos do WhatsApp** (ou Campanhas → Modelos WhatsApp → Ver autorização). Tudo aparece travado, com a frase de que só o administrador ou quem tem Financeiro em Editar muda.
5. Ponha **Financeiro** em **Editar** e salve. Recarregue: as caixas e o botão de ligar ficam liberados e a frase some. Clique em **Ligar autorização** só até ver a confirmação com o custo e **cancele**: ligar de verdade autoriza cobranças da Meta na conta. Ligue apenas se o dono da conta quiser; nesse caso, o histórico mostra o nome da pessoa de teste como quem ligou.
6. Em qualquer nível de Financeiro, o menu **Financeiro** antigo (Assinatura e Faturas) e o cartão **Plano e faturas** não aparecem para ela.
7. Se a conta tiver alguém só com **Pessoas** (sem **Pode entregar acesso acima do próprio**), na tela de Usuários a função com Financeiro aparece desabilitada para ele, e na montagem de funções a linha Financeiro fica travada.
8. Ao final, volte **Financeiro** para **Sem acesso**.

## Teste 13: Integrações e tokens sem ser administrador (#2027)

Use a mesma pessoa de teste, com uma função própria ("Teste – integrações").

1. Monte a função com **Integrações** em **Editar** (aceite a sugestão de **Caixas** em **Ver**) e **sem** o ajuste **Ver e trocar tokens e chaves**. Salve e recarregue a janela anônima.
2. Abra **Configurações → Integrações**: ela conecta e desconecta. Em **Webhooks**, cria e edita, mas não vê a chave de assinatura (aparece a frase de que a chave fica com quem cuida dos tokens). Em **Robôs**, cria e edita, sem os botões de trocar token e segredo.
3. Abra uma caixa de e-mail com servidor próprio → **Configuração**: os dados do IMAP e do SMTP aparecem, sem a senha. Para salvar uma mudança no servidor, ela precisa digitar a senha de novo.
4. Ligue **Ver e trocar tokens e chaves** e salve. Recarregue: numa caixa de site ou de API, a chave HMAC aparece com **Trocar chave**; a chave de assinatura do webhook e os botões dos robôs também aparecem.
5. Abra os tokens do CRM (link em Integrações → n8n): a tela só oferece escopos que ela tem. Sem nenhuma chave do CRM, aparece a frase explicando isso.
6. Troque a função para **Caixas** em **Editar**, sem **Integrações**. Numa caixa que precisa reconectar, aparece "peça a quem cuida das integrações", sem botão. O endereço do webhook da caixa de API fica só leitura.
7. Ao final, apague a função "Teste – integrações".

## Teste 14: Anúncios da Meta sem ser administrador (#2070)

Esse teste só funciona se a conta 16 tiver Anúncios da Meta ligado. Use a mesma pessoa de teste, com uma função própria ("Teste – anúncios").

1. Como administrador, monte a função com **Marketing → Anúncios da Meta** em **Editar**. Salve e recarregue a janela anônima.
2. Na janela anônima, o menu **Campanhas → Anúncios** aparece. Abra: ela conecta (ou continua a conexão), escolhe a conta de anúncios e o Pixel, marca para onde os anúncios levam e grava o aviso no funil, como o administrador.
3. Na aba **Resultado**, os botões **Feito** e **Dispensar** de O que fazer hoje aparecem e funcionam. Na aba **Conexão**, o resumo no WhatsApp abre, muda e testa.
4. Deixe a tela de Anúncios aberta na janela anônima: quando a leitura de hoje termina, o "atualizando…" some e os números trocam sozinhos, sem recarregar.
5. Troque a função para **Ver**: o painel continua, sem **Feito**, **Dispensar**, aba **Conexão** nem botão de conectar.
6. Dê à pessoa também **Montar funções** e tente, na janela anônima, criar uma função com Anúncios da Meta em **Editar**: o nível aparece travado, com a frase de que só quem pode entregar acima do próprio acesso entrega. Em **Ver** ela consegue.
7. Ao final, apague a função "Teste – anúncios" e a que ela criou no passo 6.

## Teste 15: Valores de venda sem ser administrador (#2075)

Use a mesma pessoa de teste, com uma função própria ("Teste – valores"). Tenha na conta 16 um funil de venda com dois cards com valor: um com a pessoa de teste como responsável e outro com outra pessoa.

1. Como administrador, monte a função com **CRM** em **Editar** e **Relatórios do CRM**, sem **Ver os valores de venda em R$**. Salve e recarregue a janela anônima.
2. Na janela anônima, abra o quadro do funil: o card da outra pessoa aparece sem valor; o card da pessoa de teste mostra o valor. Na **Lista**, a coluna Valor mostra um traço no card da outra pessoa, o total do grupo mostra só a quantidade e a coluna não ordena. Nos **Filtros**, a faixa de valor não aparece.
3. Abra o card da outra pessoa: o resumo não fala de valor e, em **Negócio**, aparece "Só quem tem acesso aos valores de venda vê o valor deste negócio." Mude o título e salve: o título muda e o valor continua o mesmo (confira como administrador).
4. Marque esse card como ganho: o diálogo não pede valor e avisa que o valor do negócio fica como está. Confira como administrador que o valor não mudou.
5. No **Painel do CRM**, as contagens e a taxa de ganho aparecem; os quadros em R$, a meta do mês e os valores por etapa não aparecem. Em **Números**, "Só eu" mostra o que a pessoa vendeu e a meta dela, sem a barra da equipe; em "Equipe", aparecem as contagens, sem R$.
6. Ligue **Ver os valores de venda em R$** na função, salve e recarregue: todos os valores voltam, inclusive a faixa de valor nos Filtros e a meta no Painel.
7. Dê à pessoa também **Montar funções** e tente, na janela anônima, ligar **Metas do mês** numa função: aparece travada, com a frase de que só quem pode entregar acima do próprio acesso entrega.
8. Ao final, apague a função "Teste – valores".

## No fim (limpeza)

1. Remova a pessoa de teste em **Configurações → Usuários**, para não contar no plano.
2. Apague a função "Teste – só lê" em **Funções personalizadas**.
3. Confira que o contato e a empresa de teste do teste 6 foram excluídos e que os cards de teste do teste 8 ficaram arquivados.
4. Remova "Teste Atendente" e apague a função "Teste – montada" do teste 11.
5. Confira que a função "Teste – integrações" do teste 13 foi apagada.
6. Confira que as funções "Teste – anúncios" e a criada no passo 6 do teste 14 foram apagadas.
7. Confira que a função "Teste – valores" do teste 15 foi apagada.

Se algo não bater com o esperado, me mande o print e o número do teste e do passo, que eu investigo.
