# Grava nos toques de campanha da conversa os nomes de anúncio, conjunto e campanha da Meta (#1034).
#
# Os IDs saem dos parâmetros automáticos do anúncio — `utm_content` (anúncio), `utm_term` (conjunto),
# `utm_campaign`/`utm_id` (campanha) — e, no clique que abre o WhatsApp (`meta_ctwa`), do `source_id`,
# que é o ID do anúncio. Só entram valores que são IDs (Crm::MetaAds::NameResolver.meta_id?).
#
# A escrita é merge sob lock da linha: acrescenta `ad_name`, `adset_name` e `campaign_name` sem apagar
# nenhuma outra chave do toque. O `headline` de toque de site só muda quando ainda é
# "<nome da origem> · <ID da campanha>" (o formato do Ctwa::TrackedLinkAttributor); vira
# "<nome da origem> · <nome da campanha>". A origem (`campaign`) recebe o mesmo tratamento quando é
# o mesmo toque.
class Crm::MetaAds::TouchEnricher
  NAME_KEYS = %w[ad_name adset_name campaign_name].freeze
  HEADLINE_SEPARATOR = ' · '.freeze
  SITE_SOURCE_PREFIX = 'site:'.freeze

  def self.ids_by_type(touch)
    return {} unless touch.is_a?(Hash)

    {
      'ad' => [touch['utm_content'], (touch['source_id'] if touch['source'] == Ctwa::CampaignBuilder::CTWA_SOURCE)],
      'adset' => [touch['utm_term']],
      'campaign' => [touch['utm_campaign'], touch['utm_id']]
    }.transform_values { |ids| ids.select { |id| Crm::MetaAds::NameResolver.meta_id?(id) }.map(&:to_s) }
      .reject { |_type, ids| ids.empty? }
  end

  def self.meta_ids?(touch)
    ids_by_type(touch).any?
  end

  # Toque com ID e ainda sem nenhum nome: é o que a resolução retroativa procura.
  def self.unnamed?(touch)
    meta_ids?(touch) && NAME_KEYS.none? { |key| touch[key].present? }
  end

  # `resolved`: nomes já resolvidos ({ id => { name:, ... } }), como a resolução retroativa faz uma
  # vez para todas as conversas. Sem ele, cada conversa resolve os próprios IDs.
  def initialize(conversation, resolved: nil)
    @conversation = conversation
    @resolved = resolved
  end

  # true quando algum toque mudou.
  def perform
    resolved = resolve(touches_of(@conversation))
    return false if resolved.empty?

    changed = write(resolved)
    Crm::Cards::RebroadcastConversationCardsJob.perform_later(@conversation.id) if changed && Crm::Config.enabled?
    changed
  end

  private

  def touches_of(conversation)
    touches = conversation.additional_attributes.to_h['campaign_touches']
    touches.is_a?(Array) ? touches.select { |touch| touch.is_a?(Hash) } : []
  end

  # A chamada HTTP fica fora do lock da linha.
  def resolve(touches)
    return @resolved unless @resolved.nil?

    ids = touches.map { |touch| self.class.ids_by_type(touch) }
                 .each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |by_type, all| by_type.each { |type, list| all[type] |= list } }
    resolver = Crm::MetaAds::NameResolver.new(@conversation.account)
    ids.reduce({}) { |resolved, (type, list)| resolved.merge(resolver.resolve(list, type: type)) }
  end

  # reload: descarta o display_id em memória, que o with_lock recusaria como mudança pendente.
  def write(resolved)
    changed = false
    @conversation.reload.with_lock do
      attrs = @conversation.additional_attributes.to_h
      touches = attrs['campaign_touches']
      next unless touches.is_a?(Array)

      enriched = touches.map { |touch| touch.is_a?(Hash) ? enrich(touch, resolved) : touch }
      origin = enriched_origin(attrs['campaign'], touches, resolved)
      next if enriched == touches && origin == attrs['campaign']

      changes = { 'campaign_touches' => enriched }
      changes = changes.merge('campaign' => origin) if origin.is_a?(Hash)
      @conversation.update!(additional_attributes: attrs.merge(changes))
      changed = true
    end
    changed
  end

  def enriched_origin(origin, touches, resolved)
    return origin unless origin.is_a?(Hash)

    key = Ctwa::CampaignBuilder.dedup_key(origin)
    same_touch = key.present? && touches.any? { |touch| touch.is_a?(Hash) && Ctwa::CampaignBuilder.dedup_key(touch) == key }
    same_touch ? enrich(origin, resolved) : origin
  end

  def enrich(touch, resolved)
    names = names_for(touch, resolved)
    return touch if names.empty?

    enriched = touch.merge(names)
    headline = renamed_headline(touch, names['campaign_name'])
    headline ? enriched.merge('headline' => headline) : enriched
  end

  def names_for(touch, resolved)
    ids = self.class.ids_by_type(touch)
    ad = first_resolved(ids['ad'], resolved)
    adset = first_resolved(ids['adset'], resolved)
    campaign = first_resolved(ids['campaign'], resolved)

    {
      'ad_name' => ad&.dig(:name),
      'adset_name' => adset&.dig(:name) || ad&.dig(:adset_name),
      'campaign_name' => campaign&.dig(:name) || adset&.dig(:campaign_name) || ad&.dig(:campaign_name)
    }.compact_blank
  end

  def first_resolved(ids, resolved)
    Array(ids).lazy.map { |id| resolved[id] }.find(&:present?)
  end

  # "<origem> · <ID>" → "<origem> · <nome da campanha>". Só toque de site, e só quando o sufixo é
  # exatamente o ID da campanha que o atribuidor pôs ali.
  def renamed_headline(touch, campaign_name)
    return if campaign_name.blank? || !touch['source_id'].to_s.start_with?(SITE_SOURCE_PREFIX)

    campaign_id = touch['utm_campaign'].to_s
    headline = touch['headline'].to_s
    suffix = "#{HEADLINE_SEPARATOR}#{campaign_id}"
    return unless Crm::MetaAds::NameResolver.meta_id?(campaign_id) && headline.end_with?(suffix)

    "#{headline.delete_suffix(campaign_id)}#{campaign_name}"
  end
end
