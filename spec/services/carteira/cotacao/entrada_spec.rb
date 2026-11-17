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
