# A COORDENADA DOS LOCAIS PRESENCIAIS DA PÁGINA (#1479 F3): o mapa que o agente manda (`enviar_localizacao`) precisa de
# latitude e longitude, e a página só tem o endereço escrito pelo dono.
#
# A COORDENADA E A MARCA "NÃO ACHOU" SÃO DO SERVIDOR E SEGUEM O ENDEREÇO. Quem as grava é o
# `Crm::BookingV2::GeocodificarLocaisJob`, direto na coluna. No salvar (`before_save`), cada item `in_person` fica com a
# coordenada e a marca que o item GRAVADO NO BANCO tinha para o MESMO endereço (relido na hora, não o snapshot do load:
# a coordenada que o job gravou depois de a página ser carregada não se perde), e com nenhuma se o endereço é novo,
# mudou ou saiu; o resto do item fica como veio. É isso que deixa o formulário salvar sem conhecê-las (ele só manda
# tipo, rótulo, endereço e link, `BookingPagesController#page_params`) sem apagá-las, e o que impede quem chama a API de
# escrever uma coordenada que não veio do Google ou uma marca que tira o endereço da fila.
#
# A MARCA NAO_ACHOU leva o hash do endereço (`hash_do_endereco`): o Google não achou um lugar preciso para ele, e ele não
# é pedido de novo enquanto for o mesmo.
#
# DEPOIS DO COMMIT, a lista que mudou e ficou com endereço pendente pede o job (`GeocodificarLocaisJob.pedir`: só com a
# conta ligada, uma vez por página e pendentes). O Google nunca roda no salvar: erro ao pedir fica no log (só o id e a
# classe) e no tracker, e o salvar segue. Só na página nova; a antiga não tem locais.
module Crm::BookingPageCoordenadas
  extend ActiveSupport::Concern

  PRESENCIAL = 'in_person'.freeze
  COORDENADAS = %w[latitude longitude].freeze
  NAO_ACHOU = 'geo_nao_achou'.freeze
  DO_SERVIDOR = (COORDENADAS + [NAO_ACHOU]).freeze
  TAMANHO_DO_HASH = 16

  # O hash que a marca NAO_ACHOU leva: os primeiros 16 hex do SHA256 do endereço como está gravado.
  def self.hash_do_endereco(endereco)
    Digest::SHA256.hexdigest(endereco.to_s).first(TAMANHO_DO_HASH)
  end

  included do
    before_save :coordenadas_seguem_o_endereco, if: -> { new_page? && will_save_change_to_locations? }
    after_commit :geocodificar_depois, on: [:create, :update], if: :geocodificar?
  end

  # Os endereços presenciais da página sem coordenada e sem a marca NAO_ACHOU do endereço atual. Lido pelo job.
  def enderecos_sem_coordenada
    Array(locations).filter_map do |item|
      next unless presencial?(item) && item['address'].present?
      next if nao_achou?(item)

      item['address'] if COORDENADAS.any? { |chave| item[chave].nil? }
    end.uniq
  end

  private

  def presencial?(item)
    item.is_a?(Hash) && item['type'] == PRESENCIAL
  end

  def nao_achou?(item)
    item[NAO_ACHOU].present? && item[NAO_ACHOU] == Crm::BookingPageCoordenadas.hash_do_endereco(item['address'])
  end

  def coordenadas_seguem_o_endereco
    conhecidos = dados_do_servidor
    self.locations = Array(locations).map do |item|
      next item unless presencial?(item)

      dados = conhecidos[item['address']] if item['address'].present?
      item.except(*DO_SERVIDOR).merge(dados.to_h)
    end
  end

  # { endereço => { 'latitude', 'longitude', NAO_ACHOU } } dos itens presenciais como estão NO BANCO agora.
  def dados_do_servidor
    # Com a linha travada (FOR UPDATE, dentro da transação do salvar): o job, que grava sob o mesmo lock, espera.
    gravada = new_record? ? [] : self.class.lock.where(id: id).pick(:locations)
    Array(gravada).each_with_object({}) do |item, conhecidos|
      next unless presencial?(item) && item['address'].present?

      dados = dados_do_item(item)
      conhecidos[item['address']] ||= dados if dados.any?
    end
  end

  # A coordenada completa e a marca NAO_ACHOU do endereço atual do item gravado; {} sem nenhuma.
  def dados_do_item(item)
    dados = COORDENADAS.all? { |chave| item[chave].present? } ? item.slice(*COORDENADAS) : {}
    nao_achou?(item) ? dados.merge(NAO_ACHOU => item[NAO_ACHOU]) : dados
  end

  def geocodificar?
    new_page? && (previously_new_record? || saved_change_to_locations?) && enderecos_sem_coordenada.any?
  end

  def geocodificar_depois
    ::Crm::BookingV2::GeocodificarLocaisJob.pedir(self)
  rescue StandardError => e
    Rails.logger.error("[crm][booking_v2][geocodificar] nao_enfileirado page_id=#{id} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
