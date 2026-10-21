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

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

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

    [Waha::Client::Error.new('limite', status: 429), Waha::Client::Error.new('motor', status: 502),
     Waha::Client::Timeout.new('sem resposta'), Errno::ECONNRESET.new].each do |falha|
      it "#{falha.class} #{falha.try(:status)}: erro do motor pausa a sessão e devolve o contato" do
        allow(client).to receive(:profile_picture).and_raise(falha)

        foto.perform

        expect(Redis::Alfred.exists?(described_class.chave_da_sessao(connection.session_name))).to be(true)
        expect(Redis::Alfred.exists?(described_class.chave_do_contato(contact.id))).to be(false)
      end
    end

    [Waha::Client::NotFound.new('contato', status: 404), Waha::Client::Error.new('pedido', status: 400), 'texto em vez de objeto']
      .each do |falha|
      it "#{falha.class} #{falha.try(:status)}: erro do contato só adia aquele contato 1 dia, a sessão segue" do
        if falha.is_a?(String)
          allow(client).to receive(:profile_picture).and_return(falha)
        else
          allow(client).to receive(:profile_picture).and_raise(falha)
        end

        foto.perform

        expect(Redis::Alfred.exists?(described_class.chave_da_sessao(connection.session_name))).to be(false)
        expect(Redis::Alfred.ttl(described_class.chave_do_contato(contact.id))).to be_within(60).of(described_class::ADIADO.to_i)
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

    it 'com teto menor (backfill), não consulta quando a sessão já chegou nele no dia, e não gasta a cota' do
      allow(client).to receive(:profile_picture)
      chave = described_class.chave_do_dia(connection.session_name)
      Redis::Alfred.set(chave, 80, ex: 60)

      described_class.new(contact: contact, connection: connection, client: client, teto: 80).perform

      expect(client).not_to have_received(:profile_picture)
      expect(Redis::Alfred.get(chave).to_i).to eq(80)
      expect(Redis::Alfred.exists?(described_class.chave_do_contato(contact.id))).to be(false)
    end

    it 'não consulta com a sessão fora do ar, pausada, em outro número ou com o WhatsApp API desligado na caixa' do
      allow(client).to receive(:profile_picture)
      [{ status: 'disconnected' }, { paused_at: Time.current }, { connected_phone: '5511000000000' },
       { routing_enabled: false }].each do |mudanca|
        connection.update!(status: 'connected', paused_at: nil, connected_phone: numero_da_caixa, routing_enabled: true)
        connection.update!(mudanca)
        described_class.new(contact: contact, connection: connection, client: client).perform
      end

      expect(client).not_to have_received(:profile_picture)
    end

    it 'não consulta com o Híbrido desligado na plataforma ou fora da lista de contas' do
      allow(client).to receive(:profile_picture)

      with_modified_env(WHATSAPP_HYBRID_ROUTING_ENABLED: 'false') { foto.perform }
      with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '') { foto.perform }

      expect(client).not_to have_received(:profile_picture)
    end

    it 'contato que já tem foto não consulta' do
      contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      allow(client).to receive(:profile_picture)

      foto.perform

      expect(client).not_to have_received(:profile_picture)
    end

    it 'contato sem telefone não consulta e fica 30 dias sem tentar' do
      contact.update!(phone_number: nil, email: 'sem@telefone.com')
      allow(client).to receive(:profile_picture)

      foto.perform

      expect(client).not_to have_received(:profile_picture)
      expect(Redis::Alfred.ttl(described_class.chave_do_contato(contact.id))).to be_within(60).of(described_class::SEM_FOTO.to_i)
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

    it 'histórico importado pela coexistência não dispara' do
      account.enable_features!(described_class::FLAG)

      expect do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                         content_attributes: { history_import: true })
      end.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
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
