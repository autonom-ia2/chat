require 'rails_helper'

# #2543: o texto do privado é medido em bytes UTF-8, como a Meta mede. A régua é uma só, a do cuidado dos comentários.
RSpec.describe Crm::MetaAds::InstagramPrivateReply do
  describe '.valid_text!' do
    def code_for(text)
      described_class.valid_text!(text)
      nil
    rescue described_class::Error => e
      e.code
    end

    it 'usa a régua de Crm::MetaAdsCommentCare::MESSAGE_LIMIT, que é de 1000 bytes' do
      expect(Crm::MetaAdsCommentCare::MESSAGE_LIMIT).to eq(1000)
    end

    it 'devolve o texto sem os espaços das pontas' do
      expect(described_class.valid_text!("  Oi, Carla!\n")).to eq('Oi, Carla!')
    end

    it 'texto vazio ou só espaço: invalid_text' do
      expect(code_for(nil)).to eq('invalid_text')
      expect(code_for("  \n")).to eq('invalid_text')
    end

    it 'aceita até 1000 bytes, contando acento como 2 bytes' do
      expect(code_for('a' * 1000)).to be_nil
      expect(code_for('ã' * 500)).to be_nil
    end

    it 'texto com acento abaixo de 1000 letras e acima de 1000 bytes: text_too_long' do
      texto = 'ã' * 501

      expect(texto.length).to be < 1000
      expect(texto.bytesize).to be > 1000
      expect(code_for(texto)).to eq('text_too_long')
    end

    it 'emoji conta 4 bytes' do
      expect(code_for('🙂' * 250)).to be_nil
      expect(code_for('🙂' * 251)).to eq('text_too_long')
    end

    it 'os espaços das pontas não contam' do
      expect(code_for("  #{'a' * 1000}  ")).to be_nil
    end
  end

  # #2212 (revisão da Funções): o privado que a IA manda é envio automático e leva a marca de
  # PessoaDaEquipe::MARCAS_DE_ENVIO_AUTOMATICO; o da tela é a pessoa que clicou, sem marca.
  describe '#perform!' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_instagram, account: account) }
    let(:client) { instance_double(Instagram::CommentsClient) }
    let(:user) { create(:user, account: account) }
    let(:comment) do
      { 'id' => 'c-1', 'timestamp' => 1.minute.ago.iso8601, 'from' => { 'id' => 'ig-carla', 'username' => 'carla' },
        'media' => { 'id' => '1790' } }
    end
    let(:marca) { Crm::MetaAds::ComentariosIa::Registro::MARCA }

    before do
      allow(Instagram::CommentsClient).to receive(:new).and_return(client)
      allow(client).to receive(:private_reply)
        .and_return(Instagram::CommentsClient::Result.new(ok: true, http_code: 200, data: { 'message_id' => 'mid-1', 'recipient_id' => 'ig-carla' }))
    end

    def enviar(actor:, user: nil)
      described_class.new(channel).perform!(comment: comment, text: 'Te mandei os valores', actor: actor, user: user)
    end

    it 'o da IA leva a marca com o id da linha private_reply e conta como envio automático' do
      message = enviar(actor: 'ai')[:message]
      action = Crm::MetaAdsCommentAction.find_by!(comment_id: 'c-1', action: 'private_reply')

      expect(message.content_attributes.to_h[marca]).to eq(action.id)
      expect(message.sender).to be_nil
      expect(Messages::EnvioAutomatico.automatico?(message)).to be(true)
    end

    it 'o da tela fica com a pessoa que clicou, sem marca' do
      message = enviar(actor: 'user', user: user)[:message]

      expect(message.content_attributes.to_h).not_to have_key(marca)
      expect(message.sender).to eq(user)
      expect(Messages::EnvioAutomatico.automatico?(message)).to be(false)
    end

    it 'a marca está na lista única de PessoaDaEquipe' do
      expect(Autonomia::Agents::Operate::PessoaDaEquipe::MARCAS_DE_ENVIO_AUTOMATICO).to include(marca)
    end

    it 'a reserva vencida de outra conta com o mesmo comment_id não é apagada' do
      outra = create(:account)
      vencida = Crm::MetaAdsCommentAction.create!(account: outra, network: 'instagram', comment_id: 'c-1', action: 'private_reply',
                                                  actor: 'ai', at: 1.day.ago)

      expect { enviar(actor: 'ai') }.to raise_error(described_class::Error, 'private_reply_done')
      expect(Crm::MetaAdsCommentAction.exists?(vencida.id)).to be(true)
    end
  end
end
