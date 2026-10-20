require 'rails_helper'

# #1934: foto de perfil do contato pela sessão WAHA da própria caixa híbrida.
describe WhatsappHybrid::FotoDoContato do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:numero_da_caixa) { channel.phone_number.delete('^0-9') }
  let(:contact) { create(:contact, account: account, phone_number: '+5511988887777') }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-foto-do-contato', status: 'connected',
                                       connected_phone: numero_da_caixa, risk_accepted_at: Time.current)
  end
  let(:client) { instance_double(Waha::Client) }
  let(:foto) { described_class.new(contact: contact, connection: connection, client: client) }

  before do
    Redis::Alfred.delete(described_class.chave_do_contato(contact.id))
    Redis::Alfred.delete(described_class.chave_da_sessao(connection.session_name))
    Redis::Alfred.scan_each(match: 'whatsapp_hybrid:foto_do_contato:*') { |key| Redis::Alfred.delete(key) }
  end

  describe '#perform' do
    it 'busca a foto pela sessão da caixa e manda baixar' do
      allow(client).to receive(:profile_picture).and_return({ 'profilePictureURL' => 'https://pps.whatsapp.net/v/foto.jpg' })

      expect { foto.perform }.to have_enqueued_job(Avatar::AvatarFromUrlJob).with(contact, 'https://pps.whatsapp.net/v/foto.jpg')
      expect(client).to have_received(:profile_picture)
        .with(session: connection.session_name, contact_id: '5511988887777@c.us', timeout: described_class::TIMEOUT)
      expect(Redis::Alfred.ttl(described_class.chave_do_contato(contact.id))).to be_within(60).of(described_class::INTERVALO.to_i)
    end

    it 'foto escondida ou ausente: sem baixar, e só tenta de novo em 30 dias' do
      allow(client).to receive(:profile_picture).and_return({ 'profilePictureURL' => nil })

      expect { foto.perform }.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
      expect(Redis::Alfred.ttl(described_class.chave_do_contato(contact.id))).to be_within(60).of(described_class::SEM_FOTO.to_i)
    end

    it 'não consulta de novo dentro do intervalo' do
      allow(client).to receive(:profile_picture).and_return({ 'profilePictureURL' => nil })

      2.times { described_class.new(contact: contact, connection: connection, client: client).perform }

      expect(client).to have_received(:profile_picture).once
    end

    it 'erro do motor pausa as buscas daquela sessão e devolve o contato' do
      allow(client).to receive(:profile_picture).and_raise(Waha::Client::Error.new('rate-overlimit', status: 500))

      foto.perform
      Redis::Alfred.scan_each(match: 'whatsapp_hybrid:foto_do_contato:ritmo:*') { |key| Redis::Alfred.delete(key) }
      outro = create(:contact, account: account, phone_number: '+5511977776666')
      described_class.new(contact: outro, connection: connection, client: client).perform

      expect(client).to have_received(:profile_picture).once
      expect(Redis::Alfred.exists?(described_class.chave_da_sessao(connection.session_name))).to be(true)
      expect(Redis::Alfred.exists?(described_class.chave_do_contato(contact.id))).to be(false)
    end

    [Waha::Client::NotFound.new('session not found', status: 404), Errno::ECONNRESET.new, 'texto em vez de objeto'].each do |falha|
      it "#{falha.class} também pausa a sessão (não vira \"sem foto\")" do
        if falha.is_a?(String)
          allow(client).to receive(:profile_picture).and_return(falha)
        else
          allow(client).to receive(:profile_picture).and_raise(falha)
        end

        foto.perform

        expect(Redis::Alfred.exists?(described_class.chave_da_sessao(connection.session_name))).to be(true)
        expect(Redis::Alfred.exists?(described_class.chave_do_contato(contact.id))).to be(false)
      end
    end

    it 'uma consulta por sessão a cada 15 s: sem vaga, desiste sem marcar o contato' do
      allow(client).to receive(:profile_picture).and_return({ 'profilePictureURL' => nil })
      foto.perform
      outro = create(:contact, account: account, phone_number: '+5511977776666')

      described_class.new(contact: outro, connection: connection, client: client).perform

      expect(client).to have_received(:profile_picture).once
      expect(Redis::Alfred.exists?(described_class.chave_do_contato(outro.id))).to be(false)
    end

    it 'respeita o teto diário da sessão' do
      allow(client).to receive(:profile_picture)
      Redis::Alfred.set("whatsapp_hybrid:foto_do_contato:dia:#{connection.session_name}:#{Time.current.utc.to_date}",
                        described_class::TETO_DIARIO, ex: 60)

      foto.perform

      expect(client).not_to have_received(:profile_picture)
      expect(Redis::Alfred.exists?(described_class.chave_do_contato(contact.id))).to be(false)
    end

    it 'não consulta com a sessão fora do ar, pausada ou em outro número' do
      allow(client).to receive(:profile_picture)
      [{ status: 'disconnected' }, { paused_at: Time.current }, { connected_phone: '5511000000000' }].each do |mudanca|
        connection.update!(status: 'connected', paused_at: nil, connected_phone: numero_da_caixa)
        connection.update!(mudanca)
        described_class.new(contact: contact, connection: connection, client: client).perform
      end

      expect(client).not_to have_received(:profile_picture)
    end

    it 'contato sem telefone não consulta' do
      contact.update!(phone_number: nil, email: 'sem@telefone.com')
      allow(client).to receive(:profile_picture)

      foto.perform

      expect(client).not_to have_received(:profile_picture)
    end
  end

  describe 'job' do
    it 'não busca contato de outra conta' do
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:profile_picture)
      de_fora = create(:contact, phone_number: '+5511966665555')

      WhatsappHybrid::FotoDoContatoJob.perform_now(de_fora.id, connection.inbox_id)

      expect(client).not_to have_received(:profile_picture)
    end
  end

  describe 'gatilho' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    def recebida
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
    end

    before do
      connection
      WhatsappHybrid::Config.forget_inbox(inbox.id)
    end

    it 'mensagem recebida de contato sem foto, com a flag: agenda a busca' do
      account.enable_features!(described_class::FLAG)

      expect { recebida }.to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob).with(contact.id, inbox.id)
    end

    it 'sem a flag, nada' do
      expect { recebida }.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
    end

    it 'contato tentado há pouco, nada' do
      account.enable_features!(described_class::FLAG)
      Redis::Alfred.setex(described_class.chave_do_contato(contact.id), 1, 60)

      expect { recebida }.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
    end

    it 'caixa que não é híbrida, nada' do
      account.enable_features!(described_class::FLAG)
      connection.destroy!
      WhatsappHybrid::Config.forget_inbox(inbox.id)

      expect { recebida }.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
    end
  end
end
