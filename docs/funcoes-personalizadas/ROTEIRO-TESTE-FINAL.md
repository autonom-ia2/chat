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

## No fim (limpeza)

1. Remova a pessoa de teste em **Configurações → Usuários**, para não contar no plano.
2. Apague a função "Teste – só lê" em **Funções personalizadas**.
3. Confira que o contato e a empresa de teste do teste 6 foram excluídos e que os cards de teste do teste 8 ficaram arquivados.
4. Remova "Teste Atendente" e apague a função "Teste – montada" do teste 11.

Se algo não bater com o esperado, me mande o print e o número do teste e do passo, que eu investigo.
