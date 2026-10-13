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
# - `change!`: muda um modelo que já está na lista, a partir da entrada atual (aviso da Meta, #1337).
# - `replace!`: só o sync. A lista da Meta vale, menos o que outro escritor mudou enquanto o sync esperava a Meta
#   (diferença entre `base`, a lista lida antes de buscar, e a lista atual): isso fica como o outro escritor deixou.
module Whatsapp::Templates::ChannelList
  module_function

  # `merge: true` só para escritor parcial (a conferência do disparo pede menos campos que o sync): os campos que o item
  # não traz ficam como estavam. Sem ele, a entrada é trocada inteira (item completo da Meta, como o do `Manager`).
  def upsert!(channel, item, merge: false, only_existing: false)
    write!(channel) do |list|
      warn_id_clash(channel, list, item)
      index = list.index { |entry| same?(entry, item) }
      next(only_existing ? list : list + [item]) unless index

      list.dup.tap { |copy| copy[index] = merge ? list[index].merge(item) : item }
    end
  end

  def remove!(channel, item)
    write!(channel) { |list| list.reject { |entry| same?(entry, item) } }
  end

  # Muda só um modelo que já está na lista (aviso da Meta, #1337): o bloco recebe a entrada atual, lida com a trava, e
  # devolve a nova, ou nil para deixar como está. Responde :changed, :unchanged ou :missing (modelo fora da lista).
  def change!(channel, item)
    result = :missing
    write!(channel) do |list|
      index = list.index { |entry| same?(entry, item) }
      next unless index

      updated = yield(list[index])
      result = updated.nil? || updated == list[index] ? :unchanged : :changed
      next unless result == :changed

      list.dup.tap { |copy| copy[index] = updated }
    end
    result
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

  # A chave que a Meta garante única na WABA é nome + idioma (idioma sem diferenciar maiúscula, como o
  # `Catalog.listed`): com nome dos dois lados, só ela decide. Assim um modelo apagado e criado de novo (outro id) troca
  # a entrada antiga, e um id repetido com outro nome (#1383: o stub da Graph devolvia o mesmo id para dois avisos)
  # nunca apaga outro modelo. Id só casa quando um dos lados vem sem nome e os dois têm id.
  def same?(entry, item)
    return false unless entry.is_a?(Hash) && item.is_a?(Hash)
    return same_key?(entry, item) if entry['name'].present? && item['name'].present?

    entry['id'].present? && entry['id'].to_s == item['id'].to_s
  end

  # Id repetido com outro nome: não deveria acontecer na Meta; fica no log e o item entra como outro modelo.
  def warn_id_clash(channel, list, item)
    return unless item['id'].present? && list.any? { |entry| entry['id'].to_s == item['id'].to_s && !same?(entry, item) }

    Rails.logger.warn "[whatsapp][templates] channel_list_id_clash channel_id=#{channel.id} meta_id=#{item['id']}"
  end

  def same_key?(entry, item)
    entry['name'] == item['name'] && entry['language'].to_s.casecmp?(item['language'].to_s)
  end

  def entries(list)
    Array(list.is_a?(Hash) ? nil : list).select { |entry| entry.is_a?(Hash) }
  end

  # Trava e relê só a coluna da lista (SELECT … FOR UPDATE na linha do canal), sem `with_lock`/`reload` no objeto de quem
  # chamou: `reload` descarta o cache das associações dele (a conta do canal) e recusaria um objeto com mudanças a salvar.
  # `update_columns` deixa o objeto de quem chamou com a lista nova (o envio da campanha lê dele). Bloco que devolve nil:
  # nada é gravado e o retorno é nil.
  def write!(channel, synced_at: nil)
    channel.class.transaction do
      current = entries(channel.class.where(id: channel.id).lock.pick(:message_templates))
      updated = yield(current)
      next if updated.nil?

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
