require 'rails_helper'

# #3101: o melhor horário de cada cliente — a próxima vez da hora dele (D5: até 24 h), o ponto dos motores de campanha
# e a escolha guardada na campanha.
RSpec.describe Autonomia::MelhorHorario do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  # Quinta-feira, 19/11/2026, 10h em São Paulo (13h UTC).
  let(:agora) { Time.utc(2026, 11, 19, 13, 0, 0) }
  let(:minuto) { contact.id % 60 }

  before { account.update_columns(settings: account.settings.to_h.merge('reporting_timezone' => 'America/Sao_Paulo')) } # rubocop:disable Rails/SkipsModelValidations

  def aprendido(hora, por_hora: Array.new(24, 0), para: contact)
    Autonomia::HorarioDeResposta.create!(account: account, contact: para, por_hora: por_hora, respostas: por_hora.sum,
                                         hora: hora, calculado_em: agora)
  end

  def horario_da_conta(inicio, fim)
    ritmo = { 'horario' => { 'inicio' => inicio, 'fim' => fim, 'dias_da_semana' => [0, 1, 2, 3, 4, 5, 6] } }
    account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => ritmo)) # rubocop:disable Rails/SkipsModelValidations
    account.reload
  end

  def proximo = described_class.proximo(account: account, contact: contact, a_partir_de: agora)

  describe '.proximo' do
    it 'marca a hora dele ainda hoje, num minuto fixo do contato' do
      aprendido(14)

      expect(proximo).to eq(Time.utc(2026, 11, 19, 17, minuto, 0))
    end

    it 'passa para amanhã quando a hora dele já passou hoje' do
      aprendido(8)

      expect(proximo).to eq(Time.utc(2026, 11, 20, 11, minuto, 0))
    end

    it 'manda agora quando já é a hora dele, e quando não há hora aprendida' do
      aprendido(10)
      expect(proximo).to be_nil

      Autonomia::HorarioDeResposta.delete_all
      aprendido(nil)
      expect(proximo).to be_nil

      expect(described_class.proximo(account: account, contact: create(:contact, account: account), a_partir_de: agora)).to be_nil
      expect(described_class.proximo(account: account, contact: nil, a_partir_de: agora)).to be_nil
    end

    it 'fora da janela, manda agora' do
      aprendido(14)

      expect(described_class.proximo(account: account, contact: contact, a_partir_de: agora, janela: 2.hours)).to be_nil
    end

    it 'com a hora fora do horário da conta, usa a hora permitida em que ele mais escreveu' do
      por_hora = Array.new(24, 0)
      por_hora[22] = 9
      por_hora[16] = 3
      por_hora[11] = 2
      aprendido(22, por_hora: por_hora)
      horario_da_conta(8, 20)

      expect(proximo).to eq(Time.utc(2026, 11, 19, 19, minuto, 0)) # 16h em São Paulo
    end
  end

  describe '.na_campanha' do
    let(:campanha) { create(:campaign, account: account) }

    # `ligado`: o ligado? da campanha, que o motor lê uma vez (Autonomia::MelhorHorario::DoMotor).
    def na_campanha(adiado_ate: nil, ligado: true)
      described_class.na_campanha(campanha: campanha, contact: contact, adiado_ate: adiado_ate, ligado: ligado, agora: agora)
    end

    before { aprendido(14) }

    it 'sem a opção ligada, fica só o Porteiro' do
      expect(na_campanha(ligado: false)).to be_nil
    end

    it 'com a opção ligada, espera a hora do contato só na primeira passada' do
      expect(na_campanha).to eq(Time.utc(2026, 11, 19, 17, minuto, 0))
      expect(na_campanha(adiado_ate: agora - 1.minute)).to be_nil
    end

    it 'não consulta a campanha: quem decide é o ligado que o motor passa' do
      allow(described_class).to receive(:ligado?)

      na_campanha

      expect(described_class).not_to have_received(:ligado?)
    end

    it 'fica com a espera mais longa entre o Porteiro e o melhor horário' do
      account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => { 'intervalo' => { 'horas' => 12 } })) # rubocop:disable Rails/SkipsModelValidations
      account.reload
      Autonomia::EnvioAoCliente.create!(account: account, contact: contact, origem: 'campanha_sms', enviado_em: agora - 1.hour)

      expect(na_campanha).to eq(agora + 11.hours + Autonomia::RitmoDeEnvio::Porteiro::FOLGA)
    end
  end

  describe '.guardar!' do
    let(:campanha) { create(:campaign, account: account) }

    it 'desligado sem linha não cria nada; ligado cria; desligar depois apaga a escolha' do
      described_class.guardar!(campanha, false)
      expect(Autonomia::CampanhaOpcoesDeEnvio.count).to eq(0)

      described_class.guardar!(campanha, true)
      expect(described_class.ligado?(campanha)).to be(true)
      expect(Autonomia::CampanhaOpcoesDeEnvio.last).to have_attributes(account_id: account.id, campanha: campanha)

      described_class.guardar!(campanha, false)
      expect(described_class.ligado?(campanha)).to be(false)
      expect(Autonomia::CampanhaOpcoesDeEnvio.count).to eq(1)
    end
  end

  describe '.conhecidos' do
    it 'conta só quem tem hora, entre os contatos dados' do
      outro = create(:contact, account: account)
      sem_hora = create(:contact, account: account)
      aprendido(14)
      aprendido(9, para: outro)
      aprendido(nil, para: sem_hora)

      expect(described_class.conhecidos(account, [contact.id, sem_hora.id])).to eq(1)
      expect(described_class.conhecidos(account, Contact.where(account: account).select(:id))).to eq(2)
    end
  end
end
