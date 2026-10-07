require 'rails_helper'

# A altura de linha que o mj-text aceita (#1099): px, % ou multiplicador. Em "1.2em" o número já é o multiplicador — a
# suíte de fidelidade (entrega D) achou o "1.2em" virando 19.2 vezes a letra, com espaços enormes entre as linhas.
RSpec.describe EmailCampaigns::Import::TextStyle do
  it 'keeps px and %, and turns em and rem into the multiplier they are' do
    expect(%w[22px 150% 1.5 1.2em 1.4rem normal].map { |value| described_class.line_height(value) })
      .to eq(['22px', '150%', '1.5', '1.2', '1.4', nil])
  end
end
