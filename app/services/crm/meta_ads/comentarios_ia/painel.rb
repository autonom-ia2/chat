# IA cuida dos comentários (#2212, B1/B2): o que a tela do cuidado mostra e o que ela grava, para um post do Seus posts
# ou um anúncio. O contrato está em docs/audit/2026-10-30-2212-contrato-api.md.
#
# - O cuidado (Crm::MetaAdsCommentCare) guarda o que o dono escreveu: a mensagem do privado, para quem ela vai, nas
#   palavras dele, e as frases públicas, no idioma da tela. O servidor não monta frase.
# - O resto é lido na hora: os comentários do alvo (Fonte, ao vivo, nunca gravados) e o que a IA fez com cada um
#   (Crm::MetaAdsCommentAction, actor 'ai'). Recebeu no privado e respondeu: pelas conversas que nasceram do cuidado.
# - "Esperando você" (`to_see`) é o que ficou com o dono, com o porquê: reclamação, privado recusado, mais de 7 dias,
#   não era o caso (a IA leu e não agiu) ou chegou antes de ligar. "Escondi" (`hidden`): o que a IA escondeu.
# - "Ler e mandar": uma vez por cuidado ligado, o LerAntigosJob põe os comentários de até 7 dias na fila do motor, como
#   comentários novos. Quem não é o caso fica com o dono.
class Crm::MetaAds::ComentariosIa::Painel
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  STATUSES = %w[on paused].freeze
  # A rede que já deixa a IA mandar o privado (Rede#privado_disponivel?): o Facebook espera a pages_messaging (F4).
  PRIVADO_LIBERADO = %w[instagram].freeze
  MOTIVO_DA_ACAO = { 'to_you' => 'complaint', 'private_reply_failed' => 'failed' }.freeze

  # alvo: { 'kind' => 'post', 'perfil', 'post_id', 'networks' } ou { 'kind' => 'ad', 'ad_id', 'networks', 'post_ids' }
  # (Fonte.do_alvo). `post_ids`: no anúncio, os posts do criativo (por onde chega o comentário sem o id do anúncio).
  # conversation_access: se quem abre a tela enxerga a conversa (o "Ver conversa" só vai quando sim).
  def initialize(account:, alvo:, fonte:, conversation_access:)
    @account = account
    @alvo = alvo.to_h.stringify_keys
    @networks = Array(@alvo['networks'])
    @post_ids = Array(@alvo['post_ids']).map(&:to_s)
    @fonte = fonte
    @conversation_access = conversation_access
  end

  def payload
    lido = @fonte.ler
    return cuidado_payload.merge(status: lido[:status], unanswered: 0, older: 0, to_see: [], hidden: []) unless lido[:status] == 'ready'

    cuidado_payload.merge(lista(lido))
  end

  def salvar!(message:, para_quem:, phrases:, status:, user:)
    raise Error, 'invalid_status' unless STATUSES.include?(status)
    raise Error, 'invalid_para_quem' if para_quem.to_s.strip.empty?

    registro = cuidado || Crm::MetaAdsCommentCare.new(account: @account, target_kind: target_kind, target_id: target_id,
                                                      started_at: Time.current, created_by: user)
    registro.assign_attributes(network: rede_do_cuidado, post_ids: @post_ids, message: message.to_s.strip,
                               para_quem: para_quem.to_s.strip, phrases: Array(phrases).map(&:to_s), status: status)
    registro.save!
    @cuidado = registro
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "invalid_#{e.record.errors.attribute_names.first}"
  end

  def ler_antigos!
    raise Error, 'not_on' unless cuidado&.status == 'on'
    raise Error, 'already_read' if cuidado.read_old_at.present?

    cuidado.update!(read_old_at: Time.current)
    Crm::MetaAds::ComentariosIa::LerAntigosJob.perform_later(@account.id, @alvo)
  end

  def cuidado
    return @cuidado if defined?(@cuidado)

    @cuidado = Crm::MetaAdsCommentCare.find_by(account_id: @account.id, target_kind: target_kind, target_id: target_id)
  end

  private

  def cuidado_payload
    escrito = cuidado || Crm::MetaAdsCommentCare.new
    {
      network: rede_do_cuidado, private_available: @networks.intersect?(PRIVADO_LIBERADO), care: cuidado ? escrito.status : 'off',
      message: escrito.message.to_s, para_quem: escrito.para_quem.to_s, phrases: Array(escrito.phrases),
      read_old: escrito.read_old_at.present?, results: resultados.merge(skipped: 0)
    }
  end

  def lista(lido)
    acoes = acoes_da_ia((lido[:linhas] + lido[:escondidas]).pluck(:id))
    to_see = lido[:linhas].map { |linha| item(linha, acoes[linha[:id].to_s]) }
    recentes = lido[:linhas].count { |linha| recente?(linha) }
    { status: 'ready', unanswered: recentes, older: lido[:linhas].size - recentes, to_see: to_see,
      hidden: escondidas_pela_ia(lido[:escondidas], acoes), results: resultados.merge(skipped: to_see.count { |linha| linha[:kind] == 'skipped' }) }
  end

  def escondidas_pela_ia(escondidas, acoes)
    escondidas.select { |linha| acoes[linha[:id].to_s].key?('hide') }.map { |linha| comentario(linha) }
  end

  def item(linha, acoes)
    acoes ||= {}
    motivo = acoes.keys.filter_map { |acao| MOTIVO_DA_ACAO[acao] }.first
    comentario(linha).merge(kind: motivo || tipo_sem_acao(linha, acoes), conversation_path: caminho(acoes.values.compact.first))
  end

  def tipo_sem_acao(linha, acoes)
    return 'older' unless recente?(linha)

    acoes.key?(Crm::MetaAds::ComentariosIa::Registro::LIDO) ? 'skipped' : 'waiting'
  end

  def comentario(linha)
    { id: linha[:id].to_s, network: linha[:network], author: linha[:author], text: linha[:text] }
  end

  # { comment_id => { ação => conversa } }, só as da IA nesta conta.
  def acoes_da_ia(ids)
    Crm::MetaAdsCommentAction.where(account_id: @account.id, actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR, comment_id: ids.map(&:to_s))
                             .includes(:conversation)
                             .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |acao, por_comentario|
      por_comentario[acao.comment_id][acao.action] = acao.conversation
    end
  end

  def resultados
    return { sent: 0, replied: 0 } if cuidado.nil?

    enviadas = Conversation.where(account_id: @account.id)
                           .where("additional_attributes -> 'meta_ads_comment' ->> 'care_id' = ?", cuidado.id.to_s)
                           .where("additional_attributes -> 'meta_ads_comment' ->> 'private_reply' = 'true'")
    { sent: enviadas.count,
      replied: enviadas.where(id: Message.where(account_id: @account.id, message_type: :incoming).select(:conversation_id)).count }
  end

  def caminho(conversation)
    return if conversation.nil? || !@conversation_access.call(conversation)

    "/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end

  def recente?(linha)
    linha[:momento].present? && linha[:momento] >= Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago
  end

  def rede_do_cuidado
    @networks.size > 1 ? 'both' : @networks.first
  end

  def target_kind
    @alvo['kind']
  end

  def target_id
    target_kind == 'post' ? @alvo['post_id'].to_s : @alvo['ad_id'].to_s
  end
end
