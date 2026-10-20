require 'rails_helper'

# #1938: Enviados da caixa de e-mail é uma vista (pasta=enviados): as conversas em que nós mandamos mensagem ao cliente.
RSpec.describe ConversationFinder do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:respondida) { create(:conversation, account: account, inbox: inbox) }
  let!(:so_recebida) { create(:conversation, account: account, inbox: inbox) }
  let!(:so_nota) { create(:conversation, account: account, inbox: inbox) }
  let!(:respondida_na_lixeira) { create(:conversation, account: account, inbox: inbox) }
  let!(:envio_falhou) { create(:conversation, account: account, inbox: inbox) }

  before do
    Current.account = account
    account.enable_features!('conversa_email_nova')
    [respondida, so_recebida, so_nota, respondida_na_lixeira, envio_falhou].each do |conversa|
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming)
    end
    create(:message, conversation: respondida, account: account, inbox: inbox, message_type: :outgoing)
    create(:message, conversation: respondida_na_lixeira, account: account, inbox: inbox, message_type: :outgoing)
    create(:message, conversation: so_nota, account: account, inbox: inbox, message_type: :outgoing, private: true)
    create(:message, conversation: envio_falhou, account: account, inbox: inbox, message_type: :outgoing, status: :failed)
    ConversaCanal::PastaDoEmail.create!(account: account, conversation: respondida_na_lixeira, pasta: 'lixeira')
    # Resolvida depois das mensagens (a recebida reabre a conversa).
    respondida.resolved!
  end

  after { Current.reset }

  def ids(params)
    parametros = ActionController::Parameters.new({ inbox_id: inbox.id, assignee_type: 'all' }.merge(params))
    described_class.new(admin, parametros).perform[:conversations].map(&:id)
  end

  it 'com a chave email_enviados: só as conversas com mensagem nossa entregue, em qualquer situação, sem Spam e Lixeira' do
    account.enable_features!('email_enviados')

    expect(ids(pasta: 'enviados')).to contain_exactly(respondida.id)
  end

  it 'a conversa enviada continua na Entrada' do
    account.enable_features!('email_enviados')

    expect(ids(status: 'all')).to include(respondida.id, so_recebida.id)
  end

  it 'sem a chave email_enviados, pasta=enviados é ignorada (lista de sempre)' do
    expect(ids(pasta: 'enviados')).to contain_exactly(so_recebida.id, so_nota.id, envio_falhou.id)
  end
end
