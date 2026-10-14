# Falha geral ou IP ruim? (#1516) Se a Webshare inteira cair, o WhatsApp Web cair ou o motor reiniciar, todas as
# sessões saem de WORKING ao mesmo tempo — tratar cada uma como "IP instável" queimaria o plano inteiro em quarentena e
# reiniciaria dezenas de números à toa. É falha geral, numa rodada, quando:
# - mais de MAX_SHARE dos IPs em uso de um plano têm sessão fora de WORKING (por IP, não por sessão: um IP ruim leva
#   até 3 números da mesma conta, e isso ainda é um IP ruim), com pelo menos MIN_OFF IPs; ou
# - as sessões SEM proxy do mesmo motor (linha de base do WhatsApp e do motor) também estão caindo: mais de MAX_SHARE
#   fora, com pelo menos MIN_OFF sessões — aí vale para todos os planos.
# Fora de WORKING = STARTING ou FAILED (SCAN_QR_CODE é aparelho; STOPPED é desligado de propósito).
class WhatsappProxy::Outage
  MAX_SHARE = 0.3
  MIN_OFF = 2

  # engine_sessions: o GET /api/sessions?all=true do motor; assignments: as atribuições da Webshare.
  def initialize(engine_sessions, assignments)
    @engine_sessions = engine_sessions
    @assignments = assignments
    @statuses = engine_sessions.to_h { |session| [session['name'], session['status'].to_s] }
  end

  def general?(pool)
    baseline_down? || pool_down?(pool)
  end

  # [fora, total] para o alerta: IPs do plano, ou sessões sem proxy quando a linha de base caiu.
  def numbers(pool)
    baseline_down? ? baseline_numbers : numbers_for_pool(pool)
  end

  private

  def pool_down?(pool)
    off, total = numbers_for_pool(pool)
    off >= MIN_OFF && off > total * MAX_SHARE
  end

  def numbers_for_pool(pool)
    ips = ips_of(pool)
    [ips.count { |_address, sessions| sessions.any? { |name| off?(name) } }, ips.size]
  end

  def ips_of(pool)
    @assignments.select { |assignment| assignment.pool == pool && @statuses.key?(assignment.session_name) }
                .group_by(&:proxy_address).transform_values { |rows| rows.map(&:session_name) }
  end

  def baseline_down?
    return @baseline_down if defined?(@baseline_down)

    off, total = baseline_numbers
    @baseline_down = off >= MIN_OFF && off > total * MAX_SHARE
  end

  def baseline_numbers
    proxied = @assignments.map(&:session_name)
    baseline = @engine_sessions.reject do |session|
      proxied.include?(session['name']) || session.dig('config', 'proxy', 'server').present?
    end
    [baseline.count { |session| off?(session['name']) }, baseline.size]
  end

  def off?(session_name)
    WhatsappProxy::Health::UNSTABLE_STATUSES.include?(@statuses[session_name])
  end
end
