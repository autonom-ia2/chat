# AS PESSOAS DA PÁGINA QUE O DONO LIBEROU PARA A IA (#1307).
#
# A configuração do agente é uma LIBERAÇÃO, não uma regra: `config['booking_agent_ids']` diz quais pessoas da página a
# IA pode usar. Vazia ou ausente = todas (agente já configurado não muda). Com quem marcar, entre as liberadas, quem
# decide é o MODELO, pela instrução do dono e pela conversa; aqui nada lê texto (sem regex, sem lista de palavras).
#
# Pessoa da página = `InvitePages#people` (quem pode atender, na ordem fixa do #1305). Id liberado que não é mais
# pessoa da página (saiu, link desligado, outra conta) não vale: a liberação nunca cai para "todas" por isso, ela
# fica sem ninguém e o agente vê a agenda sem responsável. "Todas" é só a chave ausente, `nil` ou `[]`; um valor
# gravado que não dá para ler (texto, lista sem número) também é "ninguém", nunca "todas".
#
# Pela API (`liberacao_conferida`): quando o pedido MUDA a liberação, ids de fora da página são descartados e um
# pedido que não deixa ninguém (só ids de fora, ou valor que não é lista) é RECUSADO (`Recusada`), para a restrição do
# dono nunca virar "todas" em silêncio. Reenviar a liberação salva não mexe nela. Trocar a página também não: a
# restrição salva fica, e quem não é da página nova não vale (agenda sem responsável até o dono escolher de novo).
#
# `estado` (só depois de a página estar `ativa`): 'ativa' com alguém liberado que pode atender, 'agenda_pausada' com
# todas as liberadas pausadas em Meus horários, 'sem_responsavel' sem nenhuma liberada.
class Autonomia::Agents::Tools::Native::AgendaPessoas
  CONFIG_KEY = 'booking_agent_ids'.freeze
  PAGINA_KEY = 'booking_page_id'.freeze

  # O pedido pela API não deixa ninguém liberado: recusado com 422 pelo controller.
  class Recusada < StandardError; end

  # Inteiros únicos, na ordem recebida. O que não é lista, ou não é número inteiro positivo, é descartado.
  def self.normalizar(valor)
    return [] unless valor.is_a?(Array)

    valor.filter_map { |item| numero(item) }.select(&:positive?).uniq
  end

  # Base 10 sempre: "010" não vira 8 nem "0x8" vira 8.
  def self.numero(valor)
    Integer(valor.to_s, 10, exception: false)
  end

  # "Todas": a chave ausente, nil ou lista vazia. Qualquer outro valor é uma restrição (mesmo ilegível).
  def self.todas?(valor)
    valor.nil? || valor == []
  end

  # Só os ids que são pessoas da página (da mesma conta: `pagina` já vem escopada pela conta). Pagina nil: nenhum.
  def self.conferir(ids, pagina:, paginas:)
    return [] if pagina.nil?

    da_pagina = paginas.people(pagina).map { |pessoa| pessoa.user.id }
    normalizar(ids) & da_pagina
  end

  # A liberação de um config que chega pela API (#1307), conferida contra a página que vai ficar (a do pedido ou a
  # salva) e a conta. Reenviar a liberação salva (como conjunto) não mexe nela, nem recusa. -> {} sem a chave.
  def self.liberacao_conferida(config, salvo:, account:)
    return {} unless config.key?(CONFIG_KEY)
    return { CONFIG_KEY => todas?(salvo[CONFIG_KEY]) ? [] : salvo[CONFIG_KEY] } unless muda?(config, salvo: salvo)

    ids = config[CONFIG_KEY]
    conferidos = conferir(ids, pagina: pagina_final(config, salvo, account), paginas: ::Crm::BookingV2::InvitePages.new(account))
    raise Recusada if conferidos.empty? && !todas?(ids)

    { CONFIG_KEY => conferidos }
  end

  # O pedido (cru, antes da conferência) muda quem está liberado? Compara como conjunto com o valor salvo, cru: reenviar
  # o que veio do GET não é mudança; sair de uma restrição para "todas" é.
  def self.muda?(pedido, salvo:)
    return false unless pedido.key?(CONFIG_KEY)

    valor = pedido[CONFIG_KEY]
    guardado = salvo[CONFIG_KEY]
    return todas?(valor) != todas?(guardado) if todas?(valor) || todas?(guardado)

    normalizar(valor).sort != normalizar(guardado).sort
  end

  def self.pagina_final(config, salvo, account)
    id = numero(config.key?(PAGINA_KEY) ? config[PAGINA_KEY] : salvo[PAGINA_KEY])
    id && account.crm_agent_booking_profiles.new_pages.includes(:default_assignee, agent_booking_links: :agent).find_by(id: id)
  end
  private_class_method :pagina_final

  def initialize(agent:, pagina:, paginas:)
    valor = agent.config.to_h[CONFIG_KEY]
    @todas = self.class.todas?(valor)
    @ids = self.class.normalizar(valor)
    @pagina = pagina
    @paginas = paginas
  end

  # As liberadas, na ordem da página, com o estado de cada uma.
  def liberadas
    @liberadas ||= begin
      todas = paginas.people(pagina)
      @todas ? todas : todas.select { |pessoa| ids.include?(pessoa.user.id) }
    end
  end

  # As liberadas que podem receber reunião agora (não pausaram a agenda).
  def atendem
    liberadas.reject(&:paused?)
  end

  # A liberada com este id (vindo do modelo: string ou inteiro), ou nil.
  def liberada(id)
    numero = self.class.numero(id)
    liberadas.find { |pessoa| pessoa.user.id == numero }
  end

  def estado
    return ::Crm::BookingV2::InvitePages::NO_HOST if liberadas.empty?

    atendem.any? ? ::Crm::BookingV2::InvitePages::ACTIVE : ::Crm::BookingV2::InvitePages::AGENDA_PAUSED
  end

  private

  attr_reader :ids, :pagina, :paginas
end
