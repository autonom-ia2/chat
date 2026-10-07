require 'rails_helper'

# A altura de linha que o mj-text aceita (#1099): px, % ou multiplicador. Em "1.2em" o número já é o multiplicador — a
# suíte de fidelidade (entrega D) achou o "1.2em" virando 19.2 vezes a letra, com espaços enormes entre as linhas. Já
# "rem" é da raiz da página (16 px), não da letra: "1.5rem" são 24 px em qualquer tamanho de letra.
RSpec.describe EmailCampaigns::Import::TextStyle do
  it 'keeps px and %, turns em into the multiplier it is and rem into px of the page root' do
    expect(%w[22px 150% 1.5 1.2em 1.4rem 1.5REM normal].map { |value| described_class.line_height(value) })
      .to eq(['22px', '150%', '1.5', '1.2', '22px', '24px', nil])
  end
end
