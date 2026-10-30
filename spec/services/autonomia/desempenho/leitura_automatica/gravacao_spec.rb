require 'rails_helper'

# Gravação da leitura de uma conversa (#2301): o horário 'MM-DD HH:MM' volta sem ano, e a conversa pode atravessar o
# ano. Conversa inventada.
RSpec.describe Autonomia::Desempenho::LeituraAutomatica::Gravacao do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:ficha) { ficha_da_loja!(account, sujeito_id: 7) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:esquema) { Autonomia::Desempenho::LeituraAutomatica::Esquema.new(ficha) }
  let(:mensagens) do
    [Time.utc(2025, 12, 31, 23, 58), Time.utc(2026, 1, 1, 0, 2), Time.utc(2026, 12, 31, 23, 58), Time.utc(2026, 12, 31, 23, 59)].map do |quando|
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'oi', created_at: quando)
    end
  end

  def procura(inicio, fim)
    { 'inicio' => inicio, 'fim' => fim, 'quem' => 'cliente', 'pedido' => 'comprar', 'tema' => 'entrega', 'marcos' => [],
      'resultado' => 'comprou', 'motivos' => [], 'perda_evitavel' => false, 'por_que' => '', 'qualidade' => 'acertou',
      'regras' => [], 'teve_pessoa' => false, 'precisava_pessoa' => false, 'origem' => 'desconhecida', 'resumo' => 'Prazo.' }
  end

  def gravar(*procuras)
    described_class.new(ficha: ficha, conversa: conversa, mensagens: mensagens, esquema: esquema).gravar!(procuras)
    Autonomia::Desempenho::Procura.where(conversation_id: conversa.id).order(:ordem).pluck(:inicio_em, :fim_em)
  end

  it 'na conversa que atravessa o ano, escolhe o par de mensagens mais perto com início antes do fim' do
    gravadas = gravar(procura('12-31 23:58', '01-01 00:02'), procura('12-31 23:58', '12-31 23:59'))

    expect(gravadas).to eq([[Time.utc(2025, 12, 31, 23, 58), Time.utc(2026, 1, 1, 0, 2)],
                            [Time.utc(2026, 12, 31, 23, 58), Time.utc(2026, 12, 31, 23, 59)]])
  end

  describe 'a marca de teste' do
    def procura_de_teste!(teste:)
      Autonomia::Desempenho::Procura.create!(account: account, sujeito_type: 'robo', sujeito_id: 7, conversation: conversa, ordem: 1,
                                             inicio_em: mensagens.first.created_at, fim_em: mensagens.first.created_at, versao_ficha: 1,
                                             lote: 'carga', teste: teste)
    end

    def testes_gravados
      Autonomia::Desempenho::Procura.where(conversation_id: conversa.id).order(:ordem).pluck(:lote, :teste)
    end

    it 'sem com_teste na ficha, a conversa que era de teste continua de teste depois de relida' do
      procura_de_teste!(teste: true)

      gravar(procura('12-31 23:58', '12-31 23:59'))

      expect(testes_gravados).to eq([['leitura_automatica', true]])
    end

    it 'sem com_teste na ficha, a conversa que não era de teste continua fora do teste' do
      procura_de_teste!(teste: false)

      gravar(procura('12-31 23:58', '12-31 23:59'))

      expect(testes_gravados).to eq([['leitura_automatica', false]])
    end

    it 'com com_teste na ficha, vale o que a leitura disse' do
      ficha.update!(configuracao: ficha.configuracao.merge('leitura' => { 'com_teste' => true }))
      procura_de_teste!(teste: true)

      gravar(procura('12-31 23:58', '12-31 23:59').merge('teste' => false))

      expect(testes_gravados).to eq([['leitura_automatica', false]])
    end
  end

  it 'recusa o horário que não é de nenhuma mensagem' do
    expect { gravar(procura('12-30 10:00', '12-31 23:59')) }.to raise_error(Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida)
    expect(Autonomia::Desempenho::Leitura.where(conversation_id: conversa.id)).to be_empty
  end
end
