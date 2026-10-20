require 'rails_helper'

# #1975: o anúncio de passagem superado pelo próprio atendimento não conta, e o "reason" é obrigatório no "transferir".
# Decisão do Rodrigo (20/10): pedido que falhou com pessoa prometida e aviso de espera seguem de pé; esperar a
# resposta do cliente não pede pessoa por si só.
# O texto está no prefixo congelado: as duas variantes (com e sem agentes de IA) o levam.
RSpec.describe Crm::Ai::ClassifierPrompt do
  it 'leva as regras do anúncio superado, do pedido que falhou, da espera e do motivo nas duas variantes', :aggregate_failures do
    prefixos = [described_class::TEXT, described_class::TEXT_COM_AGENTES_IA]

    expect(prefixos).to all(include('o problema do cliente foi resolvido?').and(include('"reason" é OBRIGATÓRIO')))
    expect(prefixos).to all(include('pedido abandonado não é pedido resolvido').and(include('só avisou que aguarda o')))
    expect(prefixos).to all(include('uma pergunta não pede pessoa por si só').and(include('repasse TODOS os pedidos')))
    expect(prefixos).to all(be_frozen)
  end
end
