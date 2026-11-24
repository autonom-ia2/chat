require 'rails_helper'

# #3101 (D4): a hora em que o cliente costuma escrever, de qualquer mensagem dele nos últimos 180 dias, no fuso dele;
# com menos de 3 mensagens, sem hora.
RSpec.describe Autonomia::MelhorHorario::Aprender do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:contato) { conversa.contact }
  # Quinta-feira, 19/11/2026, 5h35 UTC (2h35 em São Paulo), a hora do cron.
  let(:agora) { Time.utc(2026, 11, 19, 5, 35, 0) }

  before { account.update_columns(settings: account.settings.to_h.merge('reporting_timezone' => 'America/Sao_Paulo')) } # rubocop:disable Rails/SkipsModelValidations

  def escreveu(quando, quem: contato, tipo: :incoming)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, sender: quem, message_type: tipo,
                     created_at: quando)
  end

  def horario(quem = contato) = Autonomia::HorarioDeResposta.find_by(contact: quem)

  describe '.hora_de' do
    it 'escolhe a hora com mais mensagens somando as vizinhas' do
      por_hora = Array.new(24, 0)
      por_hora[9] = 3
      por_hora[14] = 2
      por_hora[15] = 2

      expect(described_class.hora_de(por_hora)).to eq(14)
    end

    it 'sem o mínimo de mensagens, sem hora' do
      por_hora = Array.new(24, 0)
      por_hora[9] = 2

      expect(described_class.hora_de(por_hora)).to be_nil
    end

    it 'junta a meia-noite com a hora 23' do
      por_hora = Array.new(24, 0)
      por_hora[23] = 2
      por_hora[0] = 2
      por_hora[12] = 3

      expect(described_class.hora_de(por_hora)).to eq(0)
    end
  end

  describe '.rodar' do
    it 'aprende a hora no fuso do cliente de quem escreveu nas últimas 24 h', :aggregate_failures do
      escreveu(Time.utc(2026, 11, 18, 17, 10)) # 14h10 em São Paulo
      escreveu(Time.utc(2026, 11, 10, 17, 40))
      escreveu(Time.utc(2026, 10, 1, 18, 5)) # 15h05
      escreveu(Time.utc(2026, 1, 1, 12, 0)) # fora dos 180 dias

      described_class.rodar(agora: agora)

      registro = horario
      expect(registro.respostas).to eq(3)
      expect(registro.por_hora[14]).to eq(2)
      expect(registro.por_hora[15]).to eq(1)
      expect(registro.hora).to eq(14)
      expect(registro.calculado_em).to eq(agora)
    end

    it 'conta só o que o cliente escreveu e grava sem hora abaixo do mínimo' do
      escreveu(Time.utc(2026, 11, 18, 17, 10))
      escreveu(Time.utc(2026, 11, 18, 17, 20), quem: create(:user, account: account), tipo: :outgoing)

      described_class.rodar(agora: agora)

      expect(horario).to have_attributes(respostas: 1, hora: nil)
    end

    it 'recalcula por cima e deixa de fora quem não escreveu nas últimas 24 h' do
      quieto = create(:contact, account: account)
      escreveu(Time.utc(2026, 11, 10, 17, 10), quem: quieto)
      Autonomia::HorarioDeResposta.create!(account: account, contact: contato, por_hora: Array.new(24, 0), respostas: 0,
                                           calculado_em: agora - 1.day)
      3.times { escreveu(Time.utc(2026, 11, 18, 22, 0)) } # 19h

      described_class.rodar(agora: agora)

      expect(horario).to have_attributes(respostas: 3, hora: 19)
      expect(Autonomia::HorarioDeResposta.count).to eq(1)
      expect(horario(quieto)).to be_nil
    end
  end
end
