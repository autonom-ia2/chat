require 'rails_helper'

# #3211/#3218: a fala na cadeia de pedaços. E-mail fica fora da paridade, com a chave gravada ou não.
RSpec.describe Autonomia::Agents::Operate::FalaDaCadeia do
  let(:agente) { Autonomia::Agents::Agent.new(config: { 'conversa_entrega_inteira' => true, 'conversa_em_fila' => true }) }

  it 'fora do e-mail, do 2º pedaço em diante a fala já começou' do
    expect(described_class.comecada?(agente, Inbox.new, 1)).to be(true)
  end

  # Pega: o job deixar de conferir o turno no e-mail (mensagem nova não cortaria os pedaços que faltam).
  it 'caixa de e-mail, mesmo com as chaves true gravadas: a fala não começou' do
    caixa_de_email = create(:channel_email).inbox

    expect(described_class.comecada?(agente, caixa_de_email, 1)).to be(false)
  end

  # #3235: a fala acabou (último pedaço ou parada em qualquer pedaço): só o fim deste turno sai, e só com a opção.
  describe '.acabou' do
    let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
    let(:conversa) { create(:conversation) }

    before { Redis::Alfred.delete(fala.chave_do_fim(conversa.id)) }
    after { Redis::Alfred.delete(fala.chave_do_fim(conversa.id)) }

    it 'apaga o fim deste turno' do
      fala.prever_fim!(conversa.id, 7, 30_000)
      described_class.acabou(conversa, agente, 7)
      expect(fala.fim_previsto(conversa.id)).to be_nil
    end

    it 'o fim de outro turno fica' do
      fala.prever_fim!(conversa.id, 8, 30_000)
      described_class.acabou(conversa, agente, 7)
      expect(fala.fim_previsto(conversa.id)).to be_present
    end

    it 'com a opção desligada, não toca no fim' do
      desligado = Autonomia::Agents::Agent.new(config: { 'conversa_espera_a_fala' => false })
      fala.prever_fim!(conversa.id, 7, 30_000)
      described_class.acabou(conversa, desligado, 7)
      expect(fala.fim_previsto(conversa.id)).to be_present
    end
  end
end
