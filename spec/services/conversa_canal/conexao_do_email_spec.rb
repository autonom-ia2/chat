require 'rails_helper'

# #1870 — conexão da escrita do lido: lock da caixa, credencial conferida e classificação das falhas na entrada.
RSpec.describe ConversaCanal::ConexaoDoEmail do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:chave_do_lock) { ConversaCanal::LockDaCaixa.chave(channel.inbox) }
  let(:recusa) { described_class::CredencialRecusada }

  def resposta(nome, texto)
    Net::IMAP::TaggedResponse.new('A1', nome, Net::IMAP::ResponseText.new(nil, texto), '')
  end

  def oauth(status)
    OAuth2::Error.new(double('resposta do provedor', status: status)) # rubocop:disable RSpec/VerifiedDoubles
  end

  def abrir
    described_class.abrir(Channel::Email.find(channel.id)) { |conexao, _lock| conexao }
  end

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    Redis::Alfred.delete(chave_do_lock)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(authenticate: nil, select: nil, logout: nil, disconnect: nil)
  end

  after { Redis::Alfred.delete(chave_do_lock) }

  it 'segura o lock da caixa durante o bloco, entrega o lock para renovar e solta no fim' do
    described_class.abrir(channel) do |conexao, lock|
      expect(conexao).to eq(imap)
      expect(lock.renovar).to be(true)
      expect(Redis::Alfred.get(chave_do_lock)).to be_present
    end

    expect(Redis::Alfred.get(chave_do_lock)).to be_nil
    expect(imap).to have_received(:logout)
  end

  it 'caixa ocupada pela importação: nem conecta, e o lock dela fica' do
    Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300)

    expect { abrir }.to raise_error(MutexApplicationJob::LockAcquisitionError)
    expect(Net::IMAP).not_to have_received(:new)
    expect(Redis::Alfred.get(chave_do_lock)).to eq('lock-da-importacao')
  end

  describe 'credencial recusada (descarte)' do
    it 'caixa marcada para reautorizar: antes de conectar' do
      chave = channel.send(:reauthorization_required_key)
      Redis::Alfred.set(chave, true)

      expect { abrir }.to raise_error(recusa)
      expect(Net::IMAP).not_to have_received(:new)
    ensure
      Redis::Alfred.delete(chave)
    end

    it 'NO no LOGIN/AUTHENTICATE: recusa e socket fechado' do
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::NoResponseError.new(resposta('NO', 'Invalid credentials')))

      expect { abrir }.to raise_error(recusa)
      expect(imap).to have_received(:disconnect)
    end

    it 'BAD no LOGIN/AUTHENTICATE: recusa' do
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::BadResponseError.new(resposta('BAD', 'Syntax')))

      expect { abrir }.to raise_error(recusa)
    end

    it 'mecanismo que a net-imap não conhece: recusa antes do AUTHENTICATE' do
      channel.update!(imap_authentication: 'xpto')

      expect { abrir }.to raise_error(recusa)
      expect(imap).not_to have_received(:authenticate)
      expect(imap).to have_received(:disconnect)
    end

    it 'ArgumentError de dentro da autenticação (bug nosso, como senha nil) não é recusa: sai como é' do
      allow(imap).to receive(:authenticate).and_raise(ArgumentError, 'senha nil')

      expect { abrir }.to raise_error(ArgumentError) { |erro| expect(erro).not_to be_a(recusa) }
    end

    [nil, '', 'plain', 'PLAIN', 'cram-md5'].each do |mecanismo|
      it "mecanismo #{mecanismo.inspect} passa pela conferência e autentica" do
        channel.update_column(:imap_authentication, mecanismo) # rubocop:disable Rails/SkipsModelValidations

        expect(abrir).to eq(imap)
        expect(imap).to have_received(:authenticate).with(mecanismo == 'cram-md5' ? 'CRAM-MD5' : (mecanismo.presence || 'plain'), any_args)
      end
    end

    it 'LOGIN passa pela conferência do mecanismo' do
      channel.update!(imap_authentication: 'login')
      allow(imap).to receive(:login)

      expect(abrir).to eq(imap)
      expect(imap).to have_received(:login)
    end
  end

  describe 'transitórios saem como são (o job tenta de novo)' do
    it 'BYE no LOGIN' do
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::ByeResponseError.new(resposta('BYE', 'Too many logins')))

      expect { abrir }.to raise_error(Net::IMAP::ByeResponseError)
    end

    it 'NO no SELECT (fora da autenticação)' do
      allow(imap).to receive(:select).and_raise(Net::IMAP::NoResponseError.new(resposta('NO', 'Try again')))

      expect { abrir }.to raise_error(Net::IMAP::NoResponseError)
      expect(imap).to have_received(:disconnect)
    end

    [Timeout::Error, Net::OpenTimeout, SocketError].each do |classe|
      it "#{classe} ao conectar" do
        allow(Net::IMAP).to receive(:new).and_raise(classe, 'rede')

        expect { abrir }.to raise_error(classe)
      end
    end
  end

  context 'with Microsoft (OAuth)' do
    let(:channel) { create(:channel_email, :microsoft_email, account: account) }
    let(:renovacao) { instance_double(Microsoft::RefreshOauthTokenService) }

    before { allow(Microsoft::RefreshOauthTokenService).to receive(:new).and_return(renovacao) }

    it 'renova o token dentro do lock e autentica com XOAUTH2' do
      allow(renovacao).to receive(:access_token) do
        expect(Redis::Alfred.get(chave_do_lock)).to be_present
        'token'
      end

      abrir

      expect(imap).to have_received(:authenticate).with('XOAUTH2', channel.imap_login, 'token')
    end

    it 'OAuth 4xx (invalid_grant): recusa' do
      allow(renovacao).to receive(:access_token).and_raise(oauth(400))

      expect { abrir }.to raise_error(recusa)
    end

    it 'OAuth 5xx: transitório, sai como é' do
      allow(renovacao).to receive(:access_token).and_raise(oauth(503))

      expect { abrir }.to raise_error(OAuth2::Error)
    end

    it 'refresh_token ausente no meio da renovação (RuntimeError puro): recusa' do
      allow(renovacao).to receive(:access_token).and_raise(RuntimeError, 'A refresh_token is not available')

      expect { abrir }.to raise_error(recusa)
    end

    it 'access_token vazio: recusa sem contar erro de autorização na caixa (sem e-mail de reautorização)' do
      channel.update_columns(provider_config: channel.provider_config.merge('access_token' => '')) # rubocop:disable Rails/SkipsModelValidations

      expect { abrir }.to raise_error(recusa)
      expect(channel.reload.authorization_error_count).to eq(0)
      expect(Net::IMAP).not_to have_received(:new)
    end

    it 'refresh_token vazio: recusa antes de conectar' do
      channel.update_columns(provider_config: channel.provider_config.merge('refresh_token' => '')) # rubocop:disable Rails/SkipsModelValidations

      expect { abrir }.to raise_error(recusa)
      expect(Net::IMAP).not_to have_received(:new)
    end
  end
end
