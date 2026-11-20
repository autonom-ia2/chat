# O que a conta escolheu (#3063, item 2), em accounts.settings['ritmo_de_envio']:
#   { 'limite'  => { 'mensagens' => 3, 'dias' => 7 } | nil,
#     'horario' => { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [1, 2, 3, 4, 5] } | nil }
# Sem a chave (o padrão), nada muda: sem limite e a qualquer hora, até alguém escolher. `fim` é a hora em que para de
# mandar (20 = até 19h59). Dias da semana: 0 = domingo, como Date#wday.
class Autonomia::RitmoDeEnvio::Config
  CHAVE = 'ritmo_de_envio'.freeze
  MENSAGENS = (1..10)
  DIAS = [1, 7, 15, 30].freeze
  INICIOS = (0..22)
  FINS = (1..23)
  DIAS_DA_SEMANA = (0..6)

  Invalida = Class.new(StandardError)

  attr_reader :limite, :horario

  def self.da(account)
    new(account.settings.to_h[CHAVE])
  end

  # O que veio da tela vira o hash guardado, ou Invalida com o campo errado.
  def self.normalizar(valores)
    valores = valores.to_h.deep_stringify_keys
    { 'limite' => limite_de(valores['limite']), 'horario' => horario_de(valores['horario']) }
  end

  def self.limite_de(limite)
    return nil if limite.blank?

    mensagens = Integer(limite['mensagens'], exception: false)
    dias = Integer(limite['dias'], exception: false)
    raise Invalida, 'limite.mensagens' unless MENSAGENS.cover?(mensagens)
    raise Invalida, 'limite.dias' unless DIAS.include?(dias)

    { 'mensagens' => mensagens, 'dias' => dias }
  end

  def self.horario_de(horario)
    return nil if horario.blank?

    inicio = Integer(horario['inicio'], exception: false)
    fim = Integer(horario['fim'], exception: false)
    raise Invalida, 'horario.inicio' unless INICIOS.cover?(inicio)
    raise Invalida, 'horario.fim' unless FINS.cover?(fim) && fim > inicio

    { 'inicio' => inicio, 'fim' => fim, 'dias_da_semana' => dias_da_semana_de(horario['dias_da_semana']) }
  end

  def self.dias_da_semana_de(dias)
    dias = Array(dias).map { |dia| Integer(dia, exception: false) }.uniq.sort
    raise Invalida, 'horario.dias_da_semana' if dias.empty? || !dias.all? { |dia| DIAS_DA_SEMANA.cover?(dia) }

    dias
  end

  def initialize(guardado)
    guardado = guardado.is_a?(Hash) ? guardado : {}
    @limite = guardado['limite'].presence
    @horario = guardado['horario'].presence
  end

  def to_h
    { 'limite' => limite, 'horario' => horario }
  end

  # O próximo instante em que o horário deixa mandar, a partir de `instante`, no fuso dado. Sem horário, o próprio
  # instante. Mesma regra do retorno automático do CRM (Crm::FollowUps::AllowedSchedule): [inicio, fim).
  def proximo_horario(instante, fuso)
    return instante if horario.nil?

    Crm::FollowUps::AllowedSchedule.new(
      config: { quiet_hours: { start: horario['inicio'], end: horario['fim'] }, allowed_days: horario['dias_da_semana'] },
      timezone: fuso
    ).next_at(instante)
  end
end
