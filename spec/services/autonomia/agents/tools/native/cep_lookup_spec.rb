require 'rails_helper'

# A CONSULTA DE CEP como ferramenta do especialista de ramo com imóvel (autonomia-adapters#87, chat#323).
# O texto que o MODELO recebe é afirmado inteiro nos três casos que importam: endereço, pergunta ao
# cliente e falha técnica. É ele o contrato com o modelo.
RSpec.describe Autonomia::Agents::Tools::Native::CepLookup do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:connector) { Autonomia::Insurance::Connector.client }

  before do
    enable_test_encryption!
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def consultar(cep)
    described_class.new(agent: agent, params: { 'cep' => cep }).call
  end

  it 'e sincrona, esta no catalogo, e so aparece com conexao pronta' do
    expect(described_class.async?).to be(false)
    expect(Autonomia::Agents::Tools::Registry.find('consultar_cep')).to eq(described_class)
    expect(described_class.available_for?(agent)).to be(false)
    ready_connection
    expect(described_class.available_for?(agent)).to be(true)
  end

  describe 'endereco urbano' do
    it 'devolve rua, bairro, cidade e UF, e a regra de so perguntar com indicio' do
      ready_connection

      texto = consultar('01310-100')

      expect(texto).to eq(
        'Endereço do CEP 01310100: Avenida Paulista - de 612 A 1510 - Lado Par, bairro Bela Vista, São Paulo, SP. ' \
        'Com este endereço e com o que o cliente já contou, deduza se o imóvel fica em zona rural ou em área de ' \
        'risco (beira de rio, encosta, morro). Só pergunte isso ao cliente quando houver indício: estrada, sítio, ' \
        'chácara, fazenda ou zona rural no endereço, imóvel perto de rio, encosta ou morro, ou cidade pequena. ' \
        'Endereço urbano comum não pede essa pergunta.'
      )
    end

    it 'o CEP vai ao conector como o cliente escreveu, e o adapter e quem normaliza' do
      ready_connection
      allow(connector).to receive(:cep_lookup).and_call_original

      consultar(' 01310-100 ')

      expect(connector).to have_received(:cep_lookup)
        .with(provider: 'agger', session: hash_including('multicalculoToken' => 'multi'), cep: '01310-100')
    end
  end

  describe 'quando o adapter devolve perguntas' do
    it 'CEP inexistente: diz ao modelo o que perguntar, sem inventar endereco' do
      ready_connection

      texto = consultar('99999999')

      expect(texto).to eq(
        'A consulta deste CEP não trouxe o endereço completo, e sem ele não há como deduzir zona rural nem área ' \
        'de risco. Não invente o endereço. O que perguntar ao cliente antes de seguir: O portal não encontrou ' \
        'este CEP. Confirme o CEP com o cliente.'
      )
    end

    it 'cidade de CEP unico: pergunta a rua e o bairro' do
      ready_connection

      texto = consultar('12600-000')

      expect(texto).to end_with(
        'O que perguntar ao cliente antes de seguir: Este CEP é de cidade de CEP único e não traz o nome da rua. ' \
        'Pergunte ao cliente o nome da rua do imóvel. Este CEP é de cidade de CEP único e não traz o bairro. ' \
        'Pergunte ao cliente o bairro do imóvel.'
      )
    end

    it 'CEP fora do formato: a pergunta do adapter e sobre o proprio CEP' do
      ready_connection

      expect(consultar('1234')).to end_with('O CEP tem 8 dígitos, e o informado não tem. Confirme o CEP com o cliente.')
    end

    it 'validacao sem a lista de perguntas: pede para confirmar o CEP, e nao cala' do
      ready_connection
      allow(connector).to receive(:cep_lookup).and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'x'))

      expect(consultar('01310100')).to end_with('antes de seguir: Confirme o CEP do imóvel com o cliente.')
    end
  end

  describe 'falha tecnica' do
    let(:falha) do
      'Não deu para consultar este CEP agora. Não invente rua, bairro nem cidade: siga com o que o cliente ' \
        'informou, e a cotação consulta o CEP de novo antes de enviar.'
    end

    it 'portal mudo nao derruba o turno e nao inventa endereco' do
      ready_connection
      allow(connector).to receive(:cep_lookup).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'mudo'))

      expect(consultar('01310100')).to eq(falha)
    end

    it 'sem sessao viva nao abre login no turno' do
      ready_connection.forget_session!
      allow(connector).to receive(:open_session).and_call_original

      expect(consultar('01310100')).to eq(falha)
      expect(connector).not_to have_received(:open_session)
    end

    it 'sem conexao pronta tambem e falha tecnica, e nao endereco' do
      expect(consultar('01310100')).to eq(falha)
    end
  end

  it 'CEP vazio e recusado sem tocar o portal' do
    ready_connection
    allow(connector).to receive(:cep_lookup).and_call_original

    expect(consultar('  ')).to eq(described_class::CEP_VAZIO)
    expect(connector).not_to have_received(:cep_lookup)
  end

  # REGRA DA CASA: texto ao modelo sem crase (o modelo a copia para o WhatsApp) e sem travessão.
  it 'nenhum texto da ferramenta tem crase ou travessao' do
    textos = [described_class::CEP_VAZIO, described_class::INDISPONIVEL, described_class::DEDUCAO,
              described_class::SEM_ENDERECO, described_class::PERGUNTA_PADRAO, described_class.description]

    travessoes = [8212, 8211].map { |codigo| codigo.chr(Encoding::UTF_8) }

    expect(textos.join).not_to include('`', *travessoes)
  end
end
