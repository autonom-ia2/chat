require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Conversa do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:entrega) { instance_double(Crm::Entrega, call: nil) }

  def comentario(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', from_name: 'carla.mendes', text: 'Quanto custa?',
      created_time: 1.minute.ago, **mudancas
    )
  end

  # A conversa como o InstagramPrivateReply do #2196 a deixa: o privado gravado com o id da Meta.
  def conversa_do_privado(conversation = create(:conversation, account: account, inbox: inbox, status: :open))
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: care.message, source_id: 'mid-1')
    conversation
  end

  before { allow(Crm::Entrega).to receive(:new).and_return(entrega) }

  describe '.anotar!' do
    it 'põe o comentário no topo, marca a origem e resolve a conversa nova' do
      conversation = described_class.anotar!(conversa_do_privado, comentario, care, nova: true)

      expect(conversation.reload).to be_resolved
      expect(conversation.additional_attributes['meta_ads_comment'])
        .to include('network' => 'instagram', 'comment_id' => 'c-1', 'post_id' => '1790', 'care_id' => care.id,
                    'from_id' => 'igsid-1', 'private_reply' => true)
      expect(conversation.messages.reorder(:created_at, :id).map { |message| [message.message_type, message.content] })
        .to eq([['activity', 'Comentou no post: “Quanto custa?”'], ['outgoing', care.message]])
    end

    it 'não resolve a conversa que a pessoa já tinha aberta na caixa' do
      aberta = create(:conversation, account: account, inbox: inbox, status: :open)
      create(:message, account: account, inbox: inbox, conversation: aberta, message_type: :incoming, content: 'Oi')

      expect(described_class.anotar!(conversa_do_privado(aberta), comentario, care, nova: false).reload).to be_open
    end

    it 'no anúncio, diz que o comentário veio do anúncio' do
      conversation = described_class.anotar!(conversa_do_privado, comentario(ad_id: '120'), care, nova: true)

      expect(conversation.messages.activity.first.content).to eq('Comentou no anúncio: “Quanto custa?”')
    end
  end

  it 'para_voce!: a Atribuição falhou, a conversa continua aberta na caixa e o erro vai ao rastreador' do
    entrega = instance_double(Crm::Entrega)
    allow(Crm::Entrega).to receive(:new).and_return(entrega)
    allow(entrega).to receive(:call).and_raise(ActiveRecord::StatementInvalid)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

    conversation = described_class.para_voce!(comentario, care, 'to_you')

    expect(conversation).to be_persisted.and(have_attributes(status: 'open'))
    expect(rastreador).to have_received(:capture_exception)
  end

  describe '.no_messenger!' do
    let(:pagina) do
      stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps})
      create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
    end
    let(:envio) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-9') }

    it 'abre a conversa no contato da resposta da Meta, com o privado que já saiu' do
      conversation = perform_enqueued_jobs do
        described_class.no_messenger!(comentario(network: 'facebook', inbox_id: pagina.id), envio, care.message)
      end

      expect(conversation.inbox).to eq(pagina)
      expect(conversation.contact_inbox.source_id).to eq('psid-1')
      expect(conversation.contact.name).to eq('carla.mendes')
      expect(conversation.messages.outgoing.sole).to have_attributes(content: care.message, source_id: 'mid-9')
      expect(a_request(:post, %r{graph\.facebook\.com/.*/messages})).not_to have_been_made
    end

    it 'reaproveita o contato de quem já escreveu na caixa' do
      contato = create(:contact, account: account)
      create(:contact_inbox, contact: contato, inbox: pagina, source_id: 'psid-1')

      conversation = described_class.no_messenger!(comentario(network: 'facebook', inbox_id: pagina.id), envio, care.message)

      expect(conversation.contact).to eq(contato)
    end

    it 'usa a conversa que a pessoa já tem aberta na caixa do Messenger' do
      contato = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contato, inbox: pagina, source_id: 'psid-1')
      aberta = create(:conversation, account: account, inbox: pagina, contact: contato, contact_inbox: contact_inbox, status: :open)

      conversation = described_class.no_messenger!(comentario(network: 'facebook', inbox_id: pagina.id), envio, care.message)

      expect(conversation).to eq(aberta)
      expect(aberta.messages.outgoing.sole.source_id).to eq('mid-9')
    end
  end

  describe '.para_voce!' do
    it 'reclamação: abre urgente, diz por que e entrega pela Atribuição' do
      conversation = described_class.para_voce!(comentario(text: 'Ninguém me responde'), care, 'to_you')

      expect(conversation).to be_open
      expect(conversation).to be_urgent
      expect(conversation.contact_inbox.source_id).to eq('igsid-1')
      expect(conversation.additional_attributes['meta_ads_comment']).to include('comment_id' => 'c-1')
      expect(conversation.messages.order(:id).pluck(:content))
        .to eq(['Comentou no post: “Ninguém me responde”', 'Reclamação: não respondi e passei para você.'])
      expect(Crm::Entrega).to have_received(:new).with(conversation: conversation, motivo: 'comentario', origem: 'comentarios_ia')
    end

    it 'privado recusado: abre sem urgência e avisa que não saiu' do
      conversation = described_class.para_voce!(comentario, care, 'private_reply_failed')

      expect(conversation).not_to be_urgent
      expect(conversation.messages.order(:id).last.content).to eq('Não consegui mandar a mensagem. Responda você, se quiser.')
    end
  end

  describe '.passar_se_preciso!' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox,
                            additional_attributes: { 'meta_ads_comment' => { 'care_id' => care.id, 'private_reply' => true } })
    end

    it 'a pessoa respondeu: com o cuidado em "você ou sua equipe", vai à Atribuição' do
      described_class.passar_se_preciso!(conversation)

      expect(Crm::Entrega).to have_received(:new).with(conversation: conversation, motivo: 'comentario', origem: 'comentarios_ia')
    end

    it 'segurada pela Atribuição (ninguém online) ou com convite: não roda de novo a cada mensagem' do
      allow(Crm::Entrega::Marca).to receive(:presente?).with(conversation).and_return(true)

      described_class.passar_se_preciso!(conversation)

      expect(Crm::Entrega).not_to have_received(:new)
    end

    it 'já tem alguém no nome, ou o cuidado é do agente: não passa' do
      care.update!(handoff: 'agent')
      described_class.passar_se_preciso!(conversation)

      expect(Crm::Entrega).not_to have_received(:new)
    end
  end
end
