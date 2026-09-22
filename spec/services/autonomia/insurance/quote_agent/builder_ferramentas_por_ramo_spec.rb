require 'rails_helper'

# A CONSULTA QUE ANTECEDE A COTAÇÃO É DO RAMO (autonomia-adapters#87). `consultar_cep` entra no catálogo
# e vai só ao especialista de ramo com imóvel; hoje só existe o de auto, e ele NÃO a recebe. O vínculo é
# dado (`CONSULTAS_DO_RAMO`), e aqui se prova as duas pontas:
#   auto não muda: as listas são as de antes de #87, literais, na mesma ordem;
#   residencial está pronto: acrescentar a entrada em `ESPECIALISTAS` (fase 5) basta para ele receber a
#     consulta de CEP e não a de placa.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  # As listas de antes de #87, escritas por extenso: comparar com a própria constante não provaria nada.
  let(:do_especialista_de_auto) { %w[consultar_placa cotar_seguro ver_resultado_da_cotacao] }
  let(:do_agente) do
    %w[consultar_produtos_cotacao consultar_condicoes_gerais enviar_proposta_da_seguradora
       consultar_placa cotar_seguro ver_resultado_da_cotacao]
  end
  let(:residencial) do
    { slug: 'cotacao_residencial', ramo: 'residencial', nome: 'Residencial', arquivo: 'especialista_auto.md',
      descricao: 'Cota residencial.' }
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready')
  end

  def construir
    described_class.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora Exemplo').call
  end

  describe 'auto nao muda' do
    it 'as listas do deploy sao as de antes, na mesma ordem' do
      expect(described_class::TOOLS_DO_ESPECIALISTA).to eq(do_especialista_de_auto)
      expect(described_class::TODAS_AS_TOOLS).to eq(do_agente)
    end

    it 'o especialista de auto nasce, e roda, sem a consulta de CEP' do
      agente = construir
      auto = agente.specialists.find_by!(slug: 'cotacao_auto')

      expect(auto.tool_slugs).to eq(do_especialista_de_auto)
      expect(auto.ferramentas_do_sistema).to eq(do_especialista_de_auto)
      expect(auto.tools.map(&:slug)).to eq(do_especialista_de_auto)
    end

    it 'com so o de auto, a consulta de CEP nem entra no catalogo do agente, e o principal nao a ve' do
      agente = construir

      expect(agente.native_tool_slugs).to eq(do_agente)
      expect(Autonomia::Agents::Tools::Registry.for_agent(agente).map(&:slug)).not_to include('consultar_cep')
      expect(Autonomia::Agents::Tools::Registry.find('consultar_cep')).to be_present
    end
  end

  describe 'residencial pronto para a fase 5' do
    it 'a entrada em ESPECIALISTAS basta: ele recebe a consulta de CEP, e nao a de placa' do
      stub_const("#{described_class}::ESPECIALISTAS", described_class::ESPECIALISTAS + [residencial])
      agente = construir
      do_residencial = agente.specialists.find_by!(slug: 'cotacao_residencial')

      expect(do_residencial.ferramentas_do_sistema).to eq(%w[consultar_cep cotar_seguro ver_resultado_da_cotacao])
      expect(agente.specialists.find_by!(slug: 'cotacao_auto').ferramentas_do_sistema).to eq(do_especialista_de_auto)
    end

    # O CATÁLOGO DO AGENTE SAI DA MESMA TABELA: com o de residencial, a consulta de CEP entra nele (senão o
    # especialista rodaria sem ela, ver `TOOLS_DO_PRINCIPAL`), uma vez só, e as comuns não se repetem.
    it 'as ferramentas de todos os especialistas incluem a consulta de CEP, sem repetir as comuns' do
      todas = described_class.ferramentas_dos_especialistas(described_class::ESPECIALISTAS + [residencial])

      expect(todas).to eq(%w[consultar_placa cotar_seguro ver_resultado_da_cotacao consultar_cep])
    end
  end
end
