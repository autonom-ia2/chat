require 'rails_helper'

# A BUSCA DO SEGURADO ANTES DA PROMESSA (chat#585). Nome, nascimento e sexo são buscados pelo CPF (a razão social,
# pelo CNPJ) só no envio, depois de o especialista dizer que cotou; quando a busca não acha a pessoa, a cotação
# voltava pedindo os dados que já tinham sido dados por resolvidos (versão 7 da prova de 21/09/2026). Agora a
# conferência do turno faz a mesma busca (`quote/enrich`, adapters#75) e pergunta o que ela não achou, antes.
#
# A RESPOSTA É A DO `Connector::Http`, com as chaves em snake_case (`not_found`): a primeira versão deste spec dublou
# `notFound`, a forma do adapter, e o código que a lia passava aqui e falhava em silêncio na sonda real (22/09).
#
# LGPD (revisão da adapters#75): o que a busca ACHA não volta ao modelo. Quem digitasse o CPF de outra pessoa
# ouviria o nome e a data de nascimento dela. Da resposta, só `not_found` é usado.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:connector) { Autonomia::Insurance::Connector.client }
  let(:so_cpf) { { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => '04297912678', 'cep' => '31110-210' } }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  def precheck(params)
    described_class.new(agent: agent, params: params).precheck
  end

  it 'pergunta antes o que a busca pelo documento não achou' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => %w[insured.birthDate insured.gender])

    conferencia = precheck(so_cpf)

    expect(conferencia.motivo).to eq('faltam_dados')
    expect(conferencia.faltando).to include('insured.birthDate', 'insured.gender')
    expect(conferencia.to_s).to include('insured.birthDate')
  end

  it 'o que a busca achou nunca vai ao modelo' do
    achado = { 'insured' => { 'name' => 'FULANA DE TAL', 'birthDate' => '1985-03-14', 'gender' => 'F' } }
    allow(connector).to receive(:quote_enrich).and_return('input' => achado, 'not_found' => ['insured.gender'])

    texto = precheck(so_cpf).to_s

    expect(texto).not_to include('FULANA')
    expect(texto).not_to include('1985')
  end

  it 'achou tudo: segue sem perguntar' do
    allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => [])

    expect(precheck(so_cpf)).to be_nil
  end

  # Consulta paga não se faz por via das dúvidas: com nome, nascimento e sexo na entrada, não se busca.
  it 'com os três na entrada, não busca' do
    allow(connector).to receive(:quote_enrich)
    completo = so_cpf.merge('insured' => { 'name' => 'A', 'birthDate' => '1990-01-01', 'gender' => 'M' })

    precheck(completo)

    expect(connector).not_to have_received(:quote_enrich)
  end

  # A busca é conferência, não portão: se ela cair, a cotação segue — e o envio ainda busca.
  it 'a busca fora do ar não impede a cotação' do
    allow(connector).to receive(:quote_enrich).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'fora'))

    expect(precheck(so_cpf)).to be_nil
  end

  # A busca é paga: com outro dado faltando, a conferência pede esse dado primeiro e não busca (revisão da chat#587).
  it 'com outro dado faltando, não busca' do
    allow(connector).to receive(:quote_enrich)

    precheck(so_cpf.except('cep'))

    expect(connector).not_to have_received(:quote_enrich)
  end

  it 'sem documento, não busca: pedir o documento é da validação' do
    allow(connector).to receive(:quote_enrich)

    precheck('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' })

    expect(connector).not_to have_received(:quote_enrich)
  end

  # NOS OUTROS RAMOS, SÓ O NOME (adapters#92, 22/09/2026): a Lia pede o CPF e nunca o nome, como em auto. A busca
  # roda com o documento e sem o nome, e o que ela não acha vira pergunta, pelo `segurado.nome`.
  describe 'em residencial' do
    let(:residencial) do
      { 'produto' => 'residencial', 'cpf' => '04297912678', 'cep' => '01310-100',
        'dados' => { 'configuracoes' => { 'imovelNumero' => '742', 'imovelTipoResidencia' => 3,
                                          'isDanosIncendioRaioExplosao' => 400_000 } }.to_json }
    end

    it 'pergunta o nome quando a busca não o acha' do
      allow(connector).to receive(:quote_enrich).and_return('input' => {}, 'not_found' => ['segurado.nome'])

      conferencia = precheck(residencial)

      expect(conferencia.motivo).to eq('faltam_dados')
      expect(conferencia.faltando).to eq(['segurado.nome'])
    end

    it 'achou o nome: segue sem perguntar, e o nome achado não vai ao modelo' do
      allow(connector).to receive(:quote_enrich)
        .and_return('input' => { 'segurado' => { 'nome' => 'FULANA DE TAL' } }, 'not_found' => [])

      expect(precheck(residencial)).to be_nil
      expect(connector).to have_received(:quote_enrich).with(hash_including(product: 'residencial'))
    end

    it 'com o nome informado, não busca' do
      allow(connector).to receive(:quote_enrich)

      precheck(residencial.merge('nome' => 'Fulana de Tal'))

      expect(connector).not_to have_received(:quote_enrich)
    end
  end
end
