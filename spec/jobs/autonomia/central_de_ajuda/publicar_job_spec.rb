require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::PublicarJob do
  it 'publica pela conta configurada' do
    publicador = instance_double(Autonomia::CentralDeAjuda::Publicador)
    resultado = Autonomia::CentralDeAjuda::Publicador::Resultado.new(criados: 1, atualizados: 0, iguais: 0, arquivados: 0, falhas: [])
    allow(Autonomia::CentralDeAjuda::Publicador).to receive(:new).and_return(publicador)
    allow(publicador).to receive(:publicar!).and_return(resultado)

    described_class.perform_now

    expect(publicador).to have_received(:publicar!)
  end
end
