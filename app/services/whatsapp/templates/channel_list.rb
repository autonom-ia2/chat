# A lista de modelos guardada na caixa (`channel_whatsapp.message_templates`) tem vários escritores (#1382): o sync, a
# tela de Modelos (`Manager`), os avisos do agendamento (`NoticeTemplates::Creator`) e a conferência no disparo da
# campanha (`CampaignPauses::WhatsappDispatchGate`). Cada um lia a lista, esperava a Meta e gravava a lista inteira:
# o último apagava o que os outros tinham gravado no meio. Aqui todos gravam do mesmo jeito: trava na linha do canal
# (`SELECT … FOR UPDATE`, que também relê a lista; nenhuma chamada à Meta com a trava aberta) e troca só da entrada
# do modelo, achada pelo id da Meta ou, sem id, pelo nome + idioma.
#
# - `upsert!`: põe ou atualiza um modelo (com `merge: true`, os campos que o item não traz ficam; a conferência no disparo
#   pede menos campos que o sync).
# - `remove!`: tira um modelo.
# - `replace!`: só o sync. A lista da Meta vale, menos o que outro escritor mudou enquanto o sync esperava a Meta
#   (diferença entre `base`, a lista lida antes de buscar, e a lista atual): isso fica como o outro escritor deixou.
module Whatsapp::Templates::ChannelList
  module_function

  # `merge: true` só para escritor parcial (a conferência do disparo pede menos campos que o sync): os campos que o item
  # não traz ficam como estavam. Sem ele, a entrada é trocada inteira (item completo da Meta, como o do `Manager`).
  def upsert!(channel, item, merge: false, only_existing: false)
    write!(channel) do |list|
      index = list.index { |entry| same?(entry, item) }
      next(only_existing ? list : list + [item]) unless index

      list.dup.tap { |copy| copy[index] = merge ? list[index].merge(item) : item }
    end
  end

  def remove!(channel, item)
    write!(channel) { |list| list.reject { |entry| same?(entry, item) } }
  end

  # A lista guardada foi zerada durante a busca (troca de conta do WhatsApp, `SameNumberGuard`): o que o sync buscou
  # pode ser da conta anterior, então não grava nada; o próximo sync traz a lista da conta nova.
  def replace!(channel, templates, base:, synced_at: Time.current)
    base = entries(base)
    write!(channel, synced_at: synced_at) do |current|
      next if current.empty? && base.any?

      merge_concurrent(templates, base, current)
    end
  end

  # A Meta não deixa dois modelos com o mesmo nome e idioma: mesmo id OU mesmo nome + idioma é o mesmo modelo (um modelo
  # apagado e criado de novo ganha outro id e substitui a entrada antiga).
  def same?(entry, item)
    return false unless entry.is_a?(Hash) && item.is_a?(Hash)
    return true if entry['id'].present? && entry['id'].to_s == item['id'].to_s

    entry['name'] == item['name'] && entry['language'].to_s.casecmp?(item['language'].to_s)
  end

  def entries(list)
    Array(list.is_a?(Hash) ? nil : list).select { |entry| entry.is_a?(Hash) }
  end

  # Trava e relê só a coluna da lista (SELECT … FOR UPDATE na linha do canal), sem `with_lock`/`reload` no objeto de quem
  # chamou: `reload` descarta o cache das associações dele (a conta do canal) e recusaria um objeto com mudanças a salvar.
  # `update_columns` deixa o objeto de quem chamou com a lista nova (o envio da campanha lê dele). Bloco que devolve nil:
  # nada é gravado.
  def write!(channel, synced_at: nil)
    channel.class.transaction do
      current = entries(channel.class.where(id: channel.id).lock.pick(:message_templates))
      updated = yield(current)
      next current if updated.nil?

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
