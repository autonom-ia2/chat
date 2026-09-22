require 'rails_helper'

# A CONSULTA QUE ANTECEDE A COTAÇÃO É DO RAMO (autonomia-adapters#87). `consultar_cep` vai só ao especialista de
# ramo com imóvel, e a placa só ao de auto. Com o de residencial em `ESPECIALISTAS` (fase 5, chat#323), prova-se:
#   auto não muda: o especialista de auto tem as ferramentas de antes de #87, literais, na mesma ordem;
#   residencial recebe a consulta de CEP e não a de placa;
#   o catálogo do agente passa a ter a consulta de CEP (senão o especialista rodaria sem ela), uma vez só.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  # As listas escritas por extenso: comparar com a própria constante não provaria nada.
  let(:do_especialista_de_auto) { %w[consultar_placa cotar_seguro ver_resultado_da_cotacao] }
  let(:do_especialista_de_residencial) { %w[consultar_cep cotar_seguro ver_resultado_da_cotacao] }
  let(:do_agente) do
    %w[consultar_produtos_cotacao consultar_condicoes_gerais enviar_proposta_da_seguradora
       consultar_placa cotar_seguro ver_resultado_da_cotacao consultar_cep]
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
    it 'o especialista de auto nasce, e roda, sem a consulta de CEP' do
      agente = construir
      auto = agente.specialists.find_by!(slug: 'cotacao_auto')

      expect(auto.tool_slugs).to eq(do_especialista_de_auto)
      expect(auto.ferramentas_do_sistema).to eq(do_especialista_de_auto)
      expect(auto.tools.map(&:slug)).to eq(do_especialista_de_auto)
    end
  end

  describe 'residencial' do
    it 'nasce com a consulta de CEP, e nao a de placa' do
      do_residencial = construir.specialists.find_by!(slug: 'cotacao_residencial')

      expect(do_residencial.tool_slugs).to eq(do_especialista_de_residencial)
      expect(do_residencial.ferramentas_do_sistema).to eq(do_especialista_de_residencial)
    end

    it 'o agente nasce com a consulta de CEP, uma vez so, e as comuns nao se repetem' do
      expect(described_class::TODAS_AS_TOOLS).to eq(do_agente)
      expect(construir.native_tool_slugs).to eq(do_agente)
    end

    # O CATÁLOGO DO TURNO SEGUE A CONTA (`ferramentas_mantidas`): sem residencial na conexão, a consulta de CEP
    # fica fora, e com ele entra, para o especialista a encontrar.
    it 'o catalogo do turno so tem a consulta de CEP onde a corretora cota residencial' do
      agente = construir
      expect(Autonomia::Agents::Tools::Registry.for_agent(agente).map(&:slug)).not_to include('consultar_cep')

      Autonomia::Insurance::Config.liberar_ramo!(account, 'residencial')
      Autonomia::Insurance::Connection.for_account(account).first
                                      .update!(capabilities: { 'products' => [{ 'product' => 'residencial', 'enabled' => true }] })
      expect(Autonomia::Agents::Tools::Registry.for_agent(agente.reload).map(&:slug)).to include('consultar_cep')
      expect(agente.specialists.find_by!(slug: 'cotacao_residencial').tools.map(&:slug))
        .to eq(do_especialista_de_residencial)
    end
  end
end
