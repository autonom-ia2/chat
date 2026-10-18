# F2 corretora · Lote 2: Conversas e Contatos

autonom-ia2/chat#1802, 18/10/2026. Vem depois do lote 1 (#1843), que mexe no mesmo arquivo do pacote.

É só texto, no pacote `seguros/corretora`. A conta geral não muda.

## O que entra

São 50 textos do painel.

**Conversas**
- Exemplos de corretor na janela do "+" da conversa: link da vistoria, "Seguro do carro, da casa, de vida", posto de vistoria, assistência 24 horas.
- Nova conversa: abertura e assunto de cotação.
- A nota interna diz "Só a equipe vê".

**Respostas prontas, macros e busca**
- Exemplos reais: "/cotacao", "Pode me mandar a CNH e o documento do carro?", "Prefere boleto ou cartão?".
- A macro "Pedir documentos do carro".
- A busca por placa ou por "apólice", feita no texto da mensagem.

**Contatos e Empresas**
- Estado vazio e importação falando da carteira de clientes.
- Exemplos de campo: Seguradora atual, Vencimento do seguro, Placa, CNPJ.
- Notas e descrição com exemplos de corretor.

**Relacionamentos**
- "Cliente bem cuidado renova e indica".
- Mídia com apólice, boleto e CNH.

## O que ficou de fora, e por quê

- **`CONVERSATION.FOOTER.MSG_INPUT`:** o exemplo "/cotacao" só funciona se a conta criar esse atalho, e a conta começa sem nenhum. Fica o texto do geral.
- **Prospecção:** as jogadas e o modo padrão são de agência e estão no código. O en do base também é cópia do pt. Vai como lacuna, com o dono da Prospecção.
- **Selo "Cliente":** não vira "Segurado". Isso só é possível depois do vencimento (fase seguinte).
- **Não se mexe:**
  - modelos da Meta, "mensagem pronta", `CONVERSA_CANAL.MODELO`, `PEDIDO` e `ENQUETE`;
  - opt-out;
  - a Lia (`insurance.json`).
- **A aba de seguros na ficha:** entrou no lote 1.

## Os textos, por dono

### Frontend geral (Max): Conversas, respostas prontas, macros e busca (20)

| Chave | Hoje | Corretora |
|---|---|---|
| `CONVERSA_CANAL.JANELA.BOTAO_DE_LINK.AJUDA` | O cliente toca no botão e abre o site. | O cliente toca no botão e abre o site. Ex.: o link da vistoria ou da assinatura da proposta. |
| `CONVERSA_CANAL.JANELA.OPCOES.AJUDA` | O cliente responde com um toque. Até 3 opções viram botões; mais que isso, uma lista. | O cliente responde com um toque. Ex.: Seguro do carro, Seguro da casa, Seguro de vida. Até 3 opções viram botões; mais que isso, uma lista. |
| `CONVERSA_CANAL.JANELA.LOCALIZACAO.AJUDA` | O cliente recebe o lugar no mapa. | O cliente recebe o lugar no mapa. Ex.: o endereço da corretora ou do posto de vistoria. |
| `CONVERSA_CANAL.JANELA.LOCALIZACAO.BUSCAR_EXEMPLO` | Ex.: Av. Paulista, 1000 ou Loja Exemplo | Ex.: Av. Paulista, 1000 ou Escritório Exemplo |
| `CONVERSA_CANAL.JANELA.CONTATO.AJUDA` | O cliente recebe o cartão e pode conversar com esse número. | O cliente recebe o cartão e pode conversar com esse número. Ex.: a assistência 24 horas da seguradora. |
| `NOVA_CONVERSA.MENSAGEM.PLACEHOLDER` | Escreva aqui o que você quer dizer | Ex.: Oi, tudo bem? Separei as opções da sua cotação. |
| `NOVA_CONVERSA.MENSAGEM.ASSUNTO_PLACEHOLDER` | Sobre o que é o e-mail | Ex.: Cotação do seguro do carro |
| `CONVERSATION.FOOTER.PRIVATE_MSG_INPUT` | A mensagem será visível apenas para agentes | Só a equipe vê. Ex.: cliente prefere pagar no cartão em 10x. |
| `CONVERSATION.NO_MESSAGE_1` | Oh oh! Parece que não há mensagens de clientes na sua caixa de entrada. | Nenhuma conversa ainda. Quando um cliente pedir uma cotação, a conversa aparece aqui. |
| `CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES` | Atributos do contato | Dados do cliente |
| `CANNED_MGMT.DESCRIPTION` | Respostas prontas são modelos de resposta pré-escritas que te ajudam a responder rapidamente a uma conversa. Os agentes podem digitar o caractere ' /' seguido pelo atalho para inserir uma resposta pronta durante uma conversa.  | Respostas prontas são as frases que você mais manda, salvas para usar num toque. Na conversa, digite '/' e o atalho. Ex.: /cotacao manda "Segue a cotação com as opções. Qual você prefere?" |
| `CANNED_MGMT.ADD.DESC` | Respostas Prontas são modelos de resposta predefinidas que podem ser usados para enviar respostas rapidamente durante conversas. | Salve uma frase que você manda sempre. Ex.: "Pode me mandar a CNH e o documento do carro?" |
| `CANNED_MGMT.LIST.404` | Não há respostas prontas disponíveis nesta conta. | Nenhuma resposta pronta ainda. Comece pelas frases que você mais manda, como "Prefere boleto ou cartão?" |
| `CANNED_MGMT.ADD.FORM.SHORT_CODE.PLACEHOLDER` | Por favor, insira um atalho. | Ex.: cotacao |
| `CANNED_MGMT.EDIT.FORM.SHORT_CODE.PLACEHOLDER` | Por favor, insira um atalho. | Ex.: cotacao |
| `CANNED_MGMT.ADD.FORM.CONTENT.PLACEHOLDER` | Por favor, escreva a mensagem que deseja salvar como um modelo para usar posteriormente. | Ex.: Segue a cotação com as opções. Qual você prefere? |
| `CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER` | Por favor, escreva a mensagem que deseja salvar como um modelo para usar posteriormente. | Ex.: Segue a cotação com as opções. Qual você prefere? |
| `MACROS.DESCRIPTION` | Uma macro é um conjunto de ações salvas que ajudam os agentes de atendimento ao cliente a concluir tarefas com facilidade. Os agentes podem definir um conjunto de ações, como etiquetar uma conversa com um rótulo, enviar uma transcrição de e-mail, atualizar um atributo personalizado, etc., e podem executar essas ações com um único clique. | Uma macro faz várias ações de uma vez, com um clique. Ex.: pôr a etiqueta "vistoria pendente", mandar o link da vistoria e deixar a conversa pendente. |
| `MACROS.ADD.FORM.NAME.PLACEHOLDER` | Digite um nome para sua macro | Ex.: Pedir documentos do carro |
| `SEARCH.EMPTY_STATE_DEFAULT` | Procurar por ID de conversa, e-mail, número de telefone, mensagens para melhores resultados de busca. | Procure pelo nome, telefone ou e-mail do cliente, pelo número da conversa ou por uma palavra da mensagem, como "apólice" ou a placa do carro. |

