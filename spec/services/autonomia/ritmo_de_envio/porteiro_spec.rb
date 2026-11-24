require 'rails_helper'

# #3063, item 2: o ponto único do limite de mensagens por cliente e do horário de envio da conta.
RSpec.describe Autonomia::RitmoDeEnvio::Porteiro do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  # Quinta-feira, 19/11/2026, 10h em São Paulo (13h UTC).
  let(:agora) { Time.utc(2026, 11, 19, 13, 0, 0) }

  before { account.update_columns(settings: account.settings.to_h.merge('reporting_timezone' => 'America/Sao_Paulo')) } # rubocop:disable Rails/SkipsModelValidations

  def ritmo(limite: nil, horario: nil, intervalo: nil)
    guardado = { 'limite' => limite, 'intervalo' => intervalo, 'horario' => horario }
    account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => guardado)) # rubocop:disable Rails/SkipsModelValidations
    account.reload
  end

  def enviado(quando, para: contact)
    Autonomia::EnvioAoCliente.create!(account: account, contact: para, origem: 'campanha_whatsapp', enviado_em: quando)
  end

  def quando(contato = contact) = described_class.quando(account: account, contact: contato, agora: agora)

  it 'deixa mandar quando a conta não escolheu nada (o padrão)' do
    3.times { enviado(agora - 1.hour) }

    expect(quando).to be_nil
  end

  describe 'limite por cliente' do
    before { ritmo(limite: { 'mensagens' => 2, 'dias' => 7 }) }

    it 'deixa mandar enquanto o cliente não chegou ao limite do período' do
      enviado(agora - 1.day)
      enviado(agora - 8.days)

      expect(quando).to be_nil
    end

    it 'adia até a mais velha das que contam sair do período' do
      enviado(agora - 2.days)
      enviado(agora - 1.day)

      expect(quando).to eq(agora - 2.days + 7.days + described_class::FOLGA)
    end

    it 'conta só as mensagens deste cliente e desta conta' do
      outro = create(:contact, account: account)
      2.times { enviado(agora - 1.hour, para: outro) }

      expect(quando).to be_nil
    end

    it 'não limita quem não tem ficha (e-mail de planilha)' do
      expect(quando(nil)).to be_nil
    end
  end

  describe 'horário de envio' do
    before { ritmo(horario: { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [1, 2, 3, 4, 5] }) }

    it 'deixa mandar dentro do horário' do
      expect(quando).to be_nil
    end

    it 'adia para o começo do próximo dia permitido, no fuso do cliente' do
      noite = Time.utc(2026, 11, 21, 0, 30, 0) # sexta, 21h30 em São Paulo

      ate = described_class.quando(account: account, contact: contact, agora: noite)

      expect(ate).to eq(Time.utc(2026, 11, 23, 11, 0, 0)) # segunda, 8h em São Paulo
    end

    it 'junta o limite e o horário: a vaga do limite cai fora do horário e vai para a abertura seguinte' do
      ritmo(limite: { 'mensagens' => 1, 'dias' => 1 }, horario: { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [0, 1, 2, 3, 4, 5, 6] })
      enviado(Time.utc(2026, 11, 18, 23, 30, 0)) # quarta, 20h30 em São Paulo

      expect(quando).to eq(Time.utc(2026, 11, 20, 11, 0, 0)) # vaga às 20h31 de quinta, sai sexta 8h
    end
  end

  describe 'intervalo entre mensagens (#3101)' do
    before { ritmo(intervalo: { 'horas' => 4 }) }

    it 'deixa mandar quando a última mensagem saiu há mais tempo que o intervalo' do
      enviado(agora - 5.hours)

      expect(quando).to be_nil
    end

    it 'adia até a última mensagem mais o intervalo' do
      enviado(agora - 3.days)
      enviado(agora - 1.hour)

      expect(quando).to eq(agora - 1.hour + 4.hours + described_class::FOLGA)
    end

    it 'deixa mandar para quem nunca recebeu e para quem não tem ficha' do
      expect(quando).to be_nil
      expect(quando(nil)).to be_nil
    end

    it 'fica com a vaga mais distante entre o limite e o intervalo' do
      ritmo(limite: { 'mensagens' => 2, 'dias' => 1 }, intervalo: { 'horas' => 4 })
      enviado(agora - 20.hours)
      enviado(agora - 1.hour)

      expect(quando).to eq(agora - 20.hours + 1.day + described_class::FOLGA)
    end

    it 'joga a vaga do intervalo para a abertura seguinte do horário' do
      ritmo(intervalo: { 'horas' => 12 }, horario: { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [0, 1, 2, 3, 4, 5, 6] })
      enviado(agora - 1.hour) # 9h em São Paulo; a vaga às 21h01 cai fora do horário

      expect(quando).to eq(Time.utc(2026, 11, 20, 11, 0, 0)) # sexta, 8h em São Paulo
    end
  end

  describe '.contar!' do
    it 'grava a mensagem que saiu' do
      expect { described_class.contar!(account: account, contact_id: contact.id, origem: 'automacao_email', agora: agora) }
        .to change(Autonomia::EnvioAoCliente, :count).by(1)
    end

    it 'não grava sem cliente e não quebra o envio quando a gravação falha' do
      expect(described_class.contar!(account: account, contact_id: nil, origem: 'campanha_email')).to be_nil
      expect(described_class.contar!(account: account, contact_id: contact.id, origem: 'outra')).to be_nil
      expect(Autonomia::EnvioAoCliente.count).to eq(0)
    end
  end
end
