require 'rails_helper'

# #1444: todo erro de render sobe como `Liquid::Error` — inclusive a exceção que não é do Liquid, que o
# `render!` relançaria crua e escaparia do tratamento da ferramenta.
RSpec.describe Autonomia::Agents::Tools::ModeloLiquid do
  let(:modelo) { described_class.ler('a {{ q }} b', recusa: 'x') }

  it 'raises the Liquid error of a missing variable' do
    expect { described_class.renderizar(modelo, {}, nil) }.to raise_error(Liquid::UndefinedVariable)
  end

  it 'turns an error that is not from Liquid into Liquid::InternalError' do
    filtro = ->(_valor) { raise ArgumentError, 'valor com segredo-123' }

    expect { described_class.renderizar(modelo, { 'q' => 'x' }, filtro) }
      .to raise_error(Liquid::InternalError) { |erro| expect(erro.message).not_to include('segredo-123') }
  end
end