### Base de Clientes: Contatos, Empresas, Relacionamentos e importação (30)

| Chave | Hoje | Corretora |
|---|---|---|
| `CONTACTS_LAYOUT.EMPTY_STATE.SUBTITLE` | Comece a adicionar novos contatos clicando no botão abaixo | Adicione seu primeiro cliente no botão abaixo. Para trazer a carteira toda, use Importar contatos. |
| `CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DESCRIPTION` | Importar contatos através de um arquivo CSV. | Importe a planilha da sua carteira de clientes (arquivo CSV). |
| `CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.PLACEHOLDER` | Informe o nome para esse filtro | Ex.: Clientes com seguro do carro |
| `CONTACTS_LAYOUT.FILTER.SEGMENT.INPUT_PLACEHOLDER` | Digite o nome do segmento | Ex.: Clientes com seguro do carro |
| `CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM.BIO.PLACEHOLDER` | Digite uma biografia | Ex.: tem o seguro do carro com a gente e quer cotar o da casa |
| `CONTACT_FORM.FORM.BIO.PLACEHOLDER` | Insira a descrição do contato | Ex.: tem o seguro do carro com a gente e quer cotar o da casa |
| `CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.EMPTY_STATE` | Não há atributos personalizados de contatos disponíveis nesta conta. Você pode criar um atributo personalizado nas configurações. | Esta conta ainda não tem campos do cliente. Crie nas configurações campos como Seguradora atual, Vencimento do seguro e Placa. |
| `CONTACTS_LAYOUT.SIDEBAR.NOTES.PLACEHOLDER` | Adicionar uma nota | Ex.: prefere pagar no cartão em 10x |
| `CONTACTS_LAYOUT.SIDEBAR.NOTES.EMPTY_STATE` | Não existem notas associadas a este contato. Você pode adicionar uma nota digitando na caixa acima. | Ainda não há notas deste contato. Anote na caixa acima o que a equipe precisa lembrar, como a forma de pagamento ou a troca do carro. |
| `COMPOSE_NEW_CONVERSATION.FORM.EMAIL_OPTIONS.SUBJECT_PLACEHOLDER` | Digite o assunto do seu e-mail aqui | Ex.: Cotação do seguro do carro |
| `CONTACTS_LAYOUT.DETAILS.CUSTOMER.DESCRIPTION` | Vira cliente sozinho quando um seguro fecha num funil de venda. Marque aqui se ele já comprou de outro jeito. | Vira cliente sozinho quando um seguro fecha num funil de venda. Marque aqui se ele já fechou seguro com você fora do funil. |
| `COMPANIES.DETAIL.PROFILE.DESCRIPTION_PLACEHOLDER` | Adicionar uma breve descrição para esta empresa | Ex.: transportadora com frota própria; quer cotar o seguro de carga |
| `COMPANIES.DETAIL.ATTRIBUTES.EMPTY_STATE` | Não há atributos personalizados da empresa configurados ainda. | Esta conta ainda não tem campos da empresa. Crie nas configurações campos como CNPJ, Ramo e Vencimento do seguro. |
| `RELATIONSHIPS.SUBTITLE` | Centralize e organize pessoas, empresas e informações personalizadas para fortalecer seus relacionamentos. | Seus clientes, as empresas que você atende e os dados de cada seguro, num lugar só. |
| `RELATIONSHIPS.HOME_SUPPORT_TITLE` | Relacionamentos mais fortes geram mais oportunidades | Cliente bem cuidado renova e indica |
| `RELATIONSHIPS.HOME_SUPPORT_DESCRIPTION` | Mantenha seus dados organizados e atualizados para uma comunicação mais inteligente e resultados consistentes. | Mantenha em dia dados como seguradora e vencimento, para chegar antes na renovação. |
| `RELATIONSHIPS.CARD_DETAILS.CONTACTS.SUBTITLE` | Gerencie suas pessoas | Cuide da sua carteira |
| `RELATIONSHIPS.CARD_DETAILS.CONTACTS.DESCRIPTION` | Cadastre e gerencie seus contatos, com histórico de interações, mídias e atributos personalizados. Tenha uma visão completa de cada relacionamento. | Cadastre seus clientes e veja, de cada um, as conversas, os arquivos (como apólice e boleto) e os campos do seguro. |
| `RELATIONSHIPS.CARD_DETAILS.CONTACTS.BASIC_DESCRIPTION` | Cadastre e gerencie pessoas e acompanhe o histórico dos seus relacionamentos. | Cadastre seus clientes e veja o histórico de conversa de cada um. |
| `RELATIONSHIPS.CARD_DETAILS.COMPANIES.DESCRIPTION` | Organize empresas, vincule contatos e consulte suas informações, mídias e atributos em um só lugar. | Organize as empresas que você atende, como frotas e condomínios, e ligue cada uma aos seus contatos e arquivos. |
| `RELATIONSHIPS.CARD_DETAILS.COMPANIES.BASIC_DESCRIPTION` | Organize empresas, vincule seus contatos e centralize as informações comerciais. | Organize as empresas que você atende, como frotas e condomínios, e ligue cada uma aos seus contatos. |
| `RELATIONSHIPS.CARD_DETAILS.ATTRIBUTES.DESCRIPTION` | Crie campos personalizados e defina onde eles aparecem. Adapte os detalhes de contatos e empresas à realidade da sua operação. | Crie campos como Seguradora atual, Vencimento do seguro e Placa, e escolha onde eles aparecem. |
| `RELATIONSHIPS.CARD_DETAILS.ATTRIBUTES.BASIC_DESCRIPTION` | Crie e gerencie definições de campos personalizados para a sua conta. | Crie os campos que a sua corretora usa, como Seguradora atual e Vencimento do seguro. |
| `RELATIONSHIPS.DESCRIPTION_HINT` | Descreva o objetivo do campo e como ele deve ser preenchido. | Diga para que serve o campo e como preencher. Ex.: data em que o seguro atual vence. |
| `RELATIONSHIPS.MEDIA.SUBTITLE` | Arquivos compartilhados nas conversas. | Apólices, boletos, documentos e fotos trocados nas conversas. |
| `RELATIONSHIPS.MEDIA.EMPTY_HINT` | Os arquivos das conversas autorizadas desta empresa aparecerão aqui. | Os arquivos das conversas autorizadas desta empresa, como apólices e boletos, aparecem aqui. |
| `RELATIONSHIPS.MEDIA.CONTACT_EMPTY_HINT` | Arquivos das conversas autorizadas deste contato aparecerão aqui. | Os arquivos das conversas autorizadas deste contato, como apólice, boleto e CNH, aparecem aqui. |
| `CONTACT_IMPORT_JOURNEY.SUBTITLE` | Suba a planilha. A gente acha as colunas, as empresas e as outras informações de cada contato. | Suba a planilha da sua carteira. A gente acha as colunas, as empresas e as outras informações, como seguradora e vencimento. |
| `CONTACT_IMPORT_JOURNEY.UPLOAD.HINT` | CSV ou Excel · até {size} MB · nome e celular ou e-mail; empresa e outras colunas são bem-vindas | CSV ou Excel · até {size} MB · nome e celular ou e-mail; empresa, seguradora, vencimento e outras colunas são bem-vindas |
| `CONTACT_IMPORT_JOURNEY.ATTRIBUTES.HINT` | Viram atributos do contato | Viram campos do contato, como seguradora e placa |

