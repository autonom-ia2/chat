require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 20 dos termos de aceite: "Venda fechada já entra no sistema da empresa".
#
# > "Quando a gente fecha, alguém tem que copiar tudo para o sistema de cobrança e mandar as boas-vindas. Quero que isso
# > aconteça sozinho." — Ricardo, dono da empresa
#
# Começa quando: o card é ganho.
#   1. A IA extrai da conversa o CNPJ, o e-mail do financeiro e o plano escolhido, se faltarem no card.
#   2. Faltou algum dado: pergunta ao cliente só o que falta e espera a resposta, por até 2 dias.
#   3. Manda os dados para o sistema de cobrança e grava no card o número de cliente que ele devolve.
#   4. O sistema de cobrança recusou: avisa o financeiro com o motivo que veio na resposta.
#   5. Manda o e-mail de boas-vindas com o link da agenda para a reunião de implantação.
#   6. Reunião marcada: move para "Implantação" e põe a etiqueta "cliente novo".
#   7. 30 dias depois, pelo modelo aprovado: pergunta como está o uso, e a IA decide "bem", "com dificuldade" ou "quer
#      cancelar".
#   8. Com dificuldade: manda o link da agenda para um treinamento. Quer cancelar: avisa o Ricardo com um resumo.
#   9. Bem: coloca o cliente na campanha de e-mail "Dicas do mês".
#
# Montado como o Ricardo montaria, pela API da tela, numa automação só, no card ganho do funil "Vendas" (G5):
# - Passo 1 (G70, decisão 20): o extrair grava direto nos campos do card. "Se faltarem" é o extrair que só preenche: o
#   valor que o card já tem fica.
# - Passo 2: um "se" com `alguma` das três chaves vazia no card; dentro, o "escrever" que pergunta só o que falta (a IA lê
#   o card), o "esperar até" a resposta do cliente (G11), com prazo de 2 dias, e o extrair de novo.
# - Passos 3 e 4 (G13): o sistema de cobrança é o passo "webhook". A resposta grava no card o número de cliente, ou o
#   motivo da recusa, que vai no aviso ao financeiro (`se_recusar`). O sistema é um receptor WebMock num nome que resolve
#   para um IP público, como no exemplo 14.
# - Passo 5 (G2, G44): o e-mail sai pela caixa de e-mail da empresa, com o link da página "Implantação" escolhida na
#   receita (`agenda.<id>`).
# - Passo 6 (G32): a reunião marcada é a condição do "esperar até" (`card.tem_reuniao_marcada`). O termo não dá prazo, e
#   o esquema exige um: 7 dias. O "se" depois dela só move e etiqueta com a reunião marcada. Nome de etiqueta na
#   plataforma não tem espaço: "cliente novo" é `cliente-novo`, no contato.
# - Passo 7 (G1, G11, G12): o "esperar" de 30 dias, a pergunta pelo modelo aprovado (a janela de 24 h já fechou), o
#   "esperar até" a resposta (o termo não dá prazo: 7 dias) e o "decidir".
# - Passo 8 (G44, "duas agendas"): o link da página "Treinamento"; o resumo ao Ricardo pelo "resumir" com aviso.
# - Passo 9 (G52, #2787): "coloca o cliente na campanha de e-mail" é o passo "Pôr na lista de e-mail" na lista "Dicas do
#   mês". A campanha de e-mail com a lista vai para quem está nela na hora do envio.
# A IA é o dublê no endereço da OpenAI (nenhuma chamada paga); o WhatsApp oficial para no receptor. Desenho e lacunas:
# docs/automacao/F9-fechamento-20-exemplos.md.
RSpec.describe 'Fechamento #2414 · exemplo 20: venda fechada já entra no sistema da empresa', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:ricardo) { create(:user, account: account, role: :administrator, name: 'Ricardo Dono') }
  let(:financeiro) { create(:user, account: account, role: :agent, name: 'Paula Financeiro') }
  let(:implantador) { create(:user, account: account, role: :agent, name: 'Igor Implantação') }
  let(:cliente) { create(:contact, account: account, name: 'Marina', email: 'marina@lojadamarina.com.br', phone_number: '+5511900002020') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: whatsapp, contact: cliente, source_id: '5511900002020')
    create(:conversation, account: account, inbox: whatsapp, contact: cliente, contact_inbox: contact_inbox, status: :open)
  end
  let(:vendas) { create_crm_pipeline(account: account, user: ricardo, name: 'Vendas') }
  let(:implantacao) { create_crm_stage(account: account, pipeline: vendas.first, name: 'Implantação', position: 2) }
  let(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, inbox: whatsapp, contact: cliente, primary_conversation: conversa,
                              owner: ricardo, title: 'Loja da Marina - plano Pro', currency: 'BRL')
  end
  let(:paginas) do
    { implantacao: create_booking_profile(account: account, host: implantador, title: 'Reunião de implantação'),
      treinamento: create_booking_profile(account: account, host: implantador, title: 'Treinamento') }
  end
  let(:dicas_do_mes) { EmailList.criar(account: account, name: 'Dicas do mês') }
  let(:roteiro) { { 'automacao_extrair' => dados_completos } }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def pedidos_a_cobranca = (@pedidos_a_cobranca ||= [])
  def whatsapp = canal.inbox
  def cobranca = 'https://api.cobranca.test/clientes'
  def chaves = %w[cnpj email_financeiro plano]
  def dados_completos = { 'cnpj' => '12.345.678/0001-90', 'email_financeiro' => 'financeiro@lojadamarina.com.br', 'plano' => 'Pro' }
  def card_id = { '$valor' => 'card.id' }
  def nome = { '$valor' => 'contato.nome' }
  def agenda(pagina) = { '$valor' => "agenda.#{paginas.fetch(pagina).id}" }
  def reuniao_marcada = { campo: { '$valor' => 'card.tem_reuniao_marcada' }, op: 'igual', valor: true }

  def resposta_do_cliente(id, dias)
    { id: id, tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
      prazo: { valor: dias, unidade: 'dias' } }
  end

  def receita
    { gatilho: { tipo: 'card.ganho', funil_id: vendas.first.id }, passos: [
      extrai('extrai'), faltou_algum_dado, para_a_cobranca, boas_vindas, *reuniao_de_implantacao, *trinta_dias_depois
    ] }
  end

  # Passo 1 e o fim do 2: o extrair só preenche, o que o card já tem fica.
  def extrai(id)
    descricoes = { 'cnpj' => 'o CNPJ da empresa do cliente', 'email_financeiro' => 'o e-mail do financeiro do cliente',
                   'plano' => 'o plano que o cliente escolheu' }
    { id: id, tipo: 'extrair', le: %w[mensagens_recentes],
      campos: chaves.map { |chave| { chave: chave, descricao: descricoes.fetch(chave), destino: "card.atributos.#{chave}" } } }
  end

  # Passo 2.
  def faltou_algum_dado
    falta = chaves.map { |chave| { campo: { '$valor' => "card.atributos.#{chave}" }, op: 'vazio' } }
    { id: 'faltou', tipo: 'se', condicao: { alguma: falta }, entao: [
      { id: 'pergunta', tipo: 'escrever', le: %w[card mensagens_recentes], destino: 'mensagem',
        instrucao: 'Pergunte ao cliente só os dados que ainda faltam no card: CNPJ, e-mail do financeiro ou plano escolhido.' },
      resposta_do_cliente('resposta_dos_dados', 2),
      extrai('extrai_a_resposta')
    ] }
  end

  # Passos 3 e 4.
  def para_a_cobranca
    recusou = { id: 'avisa_financeiro', tipo: 'avisar', para: { pessoas: [financeiro.id] },
                texto: ['O sistema de cobrança recusou o cadastro de ', nome, ': ', { '$valor' => 'card.atributos.motivo_da_recusa' }] }
    corpo = chaves.index_with { |chave| { '$valor' => "card.atributos.#{chave}" } }.merge(nome: nome)
    { id: 'cobranca', tipo: 'webhook', descricao: 'Cadastrar no sistema de cobrança', url: cobranca, corpo: corpo,
      gravar: [{ chave: 'cliente.numero', destino: 'card.atributos.numero_do_cliente' },
               { chave: 'motivo', destino: 'card.atributos.motivo_da_recusa' }],
      se_recusar: [recusou] }
  end

  # Passo 5.
  def boas_vindas
    { id: 'boas_vindas', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Bem-vinda à nossa plataforma'],
      texto: ['Oi ', nome, ', seja bem-vinda! Marque a reunião de implantação: ', agenda(:implantacao)] }
  end

  # Passo 6.
  def reuniao_de_implantacao
    [{ id: 'marcou', tipo: 'esperar_ate', condicao: reuniao_marcada, prazo: { valor: 7, unidade: 'dias' } },
     { id: 'se_marcou', tipo: 'se', condicao: reuniao_marcada, entao: [
       { id: 'para_implantacao', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Implantação', caminho: { id: card_id },
         corpo: { stage_id: implantacao.id } },
       { id: 'cliente_novo', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr a etiqueta cliente novo',
         caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['cliente-novo'] } }
     ] }]
  end

  # Passos 7 a 9.
  def trinta_dias_depois
    [{ id: 'trinta_dias', tipo: 'esperar', duracao: { valor: 30, unidade: 'dias' } },
     { id: 'como_esta', tipo: 'mensagem', texto: ['Como está o uso da plataforma?'],
       modelo: { nome: 'como_esta_o_uso', idioma: 'pt_BR', variaveis: [[nome]] } },
     resposta_do_cliente('resposta_do_uso', 7),
     { id: 'uso', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'Como o cliente está com o uso da plataforma?', caminhos: [
       { nome: 'Bem', chave: 'bem', descricao: 'está usando bem', passos: [{ id: 'dicas', tipo: 'lista_de_email', lista_id: dicas_do_mes.id }] },
       { nome: 'Com dificuldade', chave: 'dificuldade', descricao: 'está com dificuldade de usar', passos: [
         { id: 'treinamento', tipo: 'mensagem', texto: ['Vamos marcar um treinamento? Escolha o horário: ', agenda(:treinamento)] }
       ] },
       { nome: 'Quer cancelar', chave: 'quer_cancelar', descricao: 'quer cancelar', passos: [
         { id: 'avisa_ricardo', tipo: 'resumir', le: %w[mensagens_recentes], destino: { avisar: { pessoas: [ricardo.id] } } }
       ] }
     ], nenhum: [] }]
  end

  def atributo(chave)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: 'card_attribute', attribute_display_type: 'text')
  end

  def modelo_do_uso
    { 'name' => 'como_esta_o_uso', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, como está o uso da plataforma?' }] }
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [ricardo, financeiro, implantador].each { |pessoa| create(:inbox_member, user: pessoa, inbox: whatsapp) }
    campos_etiqueta_e_modelo
    [implantacao, paginas, dicas_do_mes, card]
  end

  # Os campos do card que o Ricardo criou, a etiqueta do passo 6 e o modelo aprovado do passo 7.
  def campos_etiqueta_e_modelo
    [*chaves, 'numero_do_cliente', 'motivo_da_recusa'].each { |chave| atributo(chave) }
    create(:label, account: account, title: 'cliente-novo', description: 'Cliente novo em implantação')
    canal.update!(message_templates: [modelo_do_uso])
  end

  # O sistema de cobrança: guarda cada pedido e responde o que o exemplo pede.
  def cobranca_responde(status, corpo)
    stub_request(:post, cobranca).to_return do |pedido|
      pedidos_a_cobranca << JSON.parse(pedido.body)
      { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Um job por vez, como no Sidekiq, com o do evento do card no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # O vendedor ganha o card às 15h de 10/11; a cliente tinha escrito há pouco, e a janela de 24 h está aberta.
  def venda_fechada
    as('2026-11-10 15:00') do
      Crm::Cards::Closer.new(card: card, actor: ricardo, result: 'won').perform
      drenar
    end
  end

  def cliente_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: whatsapp, message_type: :incoming, sender: cliente, content: texto)
      drenar
    end
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  # A cliente marca pela página "Reunião de implantação", no card ganho.
  def cliente_marca_as(hora)
    inicio = fuso.parse('2026-11-12 10:00')
    as(hora) do
      Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: implantador, params: {
                                           title: 'Reunião de implantação', starts_at: inicio, ends_at: inicio + 30.minutes,
                                           timezone: fuso.name, extra_guests: [], location_type: 'whatsapp_video',
                                           booking_profile_id: paginas[:implantacao].id
                                         }).perform
      drenar
    end
  end

  # Venda fechada com os dados completos, a reunião marcada no dia seguinte e os 30 dias passados: a pergunta do uso saiu.
  def ate_a_pergunta_do_uso
    venda_fechada
    cliente_marca_as('2026-11-11 09:00')
    varredura_as('2026-12-11 09:05')
  end

  def link(pagina) = Crm::BookingV2::ShortLink.url_for(paginas.fetch(pagina))
  def saidas = chamadas_para('graph.facebook.com')
  def textos_enviados = saidas.filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def modelos_enviados = saidas.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def cliente_do_banco = account.contacts.find(cliente.id)
  def execucao = Autonomia::Automacao::Execucao.sole
  def historico = Autonomia::Automacao::Registro.order(:id).pluck(:passo, :resultado, :motivo)
  def campos_do_card = card.reload.custom_attributes.slice(*chaves)

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.cobranca.test').and_return(['93.184.216.34'])
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
    cobranca_responde(201, { cliente: { numero: 'CLI-2020' } })
    as('2026-11-10 10:00') do
      preparar_conta
      create(:message, conversation: conversa, account: account, inbox: whatsapp, message_type: :incoming, sender: cliente,
                       content: 'Fechado! Vamos de plano Pro. CNPJ 12.345.678/0001-90, financeiro@lojadamarina.com.br no financeiro.')
      ligar_automacao(ricardo, account, montar_automacao(ricardo, account, nome: 'Venda fechada no sistema de cobrança', receita: receita))
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passo 1: o card ganho dispara a IA, que grava no card o CNPJ, o e-mail do financeiro e o plano', :aggregate_failures do
    venda_fechada

    expect(campos_do_card).to eq(dados_completos)
    expect(pedidos_da_ia('automacao_extrair').sole.to_json).to include('CNPJ 12.345.678/0001-90')
    expect(historico.first).to eq(['extrai', 'ok', nil])
    expect(historico.map(&:first)).not_to include('pergunta')
    expect(textos_enviados).to be_empty
  end

  it 'passo 1: o dado que o card já tem fica; a IA só preenche o que falta', :aggregate_failures do
    card.update!(custom_attributes: { 'plano' => 'Enterprise' })

    venda_fechada

    expect(campos_do_card).to eq(dados_completos.merge('plano' => 'Enterprise'))
    expect(Autonomia::Automacao::Registro.find_by(passo: 'extrai').dados.dig('campos', 'ja_tinha')).to eq(['plano'])
  end

  context 'with o e-mail do financeiro faltando na conversa (passo 2)' do
    let(:roteiro) do
      { 'automacao_extrair' => dados_completos.merge('email_financeiro' => nil),
        'automacao_escrever' => { 'texto' => 'Marina, qual é o e-mail do financeiro para mandarmos as cobranças?' } }
    end

    before { venda_fechada }

    it 'pergunta só o que falta, lendo o card, e espera a resposta por até 2 dias', :aggregate_failures do
      expect(campos_do_card).to eq(dados_completos.except('email_financeiro'))
      expect(textos_enviados).to eq(['Marina, qual é o e-mail do financeiro para mandarmos as cobranças?'])
      expect(pedidos_da_ia('automacao_escrever').sole.to_json).to include('12.345.678/0001-90', 'só os dados que ainda faltam')
      expect([execucao.estado, execucao.cursor]).to eq(%w[esperando resposta_dos_dados])
      expect(execucao.due_at).to be_within(1.minute).of(fuso.parse('2026-11-12 15:00'))
      expect(pedidos_a_cobranca).to be_empty
    end

    it 'a resposta completa o card, e só então os dados vão à cobrança', :aggregate_failures do
      roteiro['automacao_extrair'] = dados_completos

      cliente_escreve_as('2026-11-11 09:00', 'O e-mail do financeiro é financeiro@lojadamarina.com.br')

      expect(campos_do_card).to eq(dados_completos)
      expect(Autonomia::Automacao::Registro.find_by(passo: 'extrai_a_resposta').dados.dig('campos', 'gravados')).to eq(['email_financeiro'])
      expect(pedidos_a_cobranca.sole).to include('email_financeiro' => 'financeiro@lojadamarina.com.br')
    end
  end

  it 'passo 3: os dados do card vão ao sistema de cobrança, e o card guarda o número de cliente', :aggregate_failures do
    venda_fechada

    expect(pedidos_a_cobranca.sole).to eq(dados_completos.merge('nome' => 'Marina'))
    expect(card.reload.custom_attributes).to include('numero_do_cliente' => 'CLI-2020')
    expect(card.custom_attributes).not_to have_key('motivo_da_recusa')
    expect(mencoes_para(financeiro)).to be_empty
    expect(Autonomia::Automacao::Registro.find_by(passo: 'cobranca')).to have_attributes(resultado: 'ok', motivo: nil)
  end

  it 'passo 4: a cobrança recusa; o card guarda o motivo e o financeiro é avisado com ele', :aggregate_failures do
    cobranca_responde(422, { motivo: 'CNPJ inativo na Receita Federal' })

    venda_fechada

    expect(card.reload.custom_attributes).to include('motivo_da_recusa' => 'CNPJ inativo na Receita Federal')
    expect(card.custom_attributes).not_to have_key('numero_do_cliente')
    expect(mencoes_para(financeiro).count).to eq(1)
    aviso = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{financeiro.id}/%").sole
    expect(aviso.content).to include('O sistema de cobrança recusou o cadastro de Marina: CNPJ inativo na Receita Federal')
    expect(Autonomia::Automacao::Registro.where(passo: %w[cobranca avisa_financeiro]).order(:id).pluck(:passo, :resultado, :motivo))
      .to eq([%w[cobranca ok webhook_recusado], ['avisa_financeiro', 'ok', nil]])
  end

  it 'passo 5: o e-mail de boas-vindas sai com o link da página de implantação', :aggregate_failures do
    venda_fechada

    email = Conversation.where(inbox: caixa_de_email).sole
    expect(email.contact).to eq(cliente)
    expect(email.additional_attributes['mail_subject']).to eq('Bem-vinda à nossa plataforma')
    expect(email.messages.outgoing.sole.content).to eq("Oi Marina, seja bem-vinda! Marque a reunião de implantação: #{link(:implantacao)}")
    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando marcou])
  end

  it 'passo 6: a reunião marcada leva o card para "Implantação" e põe a etiqueta cliente-novo', :aggregate_failures do
    venda_fechada
    expect(cliente_do_banco.label_list).to be_empty

    cliente_marca_as('2026-11-11 09:00')

    expect(card.reload.stage_id).to eq(implantacao.id)
    expect(cliente_do_banco.label_list).to eq(['cliente-novo'])
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando trinta_dias])
  end

  it 'passo 6: sem reunião marcada em 7 dias, o card não sai da etapa nem ganha a etiqueta', :aggregate_failures do
    venda_fechada
    etapa = card.reload.stage_id

    varredura_as('2026-11-17 15:05')

    expect(card.reload.stage_id).to eq(etapa)
    expect(cliente_do_banco.label_list).to be_empty
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando trinta_dias])
  end

  it 'passo 7: 30 dias depois, a pergunta do uso sai pelo modelo aprovado, e a automação espera a resposta', :aggregate_failures do
    venda_fechada
    cliente_marca_as('2026-11-11 09:00')
    varredura_as('2026-12-10 09:05')
    expect(modelos_enviados).to be_empty

    varredura_as('2026-12-11 09:05')

    expect(modelos_enviados).to eq(%w[como_esta_o_uso])
    expect(saidas.last.corpo.dig('template', 'components', 0, 'parameters').pluck('text')).to eq(['Marina'])
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando resposta_do_uso])
  end

  it 'passo 7: a IA decide lendo a resposta da cliente', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'bem', 'motivo' => 'disse que está usando todo dia' }
    ate_a_pergunta_do_uso

    cliente_escreve_as('2026-12-11 14:00', 'Está ótimo, a equipe usa todo dia!')

    expect(pedidos_da_ia('automacao_decidir').sole.to_json).to include('a equipe usa todo dia')
    expect(Autonomia::Automacao::Registro.find_by(passo: 'uso').dados['ramo']).to eq('bem')
  end

  it 'passo 8: com dificuldade, a cliente recebe o link da página de treinamento', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'dificuldade', 'motivo' => 'não acha os relatórios' }
    ate_a_pergunta_do_uso

    cliente_escreve_as('2026-12-11 14:00', 'Ainda não consegui achar os relatórios.')

    expect(textos_enviados.last).to eq("Vamos marcar um treinamento? Escolha o horário: #{link(:treinamento)}")
    expect(mencoes_para(ricardo)).to be_empty
    expect(cliente_do_banco.label_list).not_to include(dicas_do_mes.label.title)
  end

  it 'passo 8: quer cancelar, e o Ricardo recebe no sino o resumo', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'quer_cancelar', 'motivo' => 'quer cancelar' }
    roteiro['automacao_resumir'] = { 'resumo' => 'Marina quer cancelar: a equipe voltou para a planilha.' }
    ate_a_pergunta_do_uso

    cliente_escreve_as('2026-12-11 14:00', 'Quero cancelar, a equipe voltou para a planilha.')

    expect(mencoes_para(ricardo).count).to eq(1)
    aviso = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{ricardo.id}/%").sole
    expect(aviso.content).to include('Marina quer cancelar: a equipe voltou para a planilha.')
    expect(cliente_do_banco.label_list).not_to include(dicas_do_mes.label.title)
  end

  it 'passo 9: bem, e a cliente entra na lista "Dicas do mês"; a campanha de e-mail da lista vai para ela', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'bem', 'motivo' => 'está usando bem' }
    ate_a_pergunta_do_uso

    cliente_escreve_as('2026-12-11 14:00', 'Está ótimo, a equipe usa todo dia!')

    expect(cliente_do_banco.label_list).to contain_exactly('cliente-novo', dicas_do_mes.label.title)
    expect(Autonomia::Automacao::Registro.find_by(passo: 'dicas')).to have_attributes(resultado: 'ok', motivo: nil)
    campanha = create(:email_campaign, account: account)
    campanha.update!(email_list: dicas_do_mes)
    expect(campanha.email_campaign_recipients.pluck(:email, :status, :contact_id))
      .to eq([['marina@lojadamarina.com.br', 'pending', cliente.id]])
    expect(execucao.reload.estado).to eq('concluida')
  end
end
