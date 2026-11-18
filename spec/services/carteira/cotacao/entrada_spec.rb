require 'rails_helper'

# E8 (#2901): a entrada da cotação montada da carteira nunca sai completa sem o que a busca paga do segurado (`quote/enrich`)
# acharia pelo documento. Assim a conferência da ferramenta nunca a chama no caminho da carteira. Tudo fictício.
RSpec.describe Carteira::Cotacao::Entrada do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:conexao) { Autonomia::Insurance::Connection.create!(account: account, username: 'corretora@exemplo.test', password: 'senha-exemplo') }

  before do
    enable_test_encryption!
    allow(Autonomia::Agents::Tools::Native::InsuranceQuote).to receive(:schema_da_conexao).and_return('campos' => [])
  end

  def entrada_de(pessoa, tipo)
    seguro = criar_apolice(pessoa, tipo: tipo, seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date)
    described_class.new(seguro, conexao).call
  end

  it 'auto: sem nascimento e sexo na carteira, os dois faltam' do
    marina = create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023')

    expect(entrada_de(marina, 'auto').faltam).to include('insured.birthDate', 'insured.gender')
  end

  # E8.1 (#3043): os dados do segurado que a carteira passou a guardar.
  describe 'nascimento, sexo, CEP, placa e classe de bônus' do
    let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
    let(:do_segurado) { { segurado_nascimento: '1985-03-15', segurado_sexo: 'F', cep: '12345678', placa: 'EXM0A00', bonus_classe: 5 } }

    def seguro_de(pessoa, tipo, **campos)
      criar_apolice(pessoa, tipo: tipo, seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date, **campos)
    end

    def ramo_com(*campos)
      allow(Autonomia::Agents::Tools::Native::InsuranceQuote).to receive(:schema_da_conexao).and_return('campos' => campos)
    end

    it 'auto, segurado pessoa com tudo guardado: os cinco vão nos parâmetros e só falta o que a carteira não tem' do
      Relacionamentos::Documentos.new(account).guardar(marina, '529.982.247-25')

      entrada = described_class.new(seguro_de(marina, 'auto', **do_segurado), conexao).call

      expect(entrada.params).to include('cep' => '12345678', 'insured' => { 'birthDate' => '1985-03-15', 'gender' => 'F' },
                                        'vehicle' => { 'plate' => 'EXM0A00' })
      expect(entrada.params['quotation']).to include('bonusClass' => 5)
      expect(entrada.faltam).to eq(['quotation.previousInsurerCode'])
    end

    it 'auto, empresa segurada: o nascimento e o sexo guardados não vão, e seguem faltando' do
      empresa = create(:company, account: account, name: 'Padaria Amostra Ltda.')

      entrada = described_class.new(seguro_de(marina, 'auto', company: empresa, **do_segurado), conexao).call

      expect(entrada.params.keys).not_to include('insured')
      expect(entrada.faltam).to include('insured.birthDate', 'insured.gender')
      expect(entrada.faltam).not_to include('address.zipCode', 'vehicle.plate', 'quotation.bonusClass')
    end

    it 'outros ramos: a classe de bônus só vai quando é um dos valores da lista do formulário; fora dela, falta' do
      ramo_com({ 'campo' => 'renovacao.bonus', 'valores' => { '4' => 'Classe 4', '5' => 'Classe 5' } })

      na_lista = described_class.new(seguro_de(marina, 'residencial', bonus_classe: 5), conexao).call
      fora = described_class.new(seguro_de(marina, 'residencial', numero: 'EX-000002', bonus_classe: 7), conexao).call

      expect([na_lista.params['renovacao']['bonus'], na_lista.faltam.include?('renovacao.bonus')]).to eq([5, false])
      expect([fora.params['renovacao'].key?('bonus'), fora.faltam.include?('renovacao.bonus')]).to eq([false, true])
    end

    it 'outros ramos: o CEP vai pelo atalho e deixa de faltar no formulário que o pede' do
      ramo_com({ 'campo' => 'segurado.cep', 'obrigatorio' => true, 'origem' => 'cliente' })

      sem_cep = described_class.new(seguro_de(marina, 'residencial'), conexao).call
      com_cep = described_class.new(seguro_de(marina, 'residencial', numero: 'EX-000002', cep: '12345678'), conexao).call

      expect(sem_cep.faltam).to include('segurado.cep')
      expect([com_cep.params['cep'], com_cep.faltam.include?('segurado.cep')]).to eq(['12345678', false])
    end
  end

  it 'outros ramos: sem o nome do segurado, ele falta mesmo quando o formulário do ramo não o pede' do
    sem_nome = create(:contact, account: account, name: '', phone_number: '+5511900000024')

    expect(entrada_de(sem_nome, 'residencial').faltam).to include('segurado.nome')
  end

  it 'outros ramos: com o nome, ele não falta' do
    marina = create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023')

    expect(entrada_de(marina, 'residencial').faltam).not_to include('segurado.nome')
  end

  # A lista da Entrada presa à da ferramenta (InsuranceQuote::Veiculo#busca_do_segurado?, que não muda aqui): com tudo o
  # que a Entrada exige do segurado, a busca paga não roda; faltando qualquer um, roda. Se a busca passar a procurar outro
  # campo do segurado, o primeiro caso de cada ramo falha.
  describe 'amarrada à busca paga da ferramenta de cotação' do
    let(:buscados) { described_class::BUSCADOS_PELO_DOCUMENTO }

    def busca_paga?(produto, entrada)
      ferramenta = Autonomia::Agents::Tools::Native::InsuranceQuote.new(agent: nil, params: { 'produto' => produto })
      allow(ferramenta).to receive_messages(entrada: entrada,
                                            quote_input: instance_double(Autonomia::Insurance::QuoteInput, auto?: produto == 'auto'))
      ferramenta.send(:busca_do_segurado?)
    end

    def com(caminhos, documento)
      caminhos.each_with_object(documento.deep_dup) do |caminho, entrada|
        grupo, campo = caminho.split('.')
        (entrada[grupo] ||= {})[campo] = 'Exemplo'
      end
    end

    it 'auto: o que a busca acha está nos obrigatórios da Entrada' do
      expect(described_class::OBRIGATORIOS_DE_AUTO).to include(*buscados['auto'])
    end

    it 'auto: com tudo o que a Entrada exige, a busca não roda; faltando um, roda' do
      documento = { 'insured' => { 'document' => '52998224725' } }

      expect(busca_paga?('auto', com(buscados['auto'], documento))).to be(false)
      buscados['auto'].each do |faltando|
        expect(busca_paga?('auto', com(buscados['auto'] - [faltando], documento))).to be(true)
      end
    end

    it 'outros ramos: com o nome, a busca não roda; sem ele, roda' do
      documento = { 'segurado' => { 'cpfCnpj' => '52998224725' } }

      expect(busca_paga?('residencial', com(buscados[nil], documento))).to be(false)
      expect(busca_paga?('residencial', documento)).to be(true)
    end
  end
end
