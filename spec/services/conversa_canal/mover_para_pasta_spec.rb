require 'rails_helper'

# #1809, fase 1: Spam e Lixeira da caixa de e-mail no painel, sem apagar nada e sem mexer na conta do cliente.
# Decisões do Rodrigo (18/10): o Spam vale só para o remetente naquela caixa (o contato e os outros canais seguem
# normais); Spam e Lixeira resolvem a conversa, Restaurar e "Não é spam" a reabrem.
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

  def no_spam?(caixa = inbox)
    ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: caixa.id, email: contato.email)
  end

  it 'spam: sai da Entrada, aparece no Spam, resolve e põe o remetente no Spam desta caixa, sem bloquear o contato' do
    mover('spam')

    expect(lista[:conversations]).to eq([outra])
    expect(lista(pasta: 'spam')[:conversations]).to eq([conversa])
    expect(conversa.reload).to be_resolved
    expect(no_spam?).to be(true)
    expect(contato.reload).not_to be_blocked
  end

  it '"não é spam": volta para a Entrada, reabre e o remetente volta a chegar' do
    mover('spam')
    mover('')

    expect(lista[:conversations]).to contain_exactly(conversa, outra)
    expect(conversa.reload).to be_open
    expect(no_spam?).to be(false)
  end

  it 'lixeira: sai da Entrada resolvida, sem apagar e sem mexer no remetente; restaurar devolve aberta' do
    mover('lixeira')

    expect(lista(pasta: 'lixeira')[:conversations]).to eq([conversa])
    expect(conversa.reload).to be_resolved
    expect(no_spam?).to be(false)
    expect(Conversation.exists?(conversa.id)).to be(true)

    mover(nil)
    expect(lista[:conversations]).to contain_exactly(conversa, outra)
    expect(conversa.reload).to be_open
  end

  it 'resolver e reabrir passam pelo status da conversa (eventos e atividade de sempre)' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    mover('lixeira')
    mover(nil)

    despachante = Rails.configuration.dispatcher
    expect(despachante).to have_received(:dispatch).with(Events::Types::CONVERSATION_RESOLVED, anything, anything)
    expect(despachante).to have_received(:dispatch).with(Events::Types::CONVERSATION_STATUS_CHANGED, anything, anything).at_least(:twice)
  end

  it 'contadores da Entrada não contam o que está nas pastas' do
    mover('lixeira')

    expect(lista[:count][:all_count]).to eq(1)
  end

  it 'conversa nova do remetente nesta caixa vai direto para o Spam, resolvida' do
    mover('spam')
    nova = create(:conversation, account: account, inbox: inbox, contact: contato)

    expect(ConversaCanal::PastaDoEmail.find_by(conversation_id: nova.id)&.pasta).to eq('spam')
    expect(nova.reload).to be_resolved
  end

  it 'outra caixa de e-mail não é afetada pelo Spam desta' do
    mover('spam')
    outra_caixa = create(:channel_email, account: account).inbox
    nova = create(:conversation, account: account, inbox: outra_caixa, contact: contato)

    expect(no_spam?(outra_caixa)).to be(false)
    expect(ConversaCanal::PastaDoEmail.exists?(conversation_id: nova.id)).to be(false)
    expect(nova.reload).to be_open
  end

  it 'o WhatsApp do mesmo contato segue normal' do
    mover('spam')
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    whatsapp = create(:conversation, account: account, inbox: canal.inbox, contact: contato)
    create(:message, account: account, inbox: canal.inbox, conversation: whatsapp, message_type: :incoming, content: 'Oi')

    expect(ConversaCanal::PastaDoEmail.exists?(conversation_id: whatsapp.id)).to be(false)
    expect(whatsapp.reload).to be_open
    expect(contato.reload).not_to be_blocked
  end

  it 'o cliente respondeu na conversa da Lixeira: ela volta para a Entrada' do
    mover('lixeira')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'Ainda quero')

    expect(lista[:conversations]).to contain_exactly(conversa, outra)
    expect(ConversaCanal::PastaDoEmail.exists?(conversation_id: conversa.id)).to be(false)
  end

  it 'resposta do atendente não tira da Lixeira; e-mail novo do remetente no Spam fica no Spam, sem reabrir' do
    mover('lixeira')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, content: 'Oi')
    expect(lista(pasta: 'lixeira')[:conversations]).to eq([conversa])

    mover('spam')
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'compre já')
    expect(lista(pasta: 'spam')[:conversations]).to eq([conversa])
    expect(conversa.reload).to be_resolved
  end

  it 'mover de novo para a mesma pasta, ou trocar de pasta, grava uma linha só' do
    mover('lixeira')
    mover('lixeira')
    mover('spam')
    mover('spam')

    expect(ConversaCanal::PastaDoEmail.where(conversation_id: conversa.id).pluck(:pasta)).to eq(['spam'])
    expect(ConversaCanal::RemetenteNoSpam.where(inbox_id: inbox.id).count).to eq(1)
  end

  it 'o endereço vale sem diferença de maiúsculas' do
    contato.update!(email: 'Spam@Exemplo.com')
    mover('spam')

    expect(ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox.id, email: 'spam@exemplo.COM')).to be(true)
  end

  it 'sem a chave conversa_email_nova as listas não mudam' do
    mover('lixeira')
    account.disable_features!('conversa_email_nova')

    expect(lista(status: 'all')[:conversations]).to contain_exactly(conversa, outra)
  end

  describe 'reabrir pelas pastas é o "Reabrir" do painel' do
    let(:robo) { create(:agent_bot, account: account) }
    let(:agente) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, user: agente, inbox: inbox)
      conversa.update!(ai_assignee: robo)
    end

    it 'conversa com robô vai ao Spam e volta pelo "Não é spam": o robô não fica atribuído' do
      mover('spam')
      mover('')

      expect(conversa.reload).to be_open
      expect(conversa.ai_assignee).to be_nil
    end

    it 'o agente que restaura da Lixeira fica com a conversa' do
      described_class.new(conversation: conversa, pasta: 'lixeira', user: agente).perform
      described_class.new(conversation: conversa, pasta: nil, user: agente).perform

      expect(conversa.reload).to be_open
      expect(conversa.assignee).to eq(agente)
      expect(conversa.ai_assignee).to be_nil
    end
  end

  it 'voltar para a Entrada sem estar numa pasta não reabre a conversa resolvida' do
    conversa.update!(status: :resolved)

    mover('')

    expect(conversa.reload).to be_resolved
  end

  describe 'remetente no Spam escreve numa conversa que já existia' do
    let!(:antiga) { create(:conversation, account: account, inbox: inbox, contact: contato) }

    def escrever(alvo)
      create(:message, account: account, inbox: inbox, conversation: alvo, message_type: :incoming, content: 'Re: oferta')
    end

    it 'aberta na Entrada (resposta com In-Reply-To): vai para o Spam, resolvida' do
      mover('spam')
      escrever(antiga)

      expect(ConversaCanal::PastaDoEmail.find_by(conversation_id: antiga.id)&.pasta).to eq('spam')
      expect(antiga.reload).to be_resolved
      expect(lista[:conversations]).to eq([outra])
    end

    it 'resolvida na Entrada: não reabre e vai para o Spam' do
      antiga.update!(status: :resolved)
      mover('spam')
      escrever(antiga)

      expect(antiga.reload).to be_resolved
      expect(lista(pasta: 'spam')[:conversations]).to contain_exactly(conversa, antiga)
    end

    it 'na Lixeira: vai para o Spam, não para a Entrada' do
      described_class.new(conversation: antiga, pasta: 'lixeira', user: user).perform
      mover('spam')
      escrever(antiga)

      expect(ConversaCanal::PastaDoEmail.where(conversation_id: antiga.id).pluck(:pasta)).to eq(['spam'])
      expect(antiga.reload).to be_resolved
    end

    it 'depois do "Não é spam", a resposta dele fica na Entrada' do
      mover('spam')
      mover('')
      escrever(antiga)

      expect(ConversaCanal::PastaDoEmail.exists?(conversation_id: antiga.id)).to be(false)
      expect(antiga.reload).to be_open
    end
  end

  it 'recusa caixa que não é de e-mail e pasta que não existe' do
    api = create(:conversation, account: account, inbox: create(:inbox, account: account))

    expect { mover('spam', api) }.to raise_error(described_class::Recusa)
    expect { mover('arquivo') }.to raise_error(described_class::Recusa)
  end

  # #2616: quem resolve é a pessoa que moveu, ou o Spam da caixa, e não o auto-resolve da conta. Com auto-resolve ligado,
  # a resolução saía como "resolvida pelo sistema por N dias de inatividade" (o auto-resolve nunca rodou) e, no toque da
  # pessoa, sem dizer para onde a conversa foi. A atividade sai no idioma da conta.
  describe 'atividade de quem resolveu' do
    let(:account) { create(:account, locale: 'pt_BR', auto_resolve_after: 40 * 24 * 60) }
    let(:user) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }

    def atividades(alvo = conversa)
      alvo.messages.activity.reorder(:created_at, :id).pluck(:content)
    end

    it 'spam e lixeira pelo toque da pessoa: diz quem moveu e para onde, uma vez por pasta; a volta é a de sempre' do
      Current.user = user
      I18n.with_locale(:en) do
        perform_enqueued_jobs do
          mover('spam')
          mover('spam')
          mover('lixeira')
          mover('')
        end
      end

      # A lista inteira: a linha nova substitui o "Conversation was marked resolved by Ana Souza", que não sai junto.
      expect(atividades).to eq(['Ana Souza moveu a conversa para o Spam.', 'Ana Souza moveu a conversa para a Lixeira.',
                                'Conversation was reopened by Ana Souza'])
      expect(Current.executed_by).to be_nil
    end

    it 'spam automático, em conversa nova e na resposta numa conversa da Entrada: diz por que foi para o Spam' do
      ConversaCanal::RemetenteNoSpam.create!(account: account, inbox: inbox, email: contato.email)
      Current.reset

      # Sem o ActionCableBroadcastJob, que já falhava antes do #2616 com a conversa nova criada no teste (sem display_id).
      nova = I18n.with_locale(:en) do
        perform_enqueued_jobs(only: [Conversations::ActivityMessageJob, EventDispatcherJob]) do
          create(:message, account: account, inbox: inbox, conversation: conversa, sender: contato, message_type: :incoming,
                           content: 'compre já')
          create(:conversation, account: account, inbox: inbox, contact: contato)
        end
      end

      motivo = 'Foi para o Spam: este remetente está no Spam desta caixa.'
      expect(atividades).to eq([motivo])
      expect(atividades(nova)).to eq([motivo])
      expect(Current.executed_by).to be_nil
    end

    it 'spam automático em conversa já resolvida na Entrada: vai para o Spam com o motivo, sem reabrir' do
      conversa.update!(status: :resolved)
      ConversaCanal::RemetenteNoSpam.create!(account: account, inbox: inbox, email: contato.email)
      Current.reset

      perform_enqueued_jobs do
        create(:message, account: account, inbox: inbox, conversation: conversa, sender: contato, message_type: :incoming,
                         content: 'de novo')
      end

      expect(conversa.reload).to be_resolved
      expect(atividades.last).to eq('Foi para o Spam: este remetente está no Spam desta caixa.')
      expect(atividades.grep_v('Foi para o Spam: este remetente está no Spam desta caixa.')).not_to include(a_string_including('40'))
    end
  end
end
