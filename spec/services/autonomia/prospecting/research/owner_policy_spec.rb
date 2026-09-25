require 'rails_helper'

# Porte de owner-policy.test.ts do Orth, mais os motivos de "sem decisor" que o chat2you mostra em português.
# No Orth a política recebe a qualificação crua; aqui ela chega normalizada pelo parser (Registry::Partner.build), então
# as expectativas de qualificação usam o rótulo canônico.
RSpec.describe Autonomia::Prospecting::Research::OwnerPolicy do
  let(:registry) { Autonomia::Prospecting::Research::Registry }

  def partner(name: 'Pessoa Teste', qualification: 'SÓCIO', person_type: 'PF', is_minor: false)
    registry::Partner.build(name: name, qualification: qualification, person_type: person_type, is_minor: is_minor)
  end

  def company(qsa: [], legal_name: 'EMPRESA ALFA SINTETICA LTDA', nature_code: 2062, nature_text: 'Sociedade Empresária Limitada')
    registry::Company.new(
      cnpj: '11222333000181', legal_name: legal_name, trade_name: nil, registration_status: 'ATIVA',
      registration_state: 'SP', city: 'SAO PAULO', legal_nature_code: nature_code, legal_nature_text: nature_text,
      opened_on: nil, cnae: nil, provider: 'OpenCNPJ', sources: [], qsa: qsa
    )
  end

  def select(qsa: [], requested_role: 'owner', **company_args)
    described_class.select(company: company(qsa: qsa, **company_args), requested_role: requested_role)
  end

  describe 'quadro de sócios' do
    it 'seleciona toda qualificação de dono PF na ordem do provedor' do
      raw = ['SÓCIO-ADMINISTRADOR', 'SÓCIO', 'TITULAR', 'EMPRESÁRIO INDIVIDUAL', 'PROPRIETÁRIO', 'ACIONISTA CONTROLADOR']
      selection = select(qsa: raw.each_with_index.map { |q, i| partner(name: "Pessoa #{i + 1}", qualification: q) })

      expect(selection.owners).to eq(
        [
          { 'name' => 'Pessoa 1', 'qualification' => 'Sócio-Administrador' },
          { 'name' => 'Pessoa 2', 'qualification' => 'Sócio' },
          { 'name' => 'Pessoa 3', 'qualification' => 'Titular' },
          { 'name' => 'Pessoa 4', 'qualification' => 'Empresário Individual' },
          { 'name' => 'Pessoa 5', 'qualification' => 'Proprietário' },
          { 'name' => 'Pessoa 6', 'qualification' => 'Acionista Controlador' }
        ]
      )
      expect(selection.decision).to eq(selection.owners.first)
      expect(selection.reason).to be_nil
      expect(selection.evidence).to eq(:qsa)
    end

    it 'trata cargos de comando como donos, não como possíveis' do
      selection = select(qsa: [partner(name: 'Dir', qualification: 'DIRETOR'), partner(name: 'Pres', qualification: 'PRESIDENTE'),
                               partner(name: 'Ceo', qualification: 'CEO')])

      expect(selection.owners.pluck('name')).to eq(%w[Dir Pres Ceo])
    end

    it 'trata Administrador como dono' do
      expect(select(qsa: [partner(name: 'Adm', qualification: 'Administrador')]).owners)
        .to eq([{ 'name' => 'Adm', 'qualification' => 'Administrador' }])
    end

    it 'põe sócio-administrador antes de administrador, mesmo quando o provedor manda o administrador primeiro' do
      selection = select(qsa: [partner(name: 'Adm', qualification: 'Administrador'), partner(name: 'Diretora', qualification: 'Diretor'),
                               partner(name: 'Socia', qualification: 'Sócio-Administrador')])

      expect(selection.owners.pluck('name')).to eq(%w[Socia Adm Diretora])
      expect(selection.decision['name']).to eq('Socia')
    end

    it 'nomeia os administradores quando os sócios são pessoa jurídica' do
      selection = select(qsa: [partner(name: 'Holding A', person_type: 'PJ'), partner(name: 'Holding B', person_type: 'PJ'),
                               partner(name: 'Adm 1', qualification: 'Administrador'),
                               partner(name: 'Adm 2', qualification: 'Administrador')])

      expect(selection.owners.pluck('name')).to eq(['Adm 1', 'Adm 2'])
    end

    it 'mantém vários donos válidos, sem declarar ambiguidade' do
      selection = select(qsa: [partner(name: 'Ana', qualification: 'SÓCIO'), partner(name: 'Bruno', qualification: 'TITULAR')])

      expect(selection.owners.pluck('name')).to eq(%w[Ana Bruno])
    end

    it 'exclui o menor de idade, mesmo sendo sócio' do
      selection = select(qsa: [partner(name: 'Menor', is_minor: true), partner(name: 'Mae', qualification: 'Administrador')])

      expect(selection.owners.pluck('name')).to eq(['Mae'])
    end

    {
      'pessoa jurídica' => { person_type: 'PJ' }, 'procurador' => { qualification: 'PROCURADOR' },
      'representante legal' => { qualification: 'REPRESENTANTE LEGAL' }, 'tipo desconhecido' => { person_type: 'UNKNOWN' }
    }.each do |label, attributes|
      it "não nomeia #{label}" do
        selection = select(qsa: [partner(**attributes)])

        expect(selection.owners).to eq([])
        expect(selection.decision).to be_nil
        expect(selection.evidence).to be_nil
      end
    end
  end

  describe 'motivo de não ter decisor' do
    it 'only_companies quando só há pessoa jurídica no quadro' do
      expect(select(qsa: [partner(name: 'Holding', person_type: 'PJ')]).reason).to eq('only_companies')
    end

    it 'only_minors quando a única pessoa física é menor' do
      expect(select(qsa: [partner(is_minor: true), partner(name: 'Holding', person_type: 'PJ')]).reason).to eq('only_minors')
    end

    it 'no_eligible_role quando há adulto PF sem cargo de comando' do
      expect(select(qsa: [partner(name: 'Contador', qualification: 'Contador')]).reason).to eq('no_eligible_role')
    end

    it 'no_qsa quando o quadro vem vazio numa sociedade' do
      expect(select(qsa: []).reason).to eq('no_qsa')
    end

    it 'public_entity para autarquia sem quadro, ainda que a razão social pareça nome de pessoa' do
      selection = select(qsa: [], legal_name: 'JUNTA COMERCIAL SINTETICA', nature_code: 1244,
                         nature_text: 'Autarquia Estadual ou do Distrito Federal')

      expect(selection.owners).to eq([])
      expect(selection.reason).to eq('public_entity')
    end

    it 'public_entity pelo código 1xxx mesmo sem texto, e o código manda quando existe' do
      expect(select(qsa: [], nature_code: 1120, nature_text: nil).reason).to eq('public_entity')
      expect(select(qsa: [], nature_code: 2062, nature_text: 'Autarquia Municipal').reason).to eq('no_qsa')
    end

    it 'public_entity pelo texto quando o provedor não manda código (OpenCNPJ)' do
      selection = select(qsa: [], legal_name: 'AUTARQUIA SINTETICA', nature_code: nil, nature_text: 'Autarquia Municipal')

      expect(selection.reason).to eq('public_entity')
    end

    it 'explicit_role_not_supported para cargo que o cadastro público não responde' do
      selection = select(qsa: [partner], requested_role: 'commercial')

      expect(selection.owners).to eq([])
      expect(selection.reason).to eq('explicit_role_not_supported')
    end

    it 'expõe a lista fechada de motivos' do
      expect(described_class::REASONS).to eq(%w[explicit_role_not_supported public_entity no_qsa only_companies only_minors no_eligible_role])
    end
  end

  # Empresário Individual não tem quadro de sócios. A razão social é o nome civil do titular (art. 1.156 do Código Civil).
  describe 'empresário individual' do
    it 'nomeia o titular pelo código 2135 da Receita, com evidência na razão social' do
      selection = select(qsa: [], legal_name: 'FULANO DE TAL SINTETICO', nature_code: 2135, nature_text: nil)

      expect(selection.owners).to eq([{ 'name' => 'FULANO DE TAL SINTETICO', 'qualification' => 'Empresário Individual' }])
      expect(selection.evidence).to eq(:legal_name)
      expect(selection.reason).to be_nil
    end

    it 'nomeia pelo texto quando o provedor não manda código (OpenCNPJ)' do
      selection = select(qsa: [], legal_name: 'FULANO DE TAL SINTETICO', nature_code: nil, nature_text: 'Empresário (Individual)')

      expect(selection.decision).to eq('name' => 'FULANO DE TAL SINTETICO', 'qualification' => 'Empresário Individual')
    end

    it 'tira do nome o número que o MEI carrega na razão social (raiz do CNPJ antes, CPF depois)' do
      expect(select(qsa: [], legal_name: '12.345.678 FULANO DE TAL', nature_code: 2135).decision['name']).to eq('FULANO DE TAL')
      expect(select(qsa: [], legal_name: 'FULANO DE TAL 12345678901', nature_code: 2135).decision['name']).to eq('FULANO DE TAL')
    end

    it 'recusa sociedade limitada sem quadro' do
      expect(select(qsa: [], legal_name: 'EMPRESA ALFA SINTETICA LTDA').decision).to be_nil
    end

    it 'recusa quando não há razão social para nomear' do
      [nil, '', '   ', '12.345.678'].each do |legal_name|
        expect(select(qsa: [], legal_name: legal_name, nature_code: 2135).decision).to be_nil
      end
    end

    it 'recusa natureza ausente' do
      expect(select(qsa: [], legal_name: 'FULANO', nature_code: nil, nature_text: nil).reason).to eq('no_qsa')
    end
  end

  describe '#storable_owners' do
    it 'passa cada dono pela lista fechada de campos de pessoa física' do
      selection = select(qsa: [partner(name: 'Ana')])

      expect(selection.storable_owners).to eq([{ 'name' => 'Ana', 'qualification' => 'Sócio' }])
    end
  end
end
