require 'rails_helper'

# UM FORMULÁRIO POR ESPECIALISTA (chat#591, receita de ramo, fase 2). Cada especialista vê na
# ferramenta de cotação o formulário do seu ramo, descoberto pela chave `ramo` de
# `Builder::ESPECIALISTAS`. Hoje só existe o de auto; o de residencial entra na fase 5, e aqui ele é
# simulado acrescentando a entrada à lista, exatamente como a fase 5 fará.
#
# O que se prova:
#   auto não muda: sem especialista, com o de auto, ou com um que a corretora criou, o formulário é o de
#     sempre (comuns + auto);
#   o de residencial vê os campos de cliente de residencial, sem `dados` e sem nada de auto;
#   o formulário de residencial passa no modo `strict` da OpenAI: toda chave em `required`, opcional pelo
#     tipo com `null`, e o `enum` aceitando `null` (sem ele o opcional deixa de ser opcional e a chamada
#     cai, como em 08/09/2026);
#   formulário recusado (campo sem descrição) volta ao `dados`, com o erro no log, e não emudece o turno.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:lia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:schema_residencial) { Autonomia::Insurance::Connector::Mock::SCHEMA_RESIDENCIAL }
  let(:builder) { Autonomia::Insurance::QuoteAgent::Builder }
  let(:schemas_guardados) { { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO, 'residencial' => schema_residencial } }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready', metadata: { 'quote_schemas' => schemas_guardados })
    allow(Autonomia::Insurance::Connector).to receive(:client).and_raise('não deveria chamar o adapter')
  end

  def especialista(slug)
    Autonomia::Agents::Specialist.create!(agent: lia, account: account, slug: slug, name: slug,
                                          description: 'cota', instruction: 'Cote.')
  end

  def com_especialista_de_residencial
    stub_const("#{builder}::ESPECIALISTAS",
               builder::ESPECIALISTAS + [{ slug: 'cotacao_residencial', ramo: 'residencial', nome: 'Residencial',
                                           arquivo: 'especialista_auto.md', descricao: 'Cota residencial.' }])
    especialista('cotacao_residencial')
  end

  def nomes(lista)
    lista.pluck('name')
  end

  describe 'auto não muda' do
    let(:de_sempre) { described_class.params + Autonomia::Insurance::Parametros.de_auto(schemas_guardados['auto']) }

    it 'sem especialista, com o de auto ou com um que a corretora criou, o formulário é o de sempre' do
      proprio = Autonomia::Agents::Specialist.create!(
        agent: Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                                enabled: true, instruction: 'Atenda.'),
        account: account, slug: 'cotacao_residencial', name: 'x', description: 'x', instruction: 'x'
      )

      expect(described_class.params_for(lia)).to eq(de_sempre)
      expect(described_class.params_for(lia, especialista: especialista('cotacao_auto'))).to eq(de_sempre)
      expect(described_class.params_for(lia, especialista: proprio)).to eq(de_sempre)
      expect(builder::ESPECIALISTAS.pluck(:ramo)).to eq(%w[auto residencial])
    end
  end

  describe 'o especialista de residencial' do
    it 'vê os campos de cliente de residencial, sem dados e sem nada de auto' do
      params = described_class.params_for(lia, especialista: com_especialista_de_residencial)

      expect(nomes(params)).to eq(nomes(described_class.params) - ['dados'] + %w[segurado configuracoes])
      expect(params.flat_map { |p| Array(p['properties']) }.size).to eq(31)
    end

    it 'chega ao modelo pelo catálogo do especialista (Specialist#tools), e o do principal segue o de auto' do
      residencial = com_especialista_de_residencial

      do_especialista = residencial.tools.find { |t| t.slug == 'cotar_seguro' }.openai_schema
      do_principal = Autonomia::Agents::Tools::Bound.for_agent(lia).find { |t| t.slug == 'cotar_seguro' }.openai_schema

      expect(do_especialista[:parameters][:properties].keys).to include('configuracoes')
      expect(do_especialista[:parameters][:properties].keys).not_to include('vehicle', 'dados')
      expect(do_principal[:parameters][:properties].keys).to include('vehicle', 'dados')
    end

    # A DESCRIÇÃO SAI DOS PARÂMETROS (revisão da #592): o especialista com formulário não recebe `dados`, e a
    # descrição não pode mandar escrever nele. A do principal (auto) é a de sempre, byte a byte.
    it 'a descrição da ferramenta acompanha o formulário: sem dados, ela não fala em dados' do
      do_especialista = described_class.openai_schema(lia, especialista: com_especialista_de_residencial)
      do_principal = described_class.openai_schema(lia)

      expect(do_especialista[:description]).to eq(described_class::DESCRICAO_COM_FORMULARIO)
      expect(do_especialista[:description]).not_to include('dados')
      expect(do_principal[:description]).to eq(described_class::DESCRICAO)
    end

    it 'formulário do ramo recusado volta ao dados, e a descrição volta à que fala dele' do
      quebrado = schema_residencial.merge('campos' => schema_residencial['campos'] +
        [{ 'campo' => 'configuracoes.novo', 'tipo' => 'texto', 'origem' => 'cliente' }])
      Autonomia::Insurance::Connection.for_account(account).first
                                      .update!(metadata: { 'quote_schemas' => { 'residencial' => quebrado } })
      allow(Rails.logger).to receive(:error)

      schema = described_class.openai_schema(lia, especialista: com_especialista_de_residencial)

      expect(schema[:parameters][:properties].keys).to include('dados')
      expect(schema[:description]).to eq(described_class::DESCRICAO)
    end

    it 'passa no modo strict: toda chave em required, opcional pelo tipo com null, enum aceitando null' do
      schema = described_class.openai_schema(lia, especialista: com_especialista_de_residencial)[:parameters]
      configuracoes = schema[:properties]['configuracoes']
      uso = configuracoes[:properties]['imovelUso']

      [schema, configuracoes, schema[:properties]['segurado']].each do |objeto|
        expect(objeto[:required]).to match_array(objeto[:properties].keys)
        expect(objeto[:additionalProperties]).to be(false)
      end
      expect(configuracoes[:type]).to eq(%w[object null])
      expect(configuracoes[:properties].values).to all(satisfy { |p| Array(p['type']).include?('null') })
      expect(uso['type']).to eq(%w[number null])
      expect(uso['enum']).to eq([1, 2, 3, nil])
    end

    describe 'quando o adapter publica um campo de cliente sem descrição' do
      let(:schemas_guardados) do
        quebrado = schema_residencial.merge('campos' => schema_residencial['campos'] +
          [{ 'campo' => 'configuracoes.novo', 'tipo' => 'texto', 'origem' => 'cliente' }])
        { 'residencial' => quebrado }
      end

      it 'o formulário é recusado, o ramo volta ao dados, e o erro fica no log com o campo' do
        allow(Rails.logger).to receive(:error)

        params = described_class.params_for(lia, especialista: com_especialista_de_residencial)

        expect(params).to eq(described_class.params)
        expect(Rails.logger).to have_received(:error).with(a_string_including('configuracoes.novo sem descricao'))
      end
    end

    describe 'sem schema guardado e com o adapter mudo' do
      let(:schemas_guardados) { {} }

      it 'fica com o dados, como antes da chat#591' do
        expect(described_class.params_for(lia, especialista: com_especialista_de_residencial)).to eq(described_class.params)
      end
    end
  end
end
