require 'rails_helper'

# A conversa com o Guia sai 30 dias depois da última mensagem (#861): o texto pode
# ter dado pessoal de cliente, e passado o prazo ele não tem por que ficar.
RSpec.describe Autonomia::Guide::LimparConversasJob do
  let(:conta) { create(:account) }
  let(:pessoa) { create(:user, account: conta) }

  def conversa(parada_ha)
    registro = Autonomia::Guide::Conversa.create!(account: conta, user: pessoa, titulo: 'teste')
    Autonomia::Guide::Turno.abrir(conversa: registro, pedido_id: SecureRandom.uuid, pergunta: 'meu cliente Pedro', tela: 'home')
    registro.update_column(:updated_at, parada_ha.ago) # rubocop:disable Rails/SkipsModelValidations
    registro
  end

  it 'apaga a conversa parada há mais de 30 dias, com os turnos', :aggregate_failures do
    velha = conversa(31.days)
    recente = conversa(29.days)

    described_class.perform_now

    expect(Autonomia::Guide::Conversa.exists?(velha.id)).to be(false)
    expect(Autonomia::Guide::Turno.where(conversation_id: velha.id)).to be_empty
    expect(Autonomia::Guide::Conversa.exists?(recente.id)).to be(true)
  end

  it 'está na agenda diária' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(agenda.dig('autonomia_guide_limpar_conversas_job', 'class')).to eq(described_class.name)
  end
end
