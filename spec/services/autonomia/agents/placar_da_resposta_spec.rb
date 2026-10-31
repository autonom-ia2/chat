require 'rails_helper'

RSpec.describe Autonomia::Agents::PlacarDaResposta do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:pergunta_class) { Autonomia::Agents::PlacarDaBase::Pergunta }
  let(:vidro) { pergunta_class.new(texto: 'cobre o vidro?', ancoras: ['para-brisa e vigias'], fora: false, esperado: 'Cobre para-brisa.') }
  let(:reboque) { pergunta_class.new(texto: 'tem reboque?', ancoras: ['guincho até 200 km'], fora: false) }
  let(:vida) { pergunta_class.new(texto: 'fazem seguro de vida?', ancoras: [], fora: true) }
  let(:respostas) do
    {
      'cobre o vidro?' => resultado('Sim, cobre o para-brisa.', usados: ['Cobertura de VIDROS: para-brisa e vigias.']),
      'tem reboque?' => resultado('Não sei.', handoff: true),
      'fazem seguro de vida?' => resultado('Não tenho essa informação.')
    }
  end
  let(:juiz) { instance_double(Autonomia::Agents::Material::JuizDoAutoteste) }
  let(:itens_julgados) { [] }

  def resultado(reply, usados: [], handoff: false)
    Autonomia::Agents::AnswerResult.new(
      reply: reply, confidence: 'high', handoff: { should: handoff, reason: nil },
      used_knowledge: usados.each_with_index.map { |content, id| { id: id, content: content, source: 'pdf' } }
    )
  end

  def medir(*perguntas, vereditos:)
    allow(juiz).to receive(:julgar) do |itens|
      itens_julgados.concat(itens)
      vereditos
    end
    described_class.new(agent: agent, perguntas: perguntas, juiz: juiz, responder: ->(texto) { respostas.fetch(texto) }).medir
  end

  it 'scores correct answers among the answerable and correct refusals among the out-of-base' do
    placar = medir(vidro, reboque, vida, vereditos: %w[certo errado recusou])

    expect(placar).to include(perguntas: 3, respondiveis: 2, fora: 1, acerto: 0.5, recusa_correta: 1.0, julgado: true)
  end

  it 'counts where the answer came from by the passages the model says it used' do
    placar = medir(vidro, reboque, vereditos: %w[certo errado])

    expect(placar[:de_onde_veio]).to eq(0.5)
    expect(placar[:itens].map { |item| item[:usou_a_ancora] }).to eq([true, false])
  end

  it 'gives the judge the expected answer, falling back to the anchors, and the handoff' do
    medir(vidro, reboque, vida, vereditos: %w[certo errado recusou])
    esperados = [
      { 'origem' => 'material', 'pergunta' => 'cobre o vidro?', 'esperado' => 'Cobre para-brisa.',
        'resposta' => 'Sim, cobre o para-brisa.', 'equipe' => false },
      { 'origem' => 'material', 'pergunta' => 'tem reboque?', 'esperado' => 'guincho até 200 km',
        'resposta' => 'Não sei.', 'equipe' => true },
      { 'origem' => 'fora', 'pergunta' => 'fazem seguro de vida?', 'esperado' => nil,
        'resposta' => 'Não tenho essa informação.', 'equipe' => false }
    ]

    expect(itens_julgados).to eq(esperados)
  end

  it 'reports the round as not judged when the judge fails, never as all wrong' do
    placar = medir(vidro, vida, vereditos: nil)

    expect(placar).to include(julgado: false, acerto: nil, recusa_correta: nil)
    expect(placar[:itens].map { |item| item[:veredito] }).to eq([nil, nil])
  end

  it 'keeps question and answer text out of the summary' do
    placar = medir(vidro, vereditos: %w[certo])
    resumo = Autonomia::Agents::PlacarDaBase.resumo(placar)

    expect(resumo.to_json).not_to include('cobre o vidro', 'para-brisa')
  end
end
