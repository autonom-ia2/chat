# O link da agenda de uma pessoa (#2499, G12): o endereço público da página de agendamento em que ela atende, para o
# texto da automação mandar ao cliente marcar. É o mesmo endereço dos convites (Crm::BookingV2::ShortLink).
#
# Qual página: a da reunião, quando a pessoa atende nela (`pagina_id`, da reunião do gatilho); senão, a única página
# publicada em que ela atende. Sem link, o passo pula, e o histórico diz por quê (`por`): `sem_responsavel`,
# `varias_paginas` (duas ou mais, e nenhuma é a da reunião) ou `sem_pagina` (nenhuma em que ela atende, ela já não atende, ou o agendamento desligado
# na conta). Decide na hora do passo, com o responsável de então. Nunca cai no link de outra pessoa: o cliente
# marcaria com quem não é o responsável dele (parecer do Funções).
class Autonomia::Automacao::LinkDaAgenda
  Resultado = Data.define(:url, :por)

  def self.de(conta, pessoa, pagina_id: nil) = resultado(conta, pessoa, pagina_id: pagina_id).url

  def self.resultado(conta, pessoa, pagina_id: nil) = new(conta, pessoa, pagina_id).resultado

  # G44 (#2756): a página escolhida na receita. A fixa dá o link dela, com quem a página diz (o responsável ainda
  # elegível: a página usável já confere); a por pessoa, só o link próprio de `pessoa` (o responsável do alvo). Sem
  # página usável, ou sem link de `pessoa` nela: vazio, nunca o link de outra pessoa.
  def self.da_pagina(conta, pessoa, pagina_id) = new(conta, pessoa, pagina_id).da_pagina

  # A página nova, publicada e com quem atenda, desta conta (o escopo das páginas da tela), ou nil.
  def self.pagina_usavel(conta, pagina_id) = ::Crm::BookingV2::InvitePages.new(conta).usable.find { |pagina| pagina.id == pagina_id }

  # O motivo do passo que pulou só sem o link: a página de reserva fora do ar (G60) e quem ligou sem acesso às páginas
  # (G44) têm o próprio; o resto é o faltou_link_da_agenda (G12).
  def self.motivo(por)
    proprios = [::Autonomia::Automacao::AgendaDaPagina::SEM_ACESSO, ::Autonomia::Automacao::AgendaDeReserva::INDISPONIVEL]
    proprios.include?(por) ? por : 'faltou_link_da_agenda'
  end

  def initialize(conta, pessoa, pagina_id)
    @conta = conta
    @pessoa = pessoa
    @pagina_id = pagina_id
  end

  # #2935: a página em que a pessoa atende e o link próprio dela, para a reunião pela conversa marcar pelo Booker na
  # mesma página do link da agenda. [página, link, por]; sem página, o `por`, como o link.
  def self.pagina_de(conta, pessoa) = new(conta, pessoa, nil).pagina_e_link

  def resultado
    pagina, link, por = pagina_e_link
    return vazio(por) if por

    Resultado.new(url: ::Crm::BookingV2::ShortLink.url_for(pagina, link: link), por: nil)
  end

  def pagina_e_link
    return [nil, nil, 'sem_responsavel'] if @pessoa.nil?
    return [nil, nil, 'sem_pagina'] unless ::Crm::Config.booking_v2_enabled?(@conta)

    onde_atende = paginas.usable.select { |pagina| atende?(pagina) }
    pagina = escolhida(onde_atende)
    return [nil, nil, onde_atende.many? ? 'varias_paginas' : 'sem_pagina'] unless pagina

    [pagina, link_proprio(pagina), nil]
  end

  def da_pagina
    return vazio('sem_pagina') unless ::Crm::Config.booking_v2_enabled?(@conta)

    pagina = paginas.usable.find { |usavel| usavel.id == @pagina_id }
    return vazio('sem_pagina') unless pagina
    return Resultado.new(url: ::Crm::BookingV2::ShortLink.url_for(pagina), por: nil) if pagina.assignment_mode_fixed?
    return vazio('sem_responsavel') if @pessoa.nil?

    link = link_proprio(pagina)
    link ? Resultado.new(url: ::Crm::BookingV2::ShortLink.url_for(pagina, link: link), por: nil) : vazio('sem_pagina')
  end

  private

  def vazio(por) = Resultado.new(url: nil, por: por)

  # A página da reunião desempata; sem ela (ou se a pessoa não atende nela), a única em que atende.
  def escolhida(onde_atende)
    da_reuniao = onde_atende.find { |pagina| pagina.id.to_s == @pagina_id.to_s } if @pagina_id.present?
    da_reuniao || (onde_atende.first if onde_atende.one?)
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
