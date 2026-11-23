require 'rails_helper'

# #3117: desde que o Guia faz para quem não administra, a recusa por permissão é a mais comum. A pessoa lê a frase
# traduzida; o motivo cru da plataforma vai só para o modelo.
RSpec.describe Autonomia::Guide::RecusaDaPlataforma do
  def resultado(codigo, corpo)
    described_class.new('POST labels', Autonomia::Guide::ChamadaInterna::Resposta.new(codigo: codigo, corpo: corpo)).resultado
  end

  it 'na negativa da policy, diz que o perfil não tem permissão e guarda o motivo cru só para o modelo', :aggregate_failures do
    recusa = resultado(401, { error: 'You are not authorized to do this action' }.to_json)

    expect(recusa.ok).to be(false)
    expect(recusa.mensagem).to eq(I18n.t('autonomia.guide.not_permitted'))
    expect(recusa.dica).to include('You are not authorized')
  end

  it 'trata o 403 como o 401' do
    expect(resultado(403, '{}').mensagem).to eq(I18n.t('autonomia.guide.not_permitted'))
  end

  # O card de um funil que a pessoa não cuida se resolve liberando o funil, não o perfil.
  it 'no card de funil que a pessoa não cuida, diz como liberar o funil' do
    expect(resultado(401, { error: 'crm.access.card_funnel_required' }.to_json).mensagem)
      .to eq(I18n.t('autonomia.guide.card_funnel_required'))
  end

  it 'lê o motivo quando `error` vem como objeto, e nunca devolve um Hash' do
    recusa = resultado(422, { error: { code: 'invalid', message: 'Nome já existe' } }.to_json)

    expect(recusa.mensagem).to eq('Nome já existe')
  end

  it 'sem motivo legível, cai na frase traduzida de falha' do
    expect(resultado(500, '<html>erro</html>').mensagem).to eq(I18n.t('autonomia.guide.failed'))
  end
end
