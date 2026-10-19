require 'rails_helper'

# #1426 (tema 4b) — contradição resolvida: os dois materiais ficam e o agente recebe, junto dos trechos, o que vale em
# cada assunto. Sem escolha, fora da Fase 2 ou na Lia, o bloco de contexto fica byte a byte o de antes.
RSpec.describe Autonomia::Agents::Material::DecisoesDoMaterial do
  include_context 'with material do agente'

  let!(:site) { material('site', trechos: ['Sábado das 9h às 13h.']) }
  let!(:pdf) { material('horarios.pdf', trechos: ['Sábado das 9h às 12h.']) }
  let(:trechos) { Autonomia::Agents::KnowledgeEntry.where(source_id: [site.id, pdf.id]).to_a }

  def gravar(escolha)
    opcoes = [{ 'fonte' => site.id, 'diz' => 'das 9h às 13h' }, { 'fonte' => pdf.id, 'diz' => 'das 9h às 12h' }]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', {
                                                         'contradicoes' => [{ 'id' => 'c', 'assunto' => 'horário de sábado',
                                                                              'opcoes' => opcoes, 'escolha' => escolha }]
                                                       })
  end

  def contexto
    builder = Autonomia::Agents::PromptBuilder.new(agent: agent.reload, query: 'Abre sábado?', snippets: trechos)
    builder.input.find { |mensagem| mensagem[:content].first[:text].start_with?('[CONTEXTO]') }[:content].first[:text]
  end

  it 'com escolha: o contexto diz o que vale, depois dos trechos dos dois materiais' do
    gravar(pdf.id)

    expect(contexto).to include('Sábado das 9h às 13h.', 'Sábado das 9h às 12h.')
    expect(contexto).to end_with('QUANDO OS MATERIAIS DIVERGEM (escolha do dono, dado): use o que vale abaixo, mesmo que um trecho diga ' \
                                 "outra coisa.\n- Sobre horário de sábado: vale \"das 9h às 12h\".")
  end

  it 'material escolhido tirado ou reprovado: a escolha sai do contexto na hora', :aggregate_failures do
    gravar(pdf.id)
    pdf.update!(review_status: 'needs_resend')
    expect(contexto).not_to include('QUANDO OS MATERIAIS DIVERGEM')

    pdf.destroy!
    expect(contexto).not_to include('QUANDO OS MATERIAIS DIVERGEM')
  end

  it 'sem escolha, fora da Fase 2 ou na Lia: o contexto de antes', :aggregate_failures do
    gravar(nil)
    sem_decisao = contexto
    expect(sem_decisao).not_to include('QUANDO OS MATERIAIS DIVERGEM')

    gravar(pdf.id)
    Autonomia::Agents::Fase2.desligar!(account)
    expect(contexto).to eq(sem_decisao)

    Autonomia::Agents::Fase2.ligar!(account)
    agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
    expect(contexto).not_to include('QUANDO OS MATERIAIS DIVERGEM')
  end
end
