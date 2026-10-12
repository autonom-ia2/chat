# A lista de modelos guardada na caixa (`channel_whatsapp.message_templates`) tem vários escritores (#1382): o sync, a
# tela de Modelos (`Manager`), os avisos do agendamento (`NoticeTemplates::Creator`) e a conferência no disparo da
# campanha (`CampaignPauses::WhatsappDispatchGate`). Cada um lia a lista, esperava a Meta e gravava a lista inteira:
# o último apagava o que os outros tinham gravado no meio. Aqui todos gravam do mesmo jeito: trava na linha do canal
# (`with_lock`, que também relê a lista) e troca só da entrada do modelo, achada pelo id da Meta ou, sem id, pelo
# nome + idioma.
#
# - `upsert!`: põe ou atualiza um modelo. Os campos que o item não traz ficam como estavam (a conferência no disparo
#   pede menos campos que o sync).
# - `remove!`: tira um modelo.
# - `replace!`: só o sync. A lista da Meta vale, menos o que outro escritor mudou enquanto o sync esperava a Meta
#   (diferença entre `base`, a lista lida antes de buscar, e a lista atual): isso fica como o outro escritor deixou.
module Whatsapp::Templates::ChannelList
  module_function

  def upsert!(channel, item)
    write!(channel) do |list|
      index = list.index { |entry| same?(entry, item) }
      next list + [item] unless index

      list.dup.tap { |copy| copy[index] = list[index].merge(item) }
    end
  end

  def remove!(channel, item)
    write!(channel) { |list| list.reject { |entry| same?(entry, item) } }
  end

  def replace!(channel, templates, base:, synced_at: Time.current)
    write!(channel, synced_at: synced_at) { |current| merge_concurrent(templates, entries(base), current) }
  end

  def same?(entry, item)
    return false unless entry.is_a?(Hash) && item.is_a?(Hash)
    return entry['id'].to_s == item['id'].to_s if entry['id'].present? && item['id'].present?

    entry['name'] == item['name'] && entry['language'].to_s.casecmp?(item['language'].to_s)
  end

  def entries(list)
    Array(list.is_a?(Hash) ? nil : list).select { |entry| entry.is_a?(Hash) }
  end

  def write!(channel, synced_at: nil)
    channel.with_lock do
      current = entries(channel.message_templates)
      updated = yield(current)
      attributes = { message_templates: updated }
      attributes[:message_templates_last_updated] = synced_at if synced_at
      channel.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
      channel.account.update_cache_key('inbox') if updated != current
      updated
    end
  end

  # Entradas que mudaram entre `base` e `current` foram gravadas por outro escritor durante a busca: valem sobre a Meta.
  def merge_concurrent(fetched, base, current)
    changed_now = current.reject { |entry| base.include?(entry) }
    removed_now = base.reject { |entry| find_same(current, entry) }
    merged = entries(fetched).filter_map do |item|
      next if find_same(removed_now, item)

      find_same(changed_now, item) || item
    end
    merged + changed_now.reject { |entry| merged.include?(entry) }
  end

  def find_same(list, item)
    list.find { |entry| same?(entry, item) }
  end
end
