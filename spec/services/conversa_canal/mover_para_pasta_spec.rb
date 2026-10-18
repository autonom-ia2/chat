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

  it 'o cliente respondeu na conversa da Lixeira: ela volta para a Entrada' do
    mover('lixeira')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'Ainda quero')

    expect(lista[:conversations]).to contain_exactly(conversa, outra)
    expect(ConversaCanal::PastaDoEmail.exists?(conversation_id: conversa.id)).to be(false)
  end

  it 'resposta do atendente não tira da Lixeira, e o Spam fica no Spam' do
    mover('lixeira')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, content: 'Oi')
    expect(lista(pasta: 'lixeira')[:conversations]).to eq([conversa])

    mover('spam')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'compre já')
    expect(lista(pasta: 'spam')[:conversations]).to eq([conversa])
  end

  it 'mover de novo para a mesma pasta, ou trocar de pasta, grava uma linha só' do
    mover('lixeira')
    mover('lixeira')
    mover('spam')

    expect(ConversaCanal::PastaDoEmail.where(conversation_id: conversa.id).pluck(:pasta)).to eq(['spam'])
  end

  it 'contato antigo com dado fora do formato de hoje também vai para o Spam' do
    contato.update_column(:email, 'sem-arroba') # rubocop:disable Rails/SkipsModelValidations

    expect { mover('spam') }.not_to raise_error
    expect(contato.reload).to be_blocked
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
