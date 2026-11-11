require 'rails_helper'

# #2858 (F4, saúde): hospitais e clínicas (CNES), exames e procedimentos (TUSS) e nome de doenças (CID-10), pelo caminho
# real (a `Execucao` da pronta de um agente). O CNES vem do WebMock; a TUSS e a CID-10 leem um CSV pequeno de `spec/fixtures/ferramentas_prontas`.
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:fontes) { described_class }
  let(:uso) { Autonomia::FerramentasProntas::Uso.sole }
  let(:fixtures) { Rails.root.join('spec/fixtures/ferramentas_prontas') }

  before do
    resolver_hosts_das_prontas
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, 'agente_ferramentas_prontas_lote2')
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00')) { example.run } }

  def nao_consegui?(saida)
    saida['situacao'] == 'nao_consegui_consultar' && !saida.key?('dados')
  end

  it 'sem a flag do lote, as tres nao entram' do
    account.disable_features!('agente_ferramentas_prontas_lote2')

    %w[hospitais procedimentos doencas].each do |chave|
      expect { incluir_pronta(chave, conta: account, agente: agent) }
        .to raise_error(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
    end
  end

  describe 'Hospitais e clinicas (CNES)' do
    let(:ferramenta) { incluir_pronta('hospitais', conta: account, agente: agent) }
    let(:base) { 'https://apidadosabertos.saude.gov.br/cnes/estabelecimentos?codigo_municipio=350950&status=1&limit=20' }
    let(:hospitais) { "#{base}&codigo_tipo_unidade=5" }
    let(:hospital) do
      { codigo_cnes: 2_023_148, nome_fantasia: 'HOSPITAL SAMARITANO DE CAMPINAS', nome_razao_social: 'ASSOCIACAO EVANGELICA',
        codigo_tipo_unidade: 5, endereco_estabelecimento: 'R DOUTOR JOSE CAMARGO', numero_estabelecimento: '100',
        bairro_estabelecimento: 'VILA JOAO JORGE', codigo_cep_estabelecimento: '13023000',
        numero_telefone_estabelecimento: '(19) 3736-1000', endereco_email_estabelecimento: 'contato@exemplo.test',
        numero_cnpj: '00000000000191', descricao_natureza_juridica_estabelecimento: '3999' }
    end
    # O consultório registrado em nome de pessoa (natureza jurídica 4000): nunca vai ao modelo.
    let(:consultorio_de_pessoa) do
      { codigo_cnes: 128_309, nome_fantasia: 'FULANA DE TAL', codigo_tipo_unidade: 5,
        descricao_natureza_juridica_estabelecimento: '4000' }
    end

    it '"Hospital em Campinas?": pelo nome e UF, so o util, sem pessoa fisica, sem e-mail e sem CNPJ' do
      fonte_responde(hospitais, { estabelecimentos: [hospital, consultorio_de_pessoa] })

      saida = executar_pronta(ferramenta, 'cidade' => 'campinas', 'uf' => 'SP', 'tipo' => 'hospital')

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']).to include('cidade' => 'Campinas', 'uf' => 'SP', 'estado' => 'São Paulo', 'total' => 1)
      expect(saida['dados']['estabelecimentos']).to eq([{ 'nome' => 'HOSPITAL SAMARITANO DE CAMPINAS', 'tipo' => 'Hospital geral',
                                                          'endereco' => 'R DOUTOR JOSE CAMARGO, 100', 'bairro' => 'VILA JOAO JORGE',
                                                          'cep' => '13023000', 'telefone' => '(19) 3736-1000', 'cnes' => '2023148' }])
      expect(saida.to_json).not_to include('FULANA', 'contato@', '00000000000191', 'ASSOCIACAO')
    end

    it 'pelo codigo IBGE de 7 digitos (vai sem o verificador) e com a busca pelo nome, filtrada aqui' do
      outro = hospital.merge(codigo_cnes: 2_081_938, nome_fantasia: 'HOSPITAL SANTA TEREZA')
      fonte_responde(base, { estabelecimentos: [hospital, outro] })

      saida = executar_pronta(ferramenta, 'codigo_ibge' => '3509502', 'busca' => 'santa tereza')

      expect(saida['dados']['estabelecimentos'].pluck('nome')).to eq(['HOSPITAL SANTA TEREZA'])
      expect(a_request(:get, base)).to have_been_made.once
    end

    it 'lista vazia: nao encontrado' do
      fonte_responde(hospitais, { estabelecimentos: [] })

      expect(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital')['situacao']).to eq('nao_encontrado')
    end

    it 'so pessoa fisica na resposta: nao encontrado, e nada dela sai' do
      fonte_responde(hospitais, { estabelecimentos: [consultorio_de_pessoa] })

      saida = executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida.to_json).not_to include('FULANA')
    end

    it 'prazo esgotado: "nao consegui", com o motivo no contador' do
      fonte_lenta(hospitais)

      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital'))).to be(true)
      expect(uso.motivos).to eq('cnes.tempo_esgotado' => 1)
    end

    it 'erro do provedor: "nao consegui"' do
      fonte_fora(hospitais)

      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital'))).to be(true)
      expect(uso.motivos).to eq('cnes.erro_da_fonte' => 1)
    end

    it 'resposta fora do formato da fonte: "nao consegui"' do
      fonte_responde(hospitais, [hospital])

      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital'))).to be(true)
      expect(uso.motivos).to eq('cnes.resposta_invalida' => 1)
    end

    it 'entrada fora do formato: cidade que nao e daquele estado, sem cidade, codigo que nao existe e tipo fora da lista' do
      expect(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'rj')).to include('situacao' => 'pedido_invalido', 'campo' => 'cidade')
      expect(executar_pronta(ferramenta, 'uf' => 'sp')['campo']).to eq('cidade')
      expect(executar_pronta(ferramenta, 'cidade' => 'Campinas')['campo']).to eq('uf')
      expect(executar_pronta(ferramenta, 'codigo_ibge' => '999999')['campo']).to eq('codigo_ibge')
      expect(executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'spa')['campo']).to eq('tipo')
      expect(a_request(:get, /saude\.gov\.br/)).not_to have_been_made
      expect(uso).to have_attributes(consultas: 0, recusadas: 5)
    end
  end

  describe 'Exames e procedimentos (TUSS, tabela no repositorio)' do
    let(:ferramenta) { incluir_pronta('procedimentos', conta: account, agente: agent) }

    before { stub_const("#{fontes::Procedimentos::Tuss}::ARQUIVO", fixtures.join('procedimentos.csv')) }

    it '"O que e o codigo 10101012?": o nome, sem rede; com ponto e traco vale o mesmo' do
      saida = executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '1.01.01.01-2')

      expect(saida['dados']).to eq('codigo' => '10101012', 'nome' => 'Consulta em consultório (no horário normal ou preestabelecido)')
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    end

    it 'a busca pelo nome, sem acento e sem caixa' do
      saida = executar_pronta(ferramenta, 'consulta' => 'busca', 'busca' => 'HEMOGRAMA plaquetas')

      expect(saida['dados']).to include('total' => 1)
      expect(saida['dados']['itens'].first).to include('codigo' => '40304361')
    end

    it 'codigo que nao esta na tabela e busca sem resultado: nao encontrado' do
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '99999999')['situacao']).to eq('nao_encontrado')
      expect(executar_pronta(ferramenta, 'consulta' => 'busca', 'busca' => 'tomografia')['situacao']).to eq('nao_encontrado')
    end

    it 'entrada fora do formato: codigo sem os 8 digitos e consulta que nao existe' do
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '1010')).to include('situacao' => 'pedido_invalido', 'campo' => 'codigo')
      expect(executar_pronta(ferramenta, 'consulta' => 'preco', 'codigo' => '10101012')['campo']).to eq('consulta')
    end

    it 'a tabela ainda nao baixada: "nao consegui", com o motivo' do
      stub_const("#{fontes::Procedimentos::Tuss}::ARQUIVO", fixtures.join('nao_existe.csv'))

      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '10101012'))).to be(true)
      expect(uso.motivos).to eq('tuss.tabela_ausente' => 1)
    end
  end

  describe 'Nome de doencas (CID-10, tabela no repositorio)' do
    let(:ferramenta) { incluir_pronta('doencas', conta: account, agente: agent) }

    before { stub_const("#{fontes::Doencas::Cid10}::ARQUIVO", fixtures.join('doencas.csv')) }

    it '"O que e CID J45?": Asma; a subcategoria com ou sem ponto vai com o ponto' do
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => 'j45')['dados']).to eq('codigo' => 'J45', 'nome' => 'Asma')
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => 'J450')['dados']).to include('codigo' => 'J45.0')
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => 'J45.0')['dados'])
        .to include('nome' => 'Asma predominantemente alérgica')
    end

    it 'a busca pelo nome: todas com o pedaco do nome, sem acento e sem caixa, com o total' do
      saida = executar_pronta(ferramenta, 'consulta' => 'busca', 'busca' => 'ASMA')

      expect(saida['dados']).to include('total' => 3)
      expect(saida['dados']['itens'].pluck('codigo')).to eq(%w[J45 J45.0 J46])
    end

    it 'codigo que nao esta na tabela: nao encontrado' do
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => 'Z99.9')['situacao']).to eq('nao_encontrado')
    end

    it 'entrada fora do formato: sem a letra, curto demais ou texto no lugar do codigo' do
      %w[450 J4 asma].each do |codigo|
        expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => codigo))
          .to include('situacao' => 'pedido_invalido', 'campo' => 'codigo')
      end
    end
  end
end
