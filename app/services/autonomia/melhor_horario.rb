# Melhor horário de cada cliente (#3101, F5 do épico #3095). A hora em que o cliente costuma escrever é aprendida por
# Autonomia::MelhorHorario::AprenderJob (Autonomia::HorarioDeResposta). Aqui:
# - `proximo`: a próxima vez em que essa hora acontece, dentro da janela (24 h, decisão D5), num minuto fixo por contato
#   para espalhar a carga. Na própria hora, ou sem hora conhecida, nil (manda agora). A hora fora do horário de envio
#   da conta vira a hora permitida em que ele mais escreveu; o dia da semana e o limite continuam com o Porteiro.
# - `na_campanha`: o ponto dos quatro motores de campanha, no lugar do Porteiro. Na primeira passada do destinatário
#   (ainda sem `adiado_ate`), com a opção ligada na campanha, espera o melhor horário; depois o Porteiro decide na saída,
#   como sempre. O destinatário volta pela varredura do ritmo de envio (Autonomia::RitmoDeEnvio::Varredura).
# - `conhecidos`: quantos destes contatos têm hora, para a revisão da campanha.
class Autonomia::MelhorHorario
  JANELA = 24.hours

  def self.proximo(account:, contact:, a_partir_de: Time.current, janela: JANELA)
    return nil if contact.nil?

    registro = Autonomia::HorarioDeResposta.find_by(account_id: account.id, contact_id: contact.id)
    hora = registro&.hora_permitida(Autonomia::RitmoDeEnvio::Config.da(account).horario)
    return nil if hora.nil?

    local = a_partir_de.in_time_zone(Crm::Timezone::Resolver.new(contact: contact, account: account).name_or_default)
    return nil if local.hour == hora

    vez = local.change(hour: hora, min: contact.id % 60)
    vez += 1.day if vez <= local
    vez <= a_partir_de + janela ? vez : nil
  end

  # nil: pode mandar agora. Time: o primeiro instante em que pode (o mais tarde entre o Porteiro e o melhor horário).
  def self.na_campanha(campanha:, contact:, adiado_ate:, agora: Time.current)
    ritmo = Autonomia::RitmoDeEnvio::Porteiro.quando(account: campanha.account, contact: contact, agora: agora)
    return ritmo unless adiado_ate.nil? && ligado?(campanha)

    [ritmo, proximo(account: campanha.account, contact: contact, a_partir_de: agora)].compact.max
  end

  def self.ligado?(campanha)
    Autonomia::CampanhaOpcoesDeEnvio.exists?(campanha: campanha, melhor_horario: true)
  end

  # Grava a escolha da criação da campanha. Desligado sem linha não cria nada.
  def self.guardar!(campanha, ligado)
    opcoes = Autonomia::CampanhaOpcoesDeEnvio.find_or_initialize_by(campanha: campanha)
    return if opcoes.new_record? && !ligado

    opcoes.update!(account_id: campanha.account_id, melhor_horario: ligado)
  end

  def self.conhecidos(account, contact_ids)
    Autonomia::HorarioDeResposta.where(account_id: account.id, contact_id: contact_ids).where.not(hora: nil).count
  end
end
