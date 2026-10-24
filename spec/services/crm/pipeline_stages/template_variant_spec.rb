# frozen_string_literal: true

require 'rails_helper'

# #1548 (passo 2): a variante do modelo de funil por tipo de conta troca a lista de categorias das etapas. Saúde e
# benefícios: no Atendimento, a E3 ("Esperando a operadora") é andamento e não pausa o prazo.
RSpec.describe Crm::PipelineStages::TemplateVariant do
  let(:nicho) { Autonomia::Agents::Nicho }

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    example.run
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
  end

  def conta(perfil)
    create(:account, internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil })
  end

  def ligado(&)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', &)
  end

  it 'saúde com o interruptor ligado: E3 do Atendimento é andamento' do
    ligado do
      account = conta('saude_beneficios')
      categorias = (1..4).map { |posicao| described_class.category_for(account: account, template: 'ATENDIMENTO', position: posicao) }

      expect(categorias).to eq(%w[novo andamento andamento resolvido])
    end
  end

  it 'saúde com o interruptor desligado: sem variante' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(described_class.category_for(account: conta('saude_beneficios'), template: 'ATENDIMENTO', position: 3)).to be_nil
    end
  end

  it 'os outros tipos e a conta geral não têm variante' do
    ligado do
      contas = %w[corretora seguradora insurtech].map { |perfil| conta(perfil) } + [create(:account)]

      expect(contas.map { |account| described_class.category_for(account: account, template: 'ATENDIMENTO', position: 3) }).to all(be_nil)
    end
  end

  it 'toda categoria da variante é uma categoria conhecida da etapa' do
    valores = described_class::CATEGORIES.values.flat_map(&:values).flatten

    expect(valores).to all(be_in(Crm::PipelineStage::CATEGORIES))
  end

  it 'em saúde, só o Atendimento e a Carteira mudam; posição inválida não acha nada' do
    ligado do
      account = conta('saude_beneficios')

      outros = %w[POS_VENDA COBRANCA AGENDAMENTOS VENDAS]
      expect(outros.map { |template| described_class.category_for(account: account, template: template, position: 3) }).to all(be_nil)
      expect([0, 5, nil, 'x'].map { |posicao| described_class.category_for(account: account, template: 'ATENDIMENTO', position: posicao) })
        .to all(be_nil)
      # #2083: na Carteira, o aniversário do contrato (E3) é andamento, não pausa o prazo.
      expect((1..4).map { |posicao| described_class.category_for(account: account, template: 'CARTEIRA', position: posicao) })
        .to eq(%w[novo andamento andamento resolvido])
    end
  end
end
