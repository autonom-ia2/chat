require 'rails_helper'

# Paridade da conversa (#3211), P3 na entrega em pedaços:
# - `conversa_entrega_inteira` (só vale com `conversa_em_fila`): depois do 1º pedaço postado, mensagem nova do cliente
#   não corta o resto. O 1º pedaço ainda confere o turno; a pessoa que assume ainda para a cadeia;
# - a cadeia é dona da marca da fala: renova a cada pedaço agendado e solta em toda saída (parada ou último pedaço).
# As opções nascem ligadas (menos na Lia): sem as chaves, a entrega é inteira. Com elas gravadas `false`, a cadeia para no
# 2º pedaço quando chega mensagem nova, como antes do #3211.
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:pedacos) do
    [{ 'text' => 'Primeira parte da resposta.', 'type' => 'text', 'delay_ms' => 900 },
     { 'text' => 'Segunda parte da resposta.', 'type' => 'text', 'delay_ms' => 900 }]
  end
  let!(:m1) { cliente_escreve('Oi, tudo bem?') }
  # Horário estritamente maior que o da m1: com horário empatado a ordem das duas mensagens não é garantida.
  let!(:m2) do
    travel 1.second
    cliente_escreve('Mais uma coisa.')
  end

  before do
    contrato!
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    clear_enqueued_jobs
    limpar_a_fala!
    # A mensagem nova grava a marca do debounce: o turno atual passa a ser o da m2, e a m1 já foi respondida.
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m2.id } })
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  # Igual ao spec da fila (reply_job_fila_da_fala_spec): liga as opções no config do agente.
  def liga!(*chaves)
    agente_da_porta.update!(config: agente_da_porta.config.to_h.merge(chaves.index_with(true)))
  end

  def pedaco!(indice)
    described_class.perform_now(conversation.id, vinculo_da_porta.id, m1.id, pedacos, indice, {})
  end

  def marca_da_fala = Redis::Alfred.get(fala.chave_ocupada(conversation.id))

  it 'com entrega inteira e fila: o 2º pedaço sai mesmo com mensagem nova' do
    liga!('conversa_entrega_inteira', 'conversa_em_fila')
    pedaco!(1)
    expect(respostas.pluck(:content)).to eq(['Segunda parte da resposta.'])
  end

  it 'sem as chaves (padrão ligado): o 2º pedaço sai mesmo com mensagem nova' do
    pedaco!(1)
    expect(respostas.pluck(:content)).to eq(['Segunda parte da resposta.'])
  end

  it 'a Lia sem as chaves: para no 2º pedaço, como antes' do
    agente_da_porta.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
    pedaco!(1)
    expect(respostas).to be_empty
  end

  it 'opção desligada: para no 2º pedaço, como antes' do
    desligar_paridade!(agente_da_porta, 'conversa_entrega_inteira')
    pedaco!(1)
    expect(respostas).to be_empty
  end

  it 'entrega inteira sem a fila: para (a dependência)' do
    desligar_paridade!(agente_da_porta, 'conversa_em_fila')
    liga!('conversa_entrega_inteira')
    pedaco!(1)
    expect(respostas).to be_empty
  end

  it 'o 1º pedaço ainda confere o turno' do
    liga!('conversa_entrega_inteira', 'conversa_em_fila')
    pedaco!(0)
    expect(respostas).to be_empty
  end

  it 'pessoa assumiu: para mesmo com a opção' do
    liga!('conversa_entrega_inteira', 'conversa_em_fila')
    conversation.update!(assignee: admin)
    pedaco!(1)
    expect(respostas).to be_empty
  end

  it 'cadeia que para solta a fala, mesmo com a opção desligada' do
    desligar_paridade!(agente_da_porta)
    fala.ocupar(conversation.id, m1.id)
    pedaco!(1) # para por turno_mudou (sem opção)
    expect(marca_da_fala).to be_nil
  end

  it 'último pedaço postado solta a fala' do
    liga!('conversa_entrega_inteira', 'conversa_em_fila')
    fala.ocupar(conversation.id, m1.id)
    pedaco!(1)
    expect(marca_da_fala).to be_nil
  end

  it 'a fala de outro turno não é solta por esta cadeia' do
    fala.ocupar(conversation.id, m2.id)
    pedaco!(1)
    expect(marca_da_fala).to eq(m2.id.to_s)
  end

  it 'pedaço intermediário renova a fala e não a solta' do
    liga!('conversa_em_fila')
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
    fala.ocupar(conversation.id, m1.id)
    pedaco!(0)
    expect(Redis::Alfred.ttl(fala.chave_ocupada(conversation.id)))
      .to be_between(1, Autonomia::Agents::Operate::TurnoEmCurso::TTL_DA_CADEIA.to_i)
  end

  it 'troca de dono no 1º pedaço solta a fala, refeito o turno ou não' do
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
    trocar_dono!(espelho_area)
    fala.ocupar(conversation.id, m1.id)
    pedaco!(0)
    expect(marca_da_fala).to be_nil
  end

  # Revisão final F4 (P1): a cadeia parou antes do 1º pedaço sem postar (aqui, mensagem nova): não houve fala, e o fim
  # previsto do turno some, para a rajada seguinte não esperar por nada. O fim de outro turno fica. #3235: o mesmo quando
  # a fala acaba depois (o último pedaço saiu, ou a cadeia parou num pedaço do meio).
  describe 'fim previsto da fala (P1)' do
    def fim_gravado = Redis::Alfred.get(fala.chave_do_fim(conversation.id))

    it 'parou no 1º pedaço sem postar: o fim deste turno some' do
      liga!('conversa_espera_a_fala')
      fala.prever_fim!(conversation.id, m1.id, 1800)
      pedaco!(0) # para por turno_mudou: o turno é o da m2
      expect(fim_gravado).to be_nil
    end

    it 'o fim de outro turno fica' do
      liga!('conversa_espera_a_fala')
      fala.prever_fim!(conversation.id, m2.id, 1800)
      pedaco!(0)
      expect(fim_gravado).to start_with("#{m2.id}:")
    end

    it 'o 1º pedaço saiu: o fim fica' do
      liga!('conversa_espera_a_fala')
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
      fala.prever_fim!(conversation.id, m1.id, 1800)
      pedaco!(0)
      expect(respostas.pluck(:content)).to eq(['Primeira parte da resposta.'])
      expect(fim_gravado).to start_with("#{m1.id}:")
    end

    # Pega: o fim ficar gravado depois que a fala acabou, e a rajada seguinte esperar pelo resto de uma previsão.
    it 'o último pedaço saiu: o fim deste turno some', :aggregate_failures do
      liga!('conversa_espera_a_fala')
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
      fala.prever_fim!(conversation.id, m1.id, 1800)
      pedaco!(1)
      expect(respostas.pluck(:content)).to eq(['Segunda parte da resposta.'])
      expect(fim_gravado).to be_nil
    end

    it 'o último pedaço saiu: o fim de outro turno fica' do
      liga!('conversa_espera_a_fala')
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
      fala.prever_fim!(conversation.id, m2.id, 1800)
      pedaco!(1)
      expect(fim_gravado).to start_with("#{m2.id}:")
    end

    # Pega: a parada do 2º pedaço em diante deixar o fim de pé (os pedaços que faltavam não vão sair).
    it 'parou no 2º pedaço (mensagem nova, sem a entrega inteira): o fim deste turno some', :aggregate_failures do
      desligar_paridade!(agente_da_porta, 'conversa_entrega_inteira')
      liga!('conversa_espera_a_fala')
      fala.prever_fim!(conversation.id, m1.id, 1800)
      pedaco!(1) # para por turno_mudou: o turno é o da m2
      expect(respostas).to be_empty
      expect(fim_gravado).to be_nil
    end

    it 'o retry de um pedaço que já entrou para a cadeia: o fim deste turno some' do
      liga!('conversa_espera_a_fala')
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
      pedaco!(0)
      fala.prever_fim!(conversation.id, m1.id, 1800)
      clear_enqueued_jobs
      pedaco!(0) # ja_postado
      expect(fim_gravado).to be_nil
    end

    it 'opção desligada: o fim não é tocado' do
      desligar_paridade!(agente_da_porta, 'conversa_espera_a_fala')
      fala.prever_fim!(conversation.id, m1.id, 1800)
      pedaco!(0)
      expect(fim_gravado).to start_with("#{m1.id}:")
    end
  end

  it 'exceção no pedaço propaga e solta a fala' do
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => m1.id } })
    fala.ocupar(conversation.id, m1.id)
    allow(Messages::MessageBuilder).to receive(:new).and_raise(StandardError, 'falha no envio')
    expect { pedaco!(0) }.to raise_error(StandardError, 'falha no envio')
    expect(marca_da_fala).to be_nil
  end
end
