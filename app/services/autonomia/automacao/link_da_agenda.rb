# O link da agenda de uma pessoa (#2499, G12): o endereço público da página de agendamento em que ela atende, para o
# texto da automação mandar ao cliente marcar. É o mesmo endereço dos convites (Crm::BookingV2::ShortLink).
#
# Qual página: a da reunião, quando há uma (`pagina_id`, da reunião do gatilho); senão, a única página publicada em que
# a pessoa atende. Sem link, o passo pula, e o histórico diz por quê (`por`): `sem_responsavel`, `varias_paginas`
# (duas ou mais sem pista) ou `sem_pagina` (nenhuma em que ela atende, ela já não atende, ou o agendamento desligado
# na conta). Decide na hora do passo, com o responsável de então. Nunca cai no link de outra pessoa: o cliente
# marcaria com quem não é o responsável dele (parecer do Funções).
class Autonomia::Automacao::LinkDaAgenda
  Resultado = Data.define(:url, :por)

  def self.de(conta, pessoa, pagina_id: nil) = resultado(conta, pessoa, pagina_id: pagina_id).url

  def self.resultado(conta, pessoa, pagina_id: nil) = new(conta, pessoa, pagina_id).resultado

  def initialize(conta, pessoa, pagina_id)
    @conta = conta
    @pessoa = pessoa
    @pagina_id = pagina_id
  end

  def resultado
    return vazio('sem_responsavel') if @pessoa.nil?
    return vazio('sem_pagina') unless ::Crm::Config.booking_v2_enabled?(@conta)

    onde_atende = paginas.usable.select { |pagina| atende?(pagina) }
    return vazio('varias_paginas') if @pagina_id.blank? && onde_atende.many?

    pagina = escolhida(onde_atende)
    pagina ? Resultado.new(url: ::Crm::BookingV2::ShortLink.url_for(pagina, link: link_proprio(pagina)), por: nil) : vazio('sem_pagina')
  end

  private

  def vazio(por) = Resultado.new(url: nil, por: por)

  # A página da reunião, se a pessoa atende nela; sem reunião, a única em que atende.
  def escolhida(onde_atende)
    return onde_atende.find { |pagina| pagina.id == @pagina_id.to_i } if @pagina_id.present?

    onde_atende.first
  end

  # No responsável fixo, ele mesmo; no link por pessoa, o link ativo dela.
  def atende?(pagina)
    return pagina.default_assignee_id == @pessoa.id && elegivel? if pagina.assignment_mode_fixed?

    link_proprio(pagina).present?
  end

  def link_proprio(pagina)
    return unless pagina.assignment_mode_per_agent?

    pagina.agent_booking_links.find { |link| link.agent_id == @pessoa.id && paginas.link_usable?(link) }
  end

  def elegivel? = ::Crm::BookingV2::HostEligibility.eligible_user_ids(account: @conta).include?(@pessoa.id)

  def paginas = (@paginas ||= ::Crm::BookingV2::InvitePages.new(@conta))
end
