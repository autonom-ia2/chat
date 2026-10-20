require 'rails_helper'

# #1975: o anúncio de passagem superado pelo próprio atendimento não conta, e o "reason" é obrigatório no "transferir".
# O texto está no prefixo congelado: as duas variantes (com e sem agentes de IA) o levam.
RSpec.describe Crm::Ai::ClassifierPrompt do
  it 'leva a regra do anúncio superado e do motivo obrigatório nas duas variantes do prefixo', :aggregate_failures do
    prefixos = [described_class::TEXT, described_class::TEXT_COM_AGENTES_IA]

    expect(prefixos).to all(include('o problema do cliente foi resolvido?').and(include('"reason" é OBRIGATÓRIO')))
    expect(prefixos).to all(be_frozen)
  end
end
