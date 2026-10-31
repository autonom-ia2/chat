# A COORDENADA DOS LOCAIS PRESENCIAIS DA PÁGINA (#1479 F3): o mapa que o agente manda (`enviar_localizacao`) precisa de
# latitude e longitude, e a página só tem o endereço escrito pelo dono.
#
# A COORDENADA É DO SERVIDOR E SEGUE O ENDEREÇO. Quem a grava é o `Crm::BookingV2::GeocodificarLocaisJob`, direto na
# coluna. No salvar (`before_save`), cada item `in_person` fica com a coordenada que um item de antes tinha para o
# MESMO endereço, e com nenhuma se o endereço é novo, mudou ou saiu; o resto do item fica como veio. É isso que deixa o
# formulário salvar sem conhecer a coordenada (ele só manda tipo, rótulo, endereço e link,
# `BookingPagesController#page_params`) sem apagá-la, e o que impede quem chama a API de escrever uma coordenada que não
# veio do Google.
#
# DEPOIS DO COMMIT, com a conta ligada (`CartaoDaPagina.ligado?`: a Fase 2 e a flag `agentes_enviar_local_e_contato`),
# a lista que mudou e ficou com endereço sem coordenada enfileira o job. O Google nunca roda no salvar: erro ao enfileirar
# fica no log (só o id e a classe) e no tracker, e o salvar segue. Só na página nova; a antiga não tem locais.
module Crm::BookingPageCoordenadas
  extend ActiveSupport::Concern

  PRESENCIAL = 'in_person'.freeze
  COORDENADAS = %w[latitude longitude].freeze

  included do
    before_save :coordenadas_seguem_o_endereco, if: -> { new_page? && will_save_change_to_locations? }
    after_commit :geocodificar_depois, on: [:create, :update], if: :geocodificar?
  end

  # Os endereços presenciais da página que ainda não têm coordenada. Lido também pelo job e pela tarefa de preencher.
  def enderecos_sem_coordenada
    Array(locations).filter_map do |item|
      next unless presencial?(item) && item['address'].present?

      item['address'] if COORDENADAS.any? { |chave| item[chave].nil? }
    end.uniq
  end

  private

  def presencial?(item)
    item.is_a?(Hash) && item['type'] == PRESENCIAL
  end

  def coordenadas_seguem_o_endereco
    conhecidas = coordenadas_de_antes
    self.locations = Array(locations).map do |item|
      next item unless presencial?(item)

      ponto = conhecidas[item['address']] if item['address'].present?
      item.except(*COORDENADAS).merge(ponto.to_h)
    end
  end

  # { endereço => { 'latitude', 'longitude' } } dos itens presenciais gravados antes deste salvar.
  def coordenadas_de_antes
    Array(locations_in_database).each_with_object({}) do |item, conhecidas|
      next unless presencial?(item) && item['address'].present? && COORDENADAS.all? { |chave| item[chave].present? }

      conhecidas[item['address']] ||= item.slice(*COORDENADAS)
    end
  end

  def geocodificar?
    new_page? && (previously_new_record? || saved_change_to_locations?) && enderecos_sem_coordenada.any?
  end

  def geocodificar_depois
    return unless ::Autonomia::Agents::Tools::Native::CartaoDaPagina.ligado?(account)

    ::Crm::BookingV2::GeocodificarLocaisJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[crm][booking_v2][geocodificar] nao_enfileirado page_id=#{id} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
