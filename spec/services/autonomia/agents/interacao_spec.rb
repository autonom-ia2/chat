require 'rails_helper'

# #1479 F1: opções e botão de link na resposta do agente. Quem pode receber o campo, o que o modelo pediu (conferido)
# e como sai em cada caixa.
RSpec.describe Autonomia::Agents::Interacao do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox) }
  let(:agent) { criar_principal(account) }
  let(:delivery) { instance_double(Autonomia::Agents::Tools::Delivery, conversation: conversation) }

  let(:tres) do
    [{ 'id' => 'manha', 'titulo' => 'Manhã', 'descricao' => nil }, { 'id' => 'tarde', 'titulo' => 'Tarde', 'descricao' => nil },
     { 'id' => 'noite', 'titulo' => 'Noite', 'descricao' => nil }]
  end
  let(:pedido) { { 'tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?', 'opcoes' => tres, 'botao' => nil, 'link' => nil } }
  let(:opcoes) { described_class.do_modelo(pedido, contexto: '') }
  let(:link) { described_class.do_modelo({ 'tipo' => 'link', 'link' => { 'rotulo' => 'Abrir proposta', 'url' => url } }, contexto: "veja #{url}") }
  let(:url) { 'https://exemplo.com.br/proposta?a=1&b=2' }

  def janela_aberta(conversa = conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversa, inbox: conversa.inbox, account: account)
  end

  def conversa_em(channel)
    create(:conversation, account: account, inbox: channel.inbox).tap { |conversa| janela_aberta(conversa) }
  end

  describe '.disponivel?' do
    it 'vale no atendimento ao cliente, com a Fase 2, numa caixa que leva o formato' do
      expect(described_class.disponivel?(agent: agent, delivery: delivery, audience: :customer)).to be(true)
    end

    it 'não vale com a Fase 2 desligada' do
      agente = criar_principal(conta_da_fase2(ligada: false))
      expect(described_class.disponivel?(agent: agente, delivery: delivery, audience: :customer)).to be(false)
    end

    it 'não vale sem contexto de entrega (Testar, copiloto, Guia)' do
      expect(described_class.disponivel?(agent: agent, delivery: nil, audience: :customer)).to be(false)
    end

    it 'não vale para o atendente' do
      expect(described_class.disponivel?(agent: agent, delivery: delivery, audience: :attendant)).to be(false)
    end

    it 'não vale para a Lia' do
      lia = instance_double(Autonomia::Agents::Agent, agent_type: 'insurance_quote', account: account)
      expect(described_class.disponivel?(agent: lia, delivery: delivery, audience: :customer)).to be(false)
    end

    it 'não vale no e-mail nem no chat do site; vale na caixa API' do
      email = conversa_em(create(:channel_email, account: account))
      widget = conversa_em(create(:channel_widget, account: account))
      api = conversa_em(create(:channel_api, account: account))
      resultado = [email, widget, api].map do |conversa|
        entrega = instance_double(Autonomia::Agents::Tools::Delivery, conversation: conversa)
        described_class.disponivel?(agent: agent, delivery: entrega, audience: :customer)
      end
      expect(resultado).to eq([false, false, true])
    end
  end

  describe 'INSTRUCAO' do
    it 'diz que a pergunta das opções não lista as alternativas, que vão nos botões' do
      expect(described_class::INSTRUCAO).to include('Ela NÃO lista as alternativas, porque elas vão nos botões ' \
                                                    '(ex.: "Qual período você prefere?").')
    end

    it 'mantém as regras do cabeçalho, do reply sem repetição e do link só com endereço escrito' do
      expect(described_class::INSTRUCAO).to include('`header`: SEMPRE um título curto do assunto',
                                                    'NÃO repita a pergunta nem as opções em `reply`',
                                                    'Nunca invente nem monte endereço')
    end
  end

  describe '.do_modelo' do
    it 'ignora o que não é interação' do
      expect([nil, 'opcoes', { 'tipo' => 'mapa' }].map { |valor| described_class.do_modelo(valor, contexto: '') }).to all(be_nil)
    end

    it 'guarda as opções; sem texto do modelo, o botão da lista fica para a entrega' do
      expect(opcoes).to eq('tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?', 'botao' => nil,
                           'opcoes' => [{ 'id' => 'manha', 'title' => 'Manhã', 'description' => nil },
                                        { 'id' => 'tarde', 'title' => 'Tarde', 'description' => nil },
                                        { 'id' => 'noite', 'title' => 'Noite', 'description' => nil }])
    end

    it 'usa o botão da lista escolhido pelo modelo' do
      expect(described_class.do_modelo(pedido.merge('botao' => 'Ver horários'), contexto: '')['botao']).to eq('Ver horários')
    end

    it 'aceita o link cujo endereço está no texto do turno' do
      expect(link).to eq('tipo' => 'link', 'rotulo' => 'Abrir proposta', 'url' => url)
    end

    it 'descarta o link cujo endereço não está no texto do turno' do
      pedido_de_link = { 'tipo' => 'link', 'link' => { 'rotulo' => 'Abrir', 'url' => 'https://inventado.com/x' } }
      expect(described_class.do_modelo(pedido_de_link, contexto: 'veja https://inventado.com/')).to be_nil
    end

    it 'descarta o link sem endereço' do
      expect(described_class.do_modelo({ 'tipo' => 'link', 'link' => { 'rotulo' => 'Abrir', 'url' => '' } }, contexto: 'x')).to be_nil
      expect(described_class.do_modelo({ 'tipo' => 'link', 'link' => nil }, contexto: 'x')).to be_nil
    end
  end

  describe '.mensagem' do
    it 'WhatsApp oficial com a janela aberta: botões, com cabeçalho e a pergunta no corpo' do
      janela_aberta
      final = described_class.mensagem(opcoes, texto: 'Temos vaga amanhã.', conversation: conversation)
      expect(final[:content]).to eq("Temos vaga amanhã.\n\nQual período?")
      expect(final[:rich_message]).to eq('type' => 'options', 'header' => 'Agendamento', 'button' => 'See options',
                                         'options' => [{ 'id' => 'manha', 'title' => 'Manhã' }, { 'id' => 'tarde', 'title' => 'Tarde' },
                                                       { 'id' => 'noite', 'title' => 'Noite' }])
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:native)
    end

    it 'o botão da lista sem texto do modelo sai no idioma da conta (en e pt_BR)' do
      janela_aberta
      botoes = %w[en pt_BR].map do |idioma|
        account.update!(locale: idioma)
        described_class.mensagem(opcoes, texto: nil, conversation: conversation.reload)[:rich_message]['button']
      end
      expect(botoes).to eq(['See options', 'Ver opções'])
    end

    it 'o botão escolhido pelo modelo vale em qualquer idioma' do
      janela_aberta
      account.update!(locale: 'pt_BR')
      final = described_class.mensagem(opcoes.merge('botao' => 'Ver horários'), texto: nil, conversation: conversation.reload)
      expect(final[:rich_message]['button']).to eq('Ver horários')
    end

    it 'mais de 3 opções sai como lista, até 10' do
      janela_aberta
      dez = (1..10).map { |n| { 'id' => "o#{n}", 'titulo' => "Opção #{n}", 'descricao' => nil } }
      interacao = described_class.do_modelo(pedido.merge('opcoes' => dez), contexto: '')
      final = described_class.mensagem(interacao, texto: nil, conversation: conversation)
      expect(final[:content]).to eq('Qual período?')
      expect(RichMessages.build(Message.new(content_attributes: { 'rich_message' => final[:rich_message] }))
               .whatsapp_cloud_payload('x')[:interactive][:type]).to eq('list')
    end

    it 'mais de 10 opções sai em texto, com as opções numeradas' do
      janela_aberta
      onze = (1..11).map { |n| { 'id' => "o#{n}", 'titulo' => "Opção #{n}", 'descricao' => nil } }
      interacao = described_class.do_modelo(pedido.merge('opcoes' => onze), contexto: '')
      final = described_class.mensagem(interacao, texto: nil, conversation: conversation)
      expect(final[:rich_message]).to be_nil
      expect(final[:content]).to start_with("Qual período?\n\n1. Opção 1\n2. Opção 2")
      expect(final[:content]).to end_with('11. Opção 11')
    end

    it 'sem cabeçalho sai em texto: a pergunta e as opções numeradas' do
      janela_aberta
      final = described_class.mensagem(opcoes.merge('header' => nil), texto: 'Temos vaga.', conversation: conversation)
      expect(final).to eq(content: "Temos vaga.\n\nQual período?\n\n1. Manhã\n2. Tarde\n3. Noite", rich_message: nil)
    end

    it 'cabeçalho com mais de 60 caracteres sai em texto' do
      janela_aberta
      final = described_class.mensagem(opcoes.merge('header' => 'a' * 61), texto: nil, conversation: conversation)
      expect(final[:rich_message]).to be_nil
    end

    it 'WhatsApp oficial com a janela fechada leva o formato: o painel decide (texto na oficial, Híbrido pela rota dele)' do
      final = described_class.mensagem(opcoes, texto: nil, conversation: conversation)
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:text)
      expect(final[:rich_message]).to include('type' => 'options')
    end

    it 'caixa API leva o formato (o painel manda a versão em texto)' do
      final = described_class.mensagem(opcoes, texto: nil, conversation: conversa_em(create(:channel_api, account: account)))
      expect(final[:rich_message]).to include('type' => 'options')
    end

    it 'e-mail e chat do site nunca recebem rich_message' do
      [create(:channel_email, account: account), create(:channel_widget, account: account)].each do |channel|
        final = described_class.mensagem(opcoes, texto: 'Temos vaga.', conversation: conversa_em(channel))
        expect(final).to eq(content: "Temos vaga.\n\nQual período?\n\n1. Manhã\n2. Tarde\n3. Noite", rich_message: nil)
      end
    end

    it 'link: botão de link com o texto no corpo' do
      janela_aberta
      final = described_class.mensagem(link, texto: 'Sua proposta está pronta.', conversation: conversation)
      expect(final).to eq(content: 'Sua proposta está pronta.',
                          rich_message: { 'type' => 'link_button', 'label' => 'Abrir proposta', 'url' => url })
    end

    it 'link fora do contrato (rótulo longo) sai em texto, com o endereço' do
      janela_aberta
      final = described_class.mensagem(link.merge('rotulo' => 'a' * 21), texto: 'Sua proposta.', conversation: conversation)
      expect(final).to eq(content: "Sua proposta.\n\n#{'a' * 21}: #{url}", rich_message: nil)
    end

    it 'não grava nem acrescenta mensagem à conversa ao conferir' do
      janela_aberta
      expect { described_class.mensagem(opcoes, texto: 'x', conversation: conversation) }.not_to change(Message, :count)
      expect(conversation.messages.reload.size).to eq(1)
    end
  end

  describe '.nos_pedacos' do
    let(:pedacos) { [{ 'text' => 'Temos vaga.', 'type' => 'text', 'delay_ms' => 900 }, { 'text' => 'Amanhã.', 'type' => 'text', 'delay_ms' => 800 }] }

    before { janela_aberta }

    it 'opções: um pedaço a mais, com a pergunta e o formato; os outros sem formato' do
      novos = described_class.nos_pedacos(pedacos, opcoes, conversation: conversation)
      expect(novos.size).to eq(3)
      expect(novos.first(2)).to eq(pedacos)
      expect(novos.last).to include('text' => 'Qual período?', 'rich_message' => hash_including('type' => 'options'))
      expect(novos.last['delay_ms']).to be_a(Integer)
    end

    it 'link: o formato vai no último pedaço da resposta' do
      novos = described_class.nos_pedacos(pedacos, link, conversation: conversation)
      expect(novos.size).to eq(2)
      expect(novos.first).to eq(pedacos.first)
      expect(novos.last).to include('text' => 'Amanhã.', 'rich_message' => hash_including('type' => 'link_button'))
    end

    it 'sem interação ou sem pedaço, nada muda' do
      expect(described_class.nos_pedacos(pedacos, nil, conversation: conversation)).to eq(pedacos)
      expect(described_class.nos_pedacos([], opcoes, conversation: conversation)).to eq([])
    end
  end
end
