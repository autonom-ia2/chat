require 'rails_helper'

# #1941, item 5: a conversa "Integração WhatsApp" do conector WAHA sai da lista, das contagens, dos filtros e da tela
# inicial. Um critério só: o contato com identifier `whatsapp.integration`.
describe Waha::IntegracaoDoConector do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 's1' }) }
  let(:inbox) { channel.inbox }
  let(:integracao) { create(:contact, account: account, name: 'Integração WhatsApp', identifier: described_class::IDENTIFIER) }
  let!(:interna) { create(:conversation, account: account, inbox: inbox, contact: integracao) }
  let!(:cliente) { create(:conversation, account: account, inbox: inbox) }

  before { Current.account = account }

  after { Current.reset }

  it 'o scope deixa de fora só a conversa do conector' do
    expect(account.conversations.fora_da_integracao_whatsapp).to contain_exactly(cliente)
  end

  it 'não confunde com contato de identifier parecido nem com contato sem identifier' do
    parecido = create(:conversation, account: account, inbox: inbox,
                                     contact: create(:contact, account: account, identifier: 'whatsapp.integration.2'))

    expect(account.conversations.fora_da_integracao_whatsapp).to contain_exactly(cliente, parecido)
  end

  it 'a lista e as contagens não trazem a conversa do conector' do
    resultado = ConversationFinder.new(admin, { status: 'open' }).perform

    expect(resultado[:conversations]).to contain_exactly(cliente)
    expect(resultado[:count][:all_count]).to eq(1)
    expect(resultado[:count][:unassigned_count]).to eq(1)
  end

  it 'a busca na caixa também não traz' do
    resultado = ConversationFinder.new(admin, { status: 'open', inbox_id: inbox.id }).perform

    expect(resultado[:conversations]).to contain_exactly(cliente)
  end

  it 'os filtros avançados não trazem a conversa do conector' do
    params = { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
    resultado = Conversations::FilterService.new(params.with_indifferent_access, admin, account).perform

    expect(resultado[:conversations]).to contain_exactly(cliente)
    expect(resultado[:count][:all_count]).to eq(1)
  end

  it 'a tela inicial não conta a conversa do conector, nem na equipe' do
    resumo = TelaInicial::Resumo.new(account: account, user: admin, account_user: account.account_users.find_by(user: admin)).perform

    expect(resumo[:sem_responsavel]).to eq(1)
    expect(resumo[:equipe][:esperam]).to eq(1)
  end

  describe 'não lidas' do
    before do
      [interna, cliente].each do |conversa|
        create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, sender: conversa.contact)
      end
    end

    it 'os contadores não contam a conversa do conector' do
      query = { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
      contadores = [Conversations::UnreadCounts::Builder.new(account),
                    Conversations::UnreadCounts::FilteredCounter.new(account: account, user: admin),
                    Conversations::UnreadCounts::FilterQueryCounter.new(account: account, user: admin, query: query)]

      contadores.each { |contador| expect(contador.send(:unread_conversations)).to contain_exactly(cliente) }
    end

    it 'a atualização em tempo real não conta a conversa do conector' do
      expect(Conversations::UnreadCounts::Refresher.new(interna).send(:unread?)).to be(false)
      expect(Conversations::UnreadCounts::Refresher.new(cliente).send(:unread?)).to be(true)
    end
  end
end
