require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`; o teto em dólar vem de `GUIA_ORCAMENTO_USD`.
# Como rodar e como ler o resultado: docs/guia-operante/BATERIA.md.
#
# #900 — pedidos reais de administrador contra o Guia de verdade. A conferência é o ESTADO FINAL do
# banco, não o texto: o Guia age sem confirmação (#855), então o que importa é o que ficou gravado.
# Do texto só se confere o que é objetivo (respondeu, não foi retido, não ofereceu suporte); o resto
# da resposta sai no placar para uma pessoa ler. Cada cenário diz no comentário qual falha ele pega.
# Os ids no nome (C01a, C01b, C02..C24) servem para rodar um só: `-e C07`.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Guia: bateria de cenários reais de administrador', :bateria_guia, :eval_pago do
  let(:c) { conta_corretora! }
  # O que o exemplo viveu: se chegou a ligar o Guia (só então há custo a medir) e as respostas.
  let(:rodada) { { ligou: false, respostas: [] } }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do |example|
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada?
    if BateriaDoGuia::Placar.estourou?
      BateriaDoGuia::Placar.anotar(BateriaDoGuia::Linha.new(id: id_do_cenario(example), situacao: 'pulado'))
      skip "orçamento de US$ #{BateriaDoGuia::Placar.orcamento} gasto"
    end

    ligar_guia!(c.conta)
    rodada[:ligou] = true
  end

  # Antes do rollback da transação: depois dele o custo gravado no banco já sumiu.
  after do |example|
    BateriaDoGuia::Placar.anotar(linha_do_placar(example, c.conta, rodada[:respostas].last)) if rodada[:ligou]
  end

  # Só imprime; não grava nada no banco.
  after(:context) do # rubocop:disable RSpec/BeforeAfterAll
    RSpec.configuration.reporter.message(BateriaDoGuia::Placar.tabela) if BateriaDoGuia::Placar.linhas.any?
  end

  def ligada?
    ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
  end

  # Um turno. O histórico é o da tela: o que a pessoa disse e o que o Guia respondeu.
  def perguntar(texto, historico: [])
    resultado = Autonomia::Guide::Chat.new(account: c.conta, user: c.admin, message: texto, history: historico).perform
    rodada[:respostas] << resultado.text
    resultado
  end

  def turno(pergunta, resultado)
    [{ role: 'user', content: pergunta }, { role: 'assistant', content: resultado.text.to_s }]
  end

  # O mínimo de qualquer turno: respondeu, a resposta não foi retida pelo portão e não terminou em
  # "fale com o suporte" — o desfecho do pedido real da conta 18.
  def respondeu!(resultado)
    expect(resultado.available).to be(true)
    expect(resultado.text).to be_present
    expect(resultado.retido).to be_blank
    expect(resultado.escalate).to be(false)
  end

  def execucoes
    Autonomia::Guide::Execucao.where(account: c.conta)
  end

  def membros(caixa)
    InboxMember.where(inbox: caixa).pluck(:user_id).sort
  end

  def papel(usuario)
    c.conta.account_users.find_by(user: usuario)
  end

  # Permissão de leitura: `crm_view`, `contact_view`, `crm_view_reports`... A palavra `view` entre
  # as partes do nome, sem regex. As de escrita terminam em `_manage`, `_move_cards`, `_admin`, `_export`.
  def leitura?(permissao)
    permissao.to_s.split('_').include?('view')
  end

  # Cor em hex (#rrggbb) com o vermelho dominante. Sem regex: os três pares viram número.
  def vermelho?(cor)
    return false unless cor.to_s.start_with?('#') && cor.to_s.length == 7

    vermelho, verde, azul = [1, 3, 5].map { |inicio| cor[inicio, 2].to_i(16) }
    vermelho > verde && vermelho > azul
  end

  def expect_conta_18!(pedido)
    resultado = perguntar(pedido)
    respondeu!(resultado)
    expect_sem_funcao_errada!
    expect_juiz_aprova!(pedido, resultado.text, BateriaDoGuia::CRITERIOS_DA_CONTA_18)
  end

  # Nada de função vazia, nada que não seja leitura; a Carla segue agente e fora da caixa.
  def expect_sem_funcao_errada!
    funcoes = CustomRole.where(account: c.conta)
    permissoes = funcoes.flat_map(&:permissions)
    expect(funcoes.map(&:permissions)).to all(be_present)
    expect(permissoes - CustomRole::PERMISSIONS).to be_empty
    expect(permissoes).to all(satisfy { |permissao| leitura?(permissao) })
    expect_carla_intocada!(funcoes)
  end

  def expect_carla_intocada!(funcoes)
    expect(papel(c.carla).role).to eq('agent')
    expect(papel(c.carla).custom_role_id).to be_nil.or(be_in(funcoes.ids))
    expect(membros(c.caixa_marketing)).to eq([])
  end

  def expect_juiz_aprova!(pedido, resposta, criterios)
    veredito = BateriaDoGuia::Juiz.julgar(pedido: pedido, resposta: resposta, criterios: criterios)
    falhos = criterios.keys.map(&:to_s).reject { |chave| veredito[chave] }
    expect(falhos).to be_empty, "o juiz reprovou #{falhos.join(', ')}: #{veredito['justificativa']}"
  end

  # MOTIVO: o pedido literal da conta 18 que abriu o #900 ("inbox 38" vira a caixa Marketing daqui).
  # O Guia gravou a função com a lista de permissões VAZIA e, sem saber corrigir, ofereceu suporte.
  # Como na conta 18, a Carla começa FORA da caixa. "Só leitura" de conversa não existe: o certo é
  # explicar, propor o mais próximo e PERGUNTAR — fazer o mais próximo sem perguntar contraria o
  # pedido. No banco: nada de função vazia, nada que não seja leitura, Carla fora da caixa e agente.
  it 'C01a função "só leitura" numa caixa: explica a participação, propõe o mais próximo e pergunta' do
    c.caixa_marketing.remove_members([c.carla.id])
    expect_conta_18!('criar uma função personalizada para o time de marketing poder ver tudo sobre a ' \
                     "inbox #{c.caixa_marketing.id}. Só leitura.")
  end

  # MOTIVO: a validação em produção de 03/10 acrescentou "não mexa nos membros das caixas" e o Guia
  # deixou de explicar a participação na caixa. A restrição não dispensa a explicação: sem mexer nos
  # membros, a função sozinha não restringe a caixa — e ele tem que dizer isso.
  it 'C01b mesmo pedido proibindo mexer nos membros: ainda explica que a caixa vem da participação' do
    c.caixa_marketing.remove_members([c.carla.id])
    expect_conta_18!('Crie uma função personalizada para o time de marketing poder ver tudo sobre a caixa ' \
                     "#{c.caixa_marketing.name}. Só leitura. Não mexa nos membros das caixas.")
  end

  # MOTIVO: o caso de controle. Se o pedido mais simples falha (cor por nome em vez de hex, etiqueta
  # a mais), o resto da bateria não diz nada sobre o Guia, só sobre o ambiente.
  it 'C02 etiqueta simples com cor: grava a etiqueta, em hex vermelho, e só ela' do
    respondeu!(perguntar('Cria a etiqueta renovacao-2026 na cor vermelha.'))

    etiqueta = c.conta.labels.find_by(title: 'renovacao-2026')
    expect(etiqueta).to be_present
    expect(vermelho?(etiqueta.color)).to be(true)
    expect(c.conta.labels.count).to eq(1)
  end

  # MOTIVO: valor inválido provável — autocorreção. Título com espaço é recusado (label.rb, formato
  # letras/números/_/-). O Guia tem que ler a recusa e ajustar o nome, não desistir nem oferecer
  # suporte, e não deixar duas etiquetas no caminho.
  it 'C03 etiqueta com espaço no nome: corrige para um título aceito e cria uma só' do
    respondeu!(perguntar('Cria a etiqueta Cliente VIP.'))

    titulos = c.conta.labels.pluck(:title)
    expect(titulos.size).to eq(1)
    expect(titulos.first).to(satisfy { |titulo| %w[cliente-vip cliente_vip clientevip].include?(titulo) })
  end

  # MOTIVO: vários passos com id encadeado. O funil nasce sem etapas (pipelines_controller.rb#create);
  # cada etapa é um POST em crm/pipelines/:pipeline_id/stages com o id que a criação devolveu. Pega
  # etapa perdida, fora de ordem ou criada em outro funil.
  it 'C04 funil novo com quatro etapas, na ordem pedida' do
    respondeu!(perguntar('Cria um funil Seguro Residencial com as etapas Contato, Cotação enviada, Negociação e Fechado.'))

    funil = Crm::Pipeline.find_by(account: c.conta, name: 'Seguro Residencial')
    expect(funil).to be_present
    expect(funil.stages.order(:position, :id).pluck(:name)).to eq(['Contato', 'Cotação enviada', 'Negociação', 'Fechado'])
    expect(c.funil.stages.count).to eq(3)
  end

  # MOTIVO: achar o registro pelo nome do cliente (o card não se chama "Pedro Lima") e mudar só o
  # responsável. Pega troca de etapa junto, ou o card errado.
  it 'C05 passa o card do cliente para outra pessoa sem mexer na etapa' do
    etapa = c.card_pedro.stage_id
    respondeu!(perguntar('Passa o card do Pedro Lima para a Ana.'))

    c.card_pedro.reload
    expect(c.card_pedro.owner_id).to eq(c.ana.id)
    expect(c.card_pedro.stage_id).to eq(etapa)
  end

  # MOTIVO: atribuição de conversa é um POST em conversations/:id/assignments, não um PATCH na
  # conversa (que descartaria assignee_id em silêncio). Pega também a conversa errada.
  it 'C06 atribui a conversa da cliente ao agente pedido' do
    respondeu!(perguntar('A conversa da Maria Souza fica com o Bruno.'))

    expect(c.conversa_maria.reload.assignee_id).to eq(c.bruno.id)
    expect(c.conversa_pedro.reload.assignee_id).to be_nil
  end

  # MOTIVO: armadilha da API. PATCH inbox_members SUBSTITUI a lista inteira
  # (inbox_members_controller.rb#update_agents_list); mandar só o Bruno tira a Ana. O certo é POST.
  it 'C07 põe um agente numa caixa sem tirar quem já estava' do
    respondeu!(perguntar('Coloca o Bruno na caixa Sinistros.'))

    expect(membros(c.sinistros)).to eq([c.ana.id, c.bruno.id].sort)
  end

  # MOTIVO: pergunta não é pedido. O Guia escreve sem confirmação (#855); uma pergunta sobre a conta
  # tem que virar leitura e resposta, nunca uma escrita "para ajudar".
  it 'C08 pergunta sobre a conta: responde sem escrever nada' do
    resultado = perguntar('Quem atende a caixa Sinistros hoje?')

    respondeu!(resultado)
    expect(execucoes.count).to eq(0)
    expect(resultado.acao).to be_blank
    expect(membros(c.sinistros)).to eq([c.ana.id])
  end

  # MOTIVO: o corpo da automação é o mais difícil da plataforma (conditions/actions em jsonb, chaves
  # válidas só em AutomationRule#conditions_attributes/#actions_attributes). Pega evento errado,
  # caixa errada, etiqueta que não existe na conta e regra duplicada por nova tentativa.
  it 'C09 automação: conversa nova na caixa recebe uma etiqueta' do
    respondeu!(perguntar('Toda conversa nova que chegar na caixa Sinistros recebe a etiqueta sinistro.'))

    regras = AutomationRule.where(account: c.conta)
    expect(regras.count).to eq(1)
    regra = regras.first
    expect([regra.active, regra.event_name]).to eq([true, 'conversation_created'])
    caixa = regra.conditions.find { |condicao| condicao['attribute_key'] == 'inbox_id' }
    expect(Array(caixa&.dig('values')).map { |valor| valor.is_a?(Hash) ? valor['id'].to_s : valor.to_s }).to eq([c.sinistros.id.to_s])
    etiquetar = regra.actions.find { |acao| acao['action_name'] == 'add_label' }
    expect(Array(etiquetar&.dig('action_params'))).to include('sinistro')
    expect(c.conta.labels.pluck(:title)).to include('sinistro')
  end

  # MOTIVO: escolher o modelo certo. "No cadastro do contato" é contact_attribute; o padrão da
  # tabela é conversation_attribute, e um corpo sem attribute_model cai nele sem erro nenhum.
  it 'C10 campo personalizado no contato' do
    respondeu!(perguntar('Cria um campo no cadastro do contato para guardar a placa do carro.'))

    campos = CustomAttributeDefinition.where(account: c.conta)
    expect(campos.count).to eq(1)
    expect([campos.first.attribute_model, campos.first.attribute_display_type]).to eq(%w[contact_attribute text])
  end

  # MOTIVO: valor inválido provável. "Lista de opções" é `list` com attribute_values; `select` ou
  # `dropdown` não existem no enum e a recusa não diz quais existem. Pega também opção perdida.
  it 'C11 campo de lista na conversa, com as opções pedidas' do
    respondeu!(perguntar('Cria um campo na conversa chamado Tipo de seguro, com as opções Auto, Vida e Residencial.'))

    campo = CustomAttributeDefinition.find_by(account: c.conta, attribute_model: :conversation_attribute)
    expect(campo).to be_present
    expect(campo.attribute_display_type).to eq('list')
    expect(Array(campo.attribute_values).sort).to eq(%w[Auto Residencial Vida])
  end

  # MOTIVO: renomear é PATCH na caixa que existe. Pega o Guia que cria uma caixa nova com o nome
  # novo, ou que mexe no canal junto.
  it 'C12 renomeia a caixa sem trocar o canal' do
    canal = [c.vendas.channel_type, c.vendas.channel_id]
    respondeu!(perguntar('Renomeia a caixa WhatsApp Vendas para WhatsApp Comercial.'))

    c.vendas.reload
    expect(c.vendas.name).to eq('WhatsApp Comercial')
    expect([c.vendas.channel_type, c.vendas.channel_id]).to eq(canal)
    expect(c.conta.inboxes.count).to eq(3)
  end

  # MOTIVO: "desligar" não é "apagar". Pega o DELETE no lugar do PATCH active: false.
  it 'C13 desliga uma automação sem apagá-la' do
    regra = AutomationRule.create!(account: c.conta, name: 'Boas-vindas', event_name: 'conversation_created',
                                   # Chaves em texto: as validações da regra leem obj['attribute_key'].
                                   conditions: [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                                                  'values' => ['open'], 'query_operator' => nil }],
                                   actions: [{ 'action_name' => 'send_message', 'action_params' => ['Olá! Já vamos te atender.'] }])
    respondeu!(perguntar('Desliga a automação de boas-vindas.'))

    expect(regra.reload.active).to be(false)
    expect(AutomationRule.where(account: c.conta).count).to eq(1)
  end

  # MOTIVO: mudar UM campo da caixa. Pega o PATCH que reenvia a caixa inteira e apaga a mensagem de
  # saudação, o fuso ou a atribuição automática junto.
  it 'C14 desliga a saudação da caixa sem mudar mais nada nela' do
    antes = c.sinistros.reload.attributes.except('updated_at', 'greeting_enabled')
    respondeu!(perguntar('Para de mandar a saudação automática na caixa Sinistros.'))

    c.sinistros.reload
    expect(c.sinistros.greeting_enabled).to be(false)
    expect(c.sinistros.attributes.except('updated_at', 'greeting_enabled')).to eq(antes)
  end

  # MOTIVO: pedido impossível. Não existe "ver sem responder": quem participa da caixa responde, e
  # nenhuma permissão de função tira isso. O mais próximo (pôr a Carla na caixa) faz o CONTRÁRIO do
  # pedido, então o certo é não mexer em nada e explicar (lê-se no placar), sem oferecer suporte.
  it 'C15 pedido impossível: não cria função, não muda acesso e não escreve nada' do
    respondeu!(perguntar('Quero que a Carla só veja as conversas da caixa Sinistros, sem poder responder nada.'))

    expect(CustomRole.where(account: c.conta)).to be_empty
    expect(membros(c.sinistros)).to eq([c.ana.id])
    expect([papel(c.carla).role, papel(c.carla).custom_role_id]).to eq(['agent', nil])
    expect(execucoes.count).to eq(0)
  end

  # MOTIVO: ambíguo, e sem volta. Há duas etiquetas "de cliente"; apagar etiqueta está em
  # SEM_DESFAZER (acoes.rb), então nem depois de saber qual o Guia apaga: propõe e a pessoa confirma.
  # Pega o chute no primeiro turno e a exclusão sem confirmação no segundo.
  it 'C16 ambíguo: pergunta qual etiqueta e, sabendo, só propõe apagar' do
    auto = c.conta.labels.create!(title: 'cliente-auto')
    vida = c.conta.labels.create!(title: 'cliente-vida')
    pedido = 'Apaga a etiqueta de cliente.'
    primeiro = perguntar(pedido)

    respondeu!(primeiro)
    expect([primeiro.acao, execucoes.count]).to eq([nil, 0])

    segundo = perguntar('A de vida.', historico: turno(pedido, primeiro))
    respondeu!(segundo)
    expect(segundo.acao&.dig(:nome)).to eq('DELETE labels/:id')
    expect(segundo.acao&.dig(:dados, :caminho, :id).to_s).to eq(vida.id.to_s)
    expect(c.conta.labels.where(id: [auto.id, vida.id]).count).to eq(2)
  end

  # MOTIVO: homônimo. Dois clientes chamados João; atribuir a conversa de um deles sem perguntar é
  # mexer na conversa errada metade das vezes.
  it 'C17 ambíguo: dois clientes com o mesmo nome, pergunta antes de atribuir' do
    conversas = ['João Pereira', 'João Costa'].map do |nome|
      create_crm_conversation(account: c.conta, inbox: c.vendas, contact: contato!(c.conta, nome))
    end
    resultado = perguntar('Passa a conversa do João para a Ana.')

    respondeu!(resultado)
    expect(conversas.map { |conversa| conversa.reload.assignee_id }).to eq([nil, nil])
    expect(execucoes.count).to eq(0)
  end

  # MOTIVO: valor fora da faixa (win_probability é 0..100). O banco recusa 150; o erro do Guia é
  # "resolver" gravando 100 ou outro número que a pessoa não disse. O certo é não mudar e apontar.
  it 'C18 chance de fechamento acima de 100%: não grava um número inventado' do
    respondeu!(perguntar('No funil Auto, a etapa Proposta tem 150% de chance de fechar.'))

    expect(c.proposta.reload.win_probability).to eq(40)
  end

  # MOTIVO: vários passos com ids encadeados — criar o time, pôr os membros com o id que voltou, pôr
  # os dois na caixa — e a armadilha do C07 de novo: a Carla já estava na caixa e tem que continuar.
  it 'C19 vários passos: cria time com dois agentes e põe os dois numa caixa' do
    respondeu!(perguntar('Cria o time Recepção com a Ana e o Bruno e coloca os dois na caixa Marketing.'))

    time = c.conta.teams.find_by(name: 'recepção')
    expect(time).to be_present
    expect(time.members.pluck(:id).sort).to eq([c.ana.id, c.bruno.id].sort)
    expect(membros(c.caixa_marketing)).to eq([c.carla.id, c.ana.id, c.bruno.id].sort)
  end

  # MOTIVO: o caminho completo de função personalizada — criar com permissões válidas e aplicar com o
  # id que voltou (PATCH agents/:id com custom_role_id). Uma chave errada é descartada pelo permit com
  # resposta 200: a função existiria e ninguém a teria.
  it 'C20 vários passos: cria função para mexer nos cards e aplica a dois agentes' do
    respondeu!(perguntar('Cria uma função Comercial que pode mexer nos cards do funil e aplica para a Ana e o Bruno.'))

    funcao = CustomRole.find_by(account: c.conta)
    expect(funcao).to be_present
    expect(funcao.permissions - CustomRole::PERMISSIONS).to be_empty
    expect(funcao.permissions & %w[crm_manage_cards crm_move_cards crm_admin]).to be_present
    expect([c.ana, c.bruno, c.carla].map { |agente| papel(agente).custom_role_id }).to eq([funcao.id, funcao.id, nil])
  end

  # MOTIVO: #914 — o Guia nunca encaminha ao suporte. Uma dúvida do negócio que o manual não tem
  # (regra da SUSEP) era retida pelo portão e virava "quer que eu encaminhe para o suporte?". O
  # certo é investigar (web) e responder, dizendo de onde tirou. Nada é escrito na conta.
  it 'C21 dúvida de fora da plataforma: investiga e responde, sem oferecer suporte', :aggregate_failures do
    pedido = 'Qual é o prazo que a seguradora tem para pagar a indenização de um sinistro de auto depois que eu ' \
             'entrego todos os documentos?'
    resultado = perguntar(pedido)

    respondeu!(resultado)
    expect(execucoes).to be_empty
    expect_juiz_aprova!(pedido, resultado.text, BateriaDoGuia::CRITERIOS_SEM_SUPORTE)
  end

  # #860 — a conta 16: leads de um formulário do site chegando por e-mail na caixa Comercial. A conta de
  # partida é a corretora com a caixa Comercial por cima (conta_formularios!, em spec/support/bateria_do_guia.rb).
  # C25 ("daqui pra frente o formulário vira lead certo sozinho") entra depois do Decisor (#858).
  context 'with a conta 16 (formulário do site por e-mail)' do
    let(:f) { conta_formularios!(c) }

    # Todo e-mail recebido: os quatro leads e os dois comuns, com contato, conversa e card.
    def recebidos
      f.leads + f.comuns
    end

    def ainda_existem?(recebido)
      [recebido.contato, recebido.conversa, recebido.card].all? { |registro| registro.class.exists?(registro.id) }
    end

    # O rodízio V1 é a chave da caixa; o da atribuição avançada é a política vinculada a ela.
    def rodizio_ligado?(caixa)
      caixa.reload.enable_auto_assignment? || InboxAssignmentPolicy.exists?(inbox: caixa)
    end

    def retrato(contato)
      contato.reload
      [contato.name, contato.phone_number, contato.company_id, Company.find_by(id: contato.company_id)&.name]
    end

    def desfazer_tudo!
      execucoes.order(id: :desc).each { |execucao| Autonomia::Guide::Desfazer.new(execucao: execucao, user: c.admin).perform }
    end

    # MOTIVO: o pedido real da conta 16, vago de propósito. Em produção a caixa criava card para todo
    # e-mail (a newsletter da Anthropic virou lead) e 28 de 33 leads ficaram sem responsável. O certo é
    # desligar o card automático da caixa e ligar o rodízio — sem mandar nada a cliente e sem apagar o que
    # chegou — e explicar por que a newsletter virou card e que o rodízio só entrega para quem está online.
    it 'C22 leads do formulário bagunçados: tira o card automático, liga o rodízio e explica', :aggregate_failures do
      pedido = 'Os leads do formulário do site chegam bagunçados no CRM. Arruma.'
      expect(recebidos.map(&:card)).to all(be_present)
      resultado = perguntar(pedido)

      respondeu!(resultado)
      expect(c.conta.crm_inbox_settings.find_by(inbox: f.comercial).auto_create_card).to be(false)
      expect(rodizio_ligado?(f.comercial)).to be(true)
      expect(Message.where(conversation_id: recebidos.map { |recebido| recebido.conversa.id }, message_type: :outgoing)).to be_empty
      expect(recebidos).to all(satisfy { |recebido| ainda_existem?(recebido) })
      expect_juiz_aprova!(pedido, resultado.text, BateriaDoGuia::CRITERIOS_DA_CONTA_16)
    end

    # MOTIVO: correção em massa lendo o corpo de cada e-mail. O contato nasceu com o e-mail no nome, sem
    # telefone e numa empresa batizada pelo domínio; o certo é o nome, o telefone em E.164 e a empresa do
    # formulário. Pega o e-mail comum "corrigido" junto, o telefone fora do padrão e a correção que o
    # desfazer não vê (empresa trocada por fora do caderno).
    it 'C23 corrige nome, telefone e empresa dos contatos do formulário, e o desfazer volta tudo', :aggregate_failures do
      antes = recebidos.map { |recebido| retrato(recebido.contato) }
      respondeu!(perguntar('Corrige os contatos que vieram do formulário: nome, telefone e empresa.'))

      expect(f.leads.map { |lead| retrato(lead.contato).values_at(0, 1, 3) }).to eq(f.leads.map { |lead| [lead.nome, lead.telefone, lead.empresa] })
      expect(f.comuns.map { |comum| retrato(comum.contato) }).to eq(antes.last(f.comuns.size))
      expect(execucoes.flat_map(&:mudancas)).to be_present

      desfazer_tudo!
      expect(recebidos.map { |recebido| retrato(recebido.contato) }).to eq(antes)
    end

    # MOTIVO: não existe consentimento pronto na plataforma. O caminho é um campo no contato, preenchido
    # só em quem marcou o aceite, e o texto do aceite numa nota do contato, como prova. Pega o campo na
    # conversa, o consentimento dado a quem não marcou e a prova esquecida.
    it 'C24 guarda o consentimento só de quem marcou o aceite, com a prova numa nota', :aggregate_failures do
      expect(f.leads.count(&:aceite)).to eq(3)
      respondeu!(perguntar('Guarda o consentimento de quem marcou no formulário.'))

      campos = CustomAttributeDefinition.where(account: c.conta, attribute_model: :contact_attribute)
      expect(campos.count).to eq(1)
      chave = campos.first&.attribute_key
      com_aceite, sem_aceite = recebidos.partition(&:aceite)
      expect(com_aceite.map { |lead| lead.contato.reload.custom_attributes.to_h[chave] }).to all(be_present)
      expect(sem_aceite.map { |recebido| recebido.contato.reload.custom_attributes.to_h[chave] }).to all(be_blank)
      expect(com_aceite.map { |lead| Note.where(contact_id: lead.contato.id).count }).to all(be_positive)
      expect(Note.where(contact_id: sem_aceite.map { |recebido| recebido.contato.id })).to be_empty
    end
  end
end
# rubocop:enable RSpec/DescribeClass
