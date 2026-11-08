require 'rails_helper'

# G29 (#2702): o `crm_cards.source` guarda o caminho exato que criou o card; a receita lê só o grupo.
RSpec.describe Autonomia::Automacao::OrigemDoCard do
  def origem(source) = described_class.de(Crm::Card.new(source: source))

  it 'lê o grupo de cada caminho que cria card', :aggregate_failures do
    expect(origem('meta_lead_form')).to eq('formulario_do_anuncio')
    expect(origem('Channel::Whatsapp')).to eq('conversa')
    expect(origem('Channel::Api')).to eq('conversa')
    expect(origem('autonomia_prospecting')).to eq('prospeccao')
    %w[public_booking contact_request public_link invite panel ai].each { |source| expect(origem(source)).to eq('agenda') }
  end

  it 'card à mão, pela API ou de origem nova lê "outra"', :aggregate_failures do
    expect(origem(nil)).to eq('outra')
    expect(origem('integracao_nova')).to eq('outra')
  end

  it 'só devolve opção da lista fechada, a mesma que o editor mostra' do
    expect(Autonomia::Automacao::Valores.fechado('card.origem')['opcoes']).to eq(described_class::OPCOES)
  end
end
