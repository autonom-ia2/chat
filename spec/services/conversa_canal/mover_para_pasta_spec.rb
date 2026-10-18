require 'rails_helper'

# #1809, fase 1: Spam e Lixeira da caixa de e-mail no painel, sem apagar nada e sem mexer na conta do cliente.
RSpec.describe ConversaCanal::MoverParaPasta do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, email: 'spam@exemplo.com') }
  let!(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato) }
  let!(:outra) { create(:conversation, account: account, inbox: inbox) }

  before do
    account.enable_features!('conversa_email_nova')
    Current.account = account
  end

  after { Current.reset }

  def mover(pasta, alvo = conversa)
    described_class.new(conversation: alvo, pasta: pasta, user: user).perform
  end

  def lista(params = {})
    ConversationFinder.new(user, { inbox_id: inbox.id, assignee_type: 'all' }.merge(params)).perform
  end

  it 'spam: sai da Entrada, aparece no Spam e bloqueia o contato' do
    mover('spam')

    expect(lista[:conversations]).to eq([outra])
    expect(lista(pasta: 'spam')[:conversations]).to eq([conversa])
    expect(contato.reload).to be_blocked
  end

  it '"não é spam": volta para a Entrada e desbloqueia' do
    mover('spam')
    mover('')

    expect(lista[:conversations]).to contain_exactly(conversa, outra)
    expect(contato.reload).not_to be_blocked
  end

  it 'lixeira: sai da Entrada sem apagar e sem bloquear; restaurar devolve' do
    mover('lixeira')

    expect(lista[:conversations]).to eq([outra])
    expect(lista(pasta: 'lixeira')[:conversations]).to eq([conversa])
    expect(contato.reload).not_to be_blocked
    expect(Conversation.exists?(conversa.id)).to be(true)

    mover(nil)
    expect(lista[:conversations]).to contain_exactly(conversa, outra)
  end

  it 'a pasta mostra também as resolvidas (contato bloqueado nasce resolvido)' do
    mover('spam')
    conversa.update!(status: :resolved)

    expect(lista(pasta: 'spam')[:conversations]).to eq([conversa])
  end

  it 'contadores da Entrada não contam o que está nas pastas' do
    mover('lixeira')

    expect(lista[:count][:all_count]).to eq(1)
  end

  it 'conversa nova de quem foi marcado como spam vai direto para o Spam' do
    mover('spam')
    nova = create(:conversation, account: account, inbox: inbox, contact: contato)

    expect(ConversaCanal::PastaDoEmail.find_by(conversation_id: nova.id)&.pasta).to eq('spam')
    expect(nova.reload).to be_resolved
  end

  it 'sem a chave conversa_email_nova as listas não mudam' do
    mover('lixeira')
    account.disable_features!('conversa_email_nova')

    expect(lista[:conversations]).to contain_exactly(conversa, outra)
  end

  it 'recusa caixa que não é de e-mail e pasta que não existe' do
    api = create(:conversation, account: account, inbox: create(:inbox, account: account))

    expect { mover('spam', api) }.to raise_error(described_class::Recusa)
    expect { mover('arquivo') }.to raise_error(described_class::Recusa)
  end
end
