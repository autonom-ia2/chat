require 'rails_helper'

# chat#1489: a linha de contexto interno sai da resposta só onde aparece exata; o resto do texto fica como veio.
describe Autonomia::Agents::Operate::RecoveredHeaderNote do
  let(:image_note) { described_class::NOTES['image'] }
  let(:media_note) { described_class::NOTES['media'] }

  def result(reply)
    Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.8, handoff: { should: false, reason: nil },
                                        used_knowledge: [{ id: 1 }], answered_from_knowledge: true, raw_reply: reply)
  end

  it 'a linha diz que é contexto interno' do
    expect(image_note).to eq('[contexto interno, não repetir ao cliente: a mensagem tinha uma imagem que não foi lida]')
    expect(media_note).to eq('[contexto interno, não repetir ao cliente: a mensagem tinha um arquivo que não foi lido]')
  end

  it 'tira a linha no meio da frase e junta o espaço duplo que sobra' do
    cleaned = described_class.without_notes(result("Recebi sua fatura #{image_note} e vou conferir."))

    expect(cleaned.reply).to eq('Recebi sua fatura e vou conferir.')
    expect(cleaned).to have_attributes(confidence: 0.8, used_knowledge: [{ id: 1 }], answered_from_knowledge: true)
  end

  it 'linha sozinha some, as outras linhas ficam intactas (inclusive espaços delas)' do
    reply = "Olá!\n#{media_note}\nValor:  R$ 10"

    expect(described_class.without_notes(result(reply)).reply).to eq("Olá!\nValor:  R$ 10")
  end

  it 'texto parecido, mas não a linha exata, não é tocado' do
    reply = 'A mensagem tinha uma imagem que não foi lida, pode reenviar?'
    same = result(reply)

    expect(described_class.without_notes(same)).to be(same)
  end

  it 'resposta só com a linha: vazia, e o motivo do silêncio é próprio' do
    answered = result(image_note)
    delivered = described_class.without_notes(answered)

    expect(delivered.reply).to eq('')
    expect(described_class.silence_reason(answered, delivered)).to eq('so_contexto_interno')
  end

  it 'resposta vazia ou sem a linha não ganha o motivo próprio' do
    expect(described_class.silence_reason(result(''), result(''))).to be_nil
    expect(described_class.silence_reason(nil, nil)).to be_nil
    ok = result('Oi')
    expect(described_class.silence_reason(ok, described_class.without_notes(ok))).to be_nil
  end
end
