require 'rails_helper'

# O ESPECIALISTA DE RESIDENCIAL SÓ ATENDE ONDE A CORRETORA COTA RESIDENCIAL (fase 5 do piloto, chat#323). Ele
# existe em todo agente de cotação, e a Lia só o enxerga quando a conexão pronta da conta tem o produto
# habilitado. As ferramentas dele continuam reservadas mesmo quando ele não atende: senão a consulta de CEP
# apareceria para a Lia justo na conta sem residencial. Auto não muda: atende sempre.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:agente) { described_class.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call }
  let(:residencial) { agente.specialists.find_by!(slug: 'cotacao_residencial') }
  let(:auto) { agente.specialists.find_by!(slug: 'cotacao_auto') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before { enable_test_encryption! }

  def conectar(produtos)
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready', capabilities: { 'products' => produtos })
  end

  def o_que_a_lia_ve
    answerer = Autonomia::Agents::Answerer.new(agent: agente, query: 'quero seguro da minha casa')
    Array(answerer.send(:answer_tools)).filter_map { |tool| tool[:name] || tool['name'] }
  end

  describe '.disponivel?' do
    it 'auto atende sempre, mesmo sem conexão' do
      expect(described_class.disponivel?(auto)).to be(true)
    end

    it 'residencial não atende sem conexão' do
      expect(described_class.disponivel?(residencial)).to be(false)
    end

    it 'residencial não atende quando a conexão não tem o ramo, ou o tem desligado' do
      conectar([{ 'product' => 'auto', 'enabled' => true }, { 'product' => 'residencial', 'enabled' => false }])

      expect(described_class.disponivel?(residencial)).to be(false)
    end

    it 'residencial atende quando a conexão tem o ramo habilitado' do
      conectar([{ 'product' => 'residencial', 'enabled' => true }])

      expect(described_class.disponivel?(residencial)).to be(true)
    end
  end

  describe 'o que a Lia vê' do
    it 'sem residencial na conta, só o especialista de auto, e sem a consulta de CEP' do
      conectar([{ 'product' => 'auto', 'enabled' => true }])

      nomes = o_que_a_lia_ve
      expect(nomes).to include(auto.function_name)
      expect(nomes).not_to include(residencial.function_name, 'consultar_cep', 'consultar_placa')
    end

    it 'com residencial na conta, os dois especialistas, e as consultas continuam deles' do
      conectar([{ 'product' => 'auto', 'enabled' => true }, { 'product' => 'residencial', 'enabled' => true }])

      nomes = o_que_a_lia_ve
      expect(nomes).to include(auto.function_name, residencial.function_name)
      expect(nomes).not_to include('consultar_cep', 'consultar_placa')
    end
  end
end
