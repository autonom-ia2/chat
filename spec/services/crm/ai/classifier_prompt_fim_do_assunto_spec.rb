require 'rails_helper'

# #1926 — fim ambíguo ("já conseguimos fechar", sem dizer com quem) vira sugestão para uma pessoa confirmar, nunca
# movimento automático. A faixa escrita no prompt sai dos limiares do Evaluator.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:sugestao) { Crm::Ai::Config::SUGGESTION_THRESHOLD }
  let(:mover) { Crm::Ai::Config::AUTO_MOVE_THRESHOLD }

  # Pega: alguém mexer num limiar e o caso incerto passar a mover sozinho, ou a faixa ficar vazia.
  it 'a faixa do fim incerto é a de sugestão: entre os dois limiares do Evaluator', :aggregate_failures do
    expect(sugestao).to be < mover
    expect(described_class::FIM_DO_ASSUNTO).to include("pelo menos\n  #{sugestao} e abaixo de #{mover}")
    expect(described_class::TEXT).to include(described_class::FIM_DO_ASSUNTO)
  end
end
