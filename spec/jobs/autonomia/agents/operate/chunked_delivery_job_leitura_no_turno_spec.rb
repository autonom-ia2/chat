require 'rails_helper'

# #3225 na entrega em pedaços: a cadeia do turno que leu a mensagem nova no meio (as lidas no meta) não é superada por
# ela; o 1º pedaço grava as lidas, na mesma transação do post; quando as cadeias de A (que leu B) e de B chegam ao 1º
# pedaço, só uma posta, qualquer que seja a ordem; e o `replied` leva as lidas e as voltas.
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:chave) { Autonomia::Agents::Operate::LeituraNoTurno::CHAVE }
  let(:pedacos) do
    [{ 'text' => 'Primeira parte da resposta.', 'type' => 'text', 'delay_ms' => 900 },
     { 'text' => 'Segunda parte da resposta.', 'type' => 'text', 'delay_ms' => 900 }]
  end
  let!(:primeira) { cliente_escreve('França, 15 a 20/01, 40 anos') }
  # Horário estritamente maior que o da primeira: com horário empatado a ordem das duas não é garantida.
  let!(:segunda) do
    travel 1.second
    cliente_escreve('Conhece lá?')
  end
  let(:meta_que_leu) { { 'lidas_no_turno' => [segunda.id], 'voltas' => 1 } }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    contrato!
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    clear_enqueued_jobs
    limpar_a_fala!
    # A mensagem B gravou a marca do debounce: o turno atual é o dela.
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => segunda.id } })
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  def pedaco!(mensagem, indice, meta = {})
    described_class.perform_now(conversation.id, vinculo_da_porta.id, mensagem.id, pedacos, indice, meta)
  end

  def respondidas
    respostas.order(:id).map { |resposta| resposta.content_attributes['autonomia_reply_to_message_id'] }
  end

  it 'a cadeia de A, que leu B: o 1º pedaço sai e grava B como lida', :aggregate_failures do
    pedaco!(primeira, 0, meta_que_leu)

    expect(respondidas).to eq([primeira.id])
    expect(respostas.sole.content_attributes[chave]).to eq([segunda.id])
  end

  it 'sem as lidas no meta: o 1º pedaço de A para, como antes' do
    pedaco!(primeira, 0)
    expect(respostas).to be_empty
  end

  it 'o 2º pedaço não grava as lidas de novo' do
    pedaco!(primeira, 0, meta_que_leu)
    pedaco!(primeira, 1, meta_que_leu)

    expect(respostas.order(:id).map { |resposta| resposta.content_attributes.key?(chave) }).to eq([true, false])
  end

  it 'o replied (registrado no 1º pedaço) leva as lidas e as voltas' do
    pedaco!(primeira, 0, meta_que_leu)

    evento = Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id, event_type: :replied).sole
    expect(evento.metadata).to include('lidas_no_turno' => [segunda.id], 'voltas' => 1)
  end

  describe 'A e B em pedaços ao mesmo tempo: só uma posta' do
    it 'A chega primeiro: o 1º pedaço de B para (respondida junto)', :aggregate_failures do
      linhas = linhas_do_log do
        pedaco!(primeira, 0, meta_que_leu)
        pedaco!(segunda, 0)
      end

      expect(respondidas).to eq([primeira.id])
      expect(linhas.join).not_to include('leitura_no_silencio')
    end

    it 'B chega primeiro: o 1º pedaço de A para (B já tem resposta própria), e registra', :aggregate_failures do
      linhas = linhas_do_log do
        pedaco!(segunda, 0)
        pedaco!(primeira, 0, meta_que_leu)
      end

      expect(respondidas).to eq([segunda.id])
      expect(linhas.join).to include('leitura_no_silencio', "msg=#{primeira.id}", 'motivo=turno_mudou', 'pedaco=0')
    end
  end
end
