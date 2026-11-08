require 'rails_helper'

RSpec.describe Crm::MetaAdsComentariosIaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, handoff: 'assignment') }
  let(:entrega) { instance_double(Crm::Entrega, call: nil) }

  before do
    account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)
    allow(Crm::Entrega).to receive(:new).and_return(entrega)
  end

  describe '#meta_ads_comment_received' do
    let(:dados) do
      { network: 'instagram', account_id: account.id, inbox_id: inbox.id, instagram_id: 'ig-1', media_id: '1790', ad_id: nil,
        comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', created_time: Time.zone.parse('2026-10-27 10:00') }
    end

    def evento(dados)
      Events::Base.new('meta_ads.comment_received', Time.zone.now, dados)
    end

    it 'enfileira o cuidado do comentário com valores simples' do
      expect { listener.meta_ads_comment_received(evento(dados)) }
        .to have_enqueued_job(Crm::MetaAds::ComentariosIa::CuidarJob)
        .with(hash_including('comment_id' => 'c-1', 'owner_id' => 'ig-1', 'post_id' => '1790', 'created_time' => '2026-10-27T10:00:00Z'))
    end

    # #2327: o job guarda os argumentos em claro no Redis. Texto e nome, se viessem, não vão para lá.
    it 'enfileira só ids, mesmo se o evento trouxer texto e nome' do
      expect { listener.meta_ads_comment_received(evento(dados.merge(text: 'Quanto custa?', from_name: 'carla'))) }
        .to have_enqueued_job(Crm::MetaAds::ComentariosIa::CuidarJob).with(hash_excluding('text', 'from_name'))
    end

    it 'aceita a hora como texto' do
      expect { listener.meta_ads_comment_received(evento(dados.merge(created_time: '2026-10-27T10:00:00+00:00'))) }
        .to have_enqueued_job(Crm::MetaAds::ComentariosIa::CuidarJob).with(hash_including('created_time' => '2026-10-27T10:00:00Z'))
    end

    it 'com a flag desligada, nem enfileira' do
      account.disable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

      expect { listener.meta_ads_comment_received(evento(dados)) }.not_to have_enqueued_job(Crm::MetaAds::ComentariosIa::CuidarJob)
    end
  end

  describe '#message_created' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox,
                            additional_attributes: { 'meta_ads_comment' => { 'comment_id' => 'c-1', 'care_id' => care.id } })
    end

    def responde(conversa = conversation, tipo: :incoming)
      message = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: tipo, content: 'Quero sim!')
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    end

    it 'sem agente: quando a pessoa responde, a conversa vai à Atribuição' do
      responde

      expect(Crm::Entrega).to have_received(:new).with(conversation: conversation, motivo: 'comentario', origem: 'comentarios_ia')
      expect(entrega).to have_received(:call)
    end

    it 'com agente: o agente da caixa continua, sem passar' do
      care.update!(handoff: 'agent')

      responde

      expect(Crm::Entrega).not_to have_received(:new)
    end

    it 'conversa que já tem pessoa no nome, mensagem enviada ou conversa que não veio de comentário: nada' do
      conversation.update!(assignee: create(:user, account: account))
      responde
      responde(create(:conversation, account: account, inbox: inbox))
      responde(create(:conversation, account: account, inbox: inbox), tipo: :outgoing)

      expect(Crm::Entrega).not_to have_received(:new)
    end

    it 'com a flag desligada, nada' do
      account.disable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

      responde

      expect(Crm::Entrega).not_to have_received(:new)
    end
  end
end
