require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Conversa do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:envio) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: 'igsid-1', message_id: 'mid-1') }
  let(:entrega) { instance_double(Crm::Entrega, call: nil) }

  def comentario(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', from_name: 'carla.mendes', text: 'Quanto custa?',
      created_time: 1.minute.ago, **mudancas
    )
  end

  before { allow(Crm::Entrega).to receive(:new).and_return(entrega) }

  describe '.do_privado!' do
    it 'abre a conversa resolvida com o comentário no topo e o privado que já saiu' do
      conversation = described_class.do_privado!(comentario, care, envio)

      expect(conversation).to be_resolved
      expect(conversation.inbox).to eq(inbox)
      expect(conversation.contact.name).to eq('carla.mendes')
      expect(conversation.contact_inbox.source_id).to eq('igsid-1')
      expect(conversation.additional_attributes['meta_ads_comment'])
        .to include('network' => 'instagram', 'comment_id' => 'c-1', 'post_id' => '1790', 'care_id' => care.id)
      expect(conversation.messages.order(:id).map { |message| [message.message_type, message.content] }).to eq(
        [['activity', 'Comentou no post: “Quanto custa?”'], ['outgoing', care.message]]
      )
      expect(Crm::Entrega).not_to have_received(:new)
    end

    it 'não manda de novo o privado que já saiu' do
      conversation = perform_enqueued_jobs { described_class.do_privado!(comentario, care, envio) }

      expect(conversation.messages.outgoing.first.source_id).to eq('mid-1')
      expect(a_request(:post, %r{graph\.instagram\.com/.*/messages})).not_to have_been_made
    end

    it 'reaproveita o contato de quem já escreveu na caixa' do
      contato = create(:contact, account: account, name: 'Carla')
      create(:contact_inbox, contact: contato, inbox: inbox, source_id: 'igsid-1')

      expect(described_class.do_privado!(comentario, care, envio).contact).to eq(contato)
    end

    it 'no anúncio, diz que o comentário veio do anúncio' do
      conversation = described_class.do_privado!(comentario(ad_id: '120'), care, envio)

      expect(conversation.messages.activity.first.content).to eq('Comentou no anúncio: “Quanto custa?”')
    end
  end

  describe '.para_voce!' do
    it 'reclamação: abre urgente, diz por que e entrega pela Atribuição' do
      conversation = described_class.para_voce!(comentario(text: 'Ninguém me responde'), care, 'to_you')

      expect(conversation).to be_open
      expect(conversation).to be_urgent
      expect(conversation.contact_inbox.source_id).to eq('igsid-1')
      expect(conversation.messages.order(:id).pluck(:content))
        .to eq(['Comentou no post: “Ninguém me responde”', 'Reclamação: não respondi e passei para você.'])
      expect(Crm::Entrega).to have_received(:new).with(conversation: conversation, motivo: 'comentario', origem: 'comentarios_ia')
      expect(entrega).to have_received(:call)
    end

    it 'privado recusado: abre sem urgência e avisa que não saiu' do
      conversation = described_class.para_voce!(comentario, care, 'failed')

      expect(conversation).not_to be_urgent
      expect(conversation.messages.order(:id).last.content).to eq('Não consegui mandar a mensagem. Responda você, se quiser.')
    end

    it 'no Facebook, diz que foi no post da Página' do
      stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps})
      pagina = create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
      conversation = described_class.para_voce!(comentario(network: 'facebook', inbox_id: pagina.id, from_id: 'psid-1'), care,
                                                'to_you')

      expect(conversation.inbox).to eq(pagina)
      expect(conversation.messages.activity.first.content).to eq('Comentou no post da Página: “Quanto custa?”')
    end
  end
end
