# IA cuida dos comentários (#2212, B1/B2): o que a tela do cuidado mostra e o que ela grava, para um post do Seus posts
# ou um anúncio. O contrato está em docs/audit/2026-10-30-2212-contrato-api.md.
#
# - O cuidado (Crm::MetaAdsCommentCare) guarda o que o dono escreveu: a mensagem do privado, para quem ela vai, nas
#   palavras dele, e as frases públicas, no idioma da tela. O servidor não monta frase.
# - O resto é lido na hora: os comentários do alvo (Fonte, ao vivo, nunca gravados) e o que a IA fez com cada um
#   (Crm::MetaAdsCommentAction, actor 'ai'). Recebeu no privado e respondeu: pelas conversas que nasceram do cuidado.
# - "Esperando você" (`to_see`) é o que ficou com o dono, com o porquê: reclamação, privado recusado, privado que pode
#   ter saído (a Meta não respondeu), não cuidei (Meta ou Jev fora do ar, teto do dia, sem certeza), mais de 7 dias,
#   não era o caso (a IA leu e não agiu), chegou antes de ligar (`started_at`) ou chegou com o cuidado pausado
#   (`paused`). O que chegou depois de ligar, com o cuidado ligado, e a IA ainda não leu está na fila dela: não entra.
#   "Escondi" (`hidden`): o que a IA escondeu.
# - "Ler e mandar": uma vez por cuidado ligado (trava atômica em `read_old_at`), o LerAntigosJob põe os comentários de
#   até 7 dias que chegaram antes de ligar na fila do motor, como comentários novos. Quem não é o caso fica com o dono.
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
  MOTIVO_DA_ACAO = {
    'to_you' => 'complaint', 'private_reply_failed' => 'failed', 'private_reply_unsure' => 'unsure', 'ai_unread' => 'unread'
  }.freeze

  CARE_ID = Arel.sql("conversations.additional_attributes -> 'meta_ads_comment' ->> 'care_id'")
  SEM_RESULTADO = { sent: 0, replied: 0 }.freeze

  # Recebeu no privado e respondeu, pelas conversas que nasceram do cuidado e que `user` vê
  # (Conversations::PermissionFilterService, como a contagem do Seus posts): a tela do cuidado e a lista do Seus posts.
  # Uma consulta por número, agrupada por cuidado: { care_id => { sent:, replied: } }, com zero para quem não tem nada.
  def self.resultados(account, cares, user)
    ids = Array(cares).map { |care| care.id.to_s }
    enviadas = enviadas_vistas(account, ids, user)
    sent = enviadas.group(CARE_ID).count
    replied = enviadas.where(respondeu.arel.exists).group(CARE_ID).count
    ids.to_h { |id| [id.to_i, { sent: sent.fetch(id, 0), replied: replied.fetch(id, 0) }] }
  end

  def self.enviadas_vistas(account, ids, user)
    Conversations::PermissionFilterService.new(account.conversations, user, account, for_reading: true).perform
                                          .unscope(:order).where(CARE_ID.in(ids))
                                          .where("conversations.additional_attributes -> 'meta_ads_comment' ->> 'private_reply' = 'true'")
  end

  # EXISTS por conversa enviada: o índice de messages.conversation_id, sem varrer as mensagens da conta.
  def self.respondeu
    Message.unscope(:order).where(message_type: :incoming).where(Message.arel_table[:conversation_id].eq(Conversation.arel_table[:id]))
  end
  private_class_method :enviadas_vistas, :respondeu

  # O cuidado do alvo (Fonte.do_alvo), ou nil. O LerAntigosJob também o acha por aqui.
  def self.cuidado_do(account_id, alvo)
    alvo = alvo.to_h.stringify_keys
    Crm::MetaAdsCommentCare.find_by(account_id: account_id, target_kind: alvo['kind'], target_id: target_id_do(alvo))
  end

  def self.target_id_do(alvo)
    alvo['kind'] == 'post' ? alvo['post_id'].to_s : alvo['ad_id'].to_s
  end

  # alvo: { 'kind' => 'post', 'perfil', 'post_id', 'networks', 'inbox_id' } ou { 'kind' => 'ad', 'ad_id', 'networks', 'post_ids' }
  # (Fonte.do_alvo). `post_ids`: no anúncio, os posts do criativo (por onde chega o comentário sem o id do anúncio).
  # conversation_access: se quem abre a tela enxerga a conversa (o "Ver conversa" só vai quando sim). viewer: quem abre a
  # tela; os números contam só as conversas que ele vê.
  def initialize(account:, alvo:, fonte:, conversation_access:, viewer:)
    @account = account
    @viewer = viewer
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

    gravar!({ network: rede_do_cuidado, post_ids: @post_ids, inbox_id: @alvo['inbox_id'], message: message.to_s.strip,
              para_quem: para_quem.to_s.strip, phrases: Array(phrases).map(&:to_s), status: status }, user)
  end

  # Só uma chamada acha `read_old_at` vazio e o marca (duas abas, duplo clique): a outra recebe `already_read`. Se a Meta
  # não responde, o LerAntigosJob solta a marca para o dono tentar de novo.
  def ler_antigos!
    raise Error, 'not_on' unless cuidado&.status == 'on'

    agora = Time.current
    marcou = Crm::MetaAdsCommentCare.where(id: cuidado.id, status: 'on', read_old_at: nil)
                                    .update_all(read_old_at: agora, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
    raise Error, 'already_read' unless marcou == 1

    cuidado.reload
    Crm::MetaAds::ComentariosIa::LerAntigosJob.perform_later(@account.id, @alvo)
  end

  def cuidado
    return @cuidado if defined?(@cuidado)

    @cuidado = self.class.cuidado_do(@account.id, @alvo)
  end

  private

  # Duas abas ligando o mesmo post ao mesmo tempo: a segunda esbarra no cuidado que a primeira acabou de criar (na
  # validação de unicidade ou, na corrida, no índice único). Relê o cuidado e aplica por cima, uma vez.
  def gravar!(atributos, user, de_novo: false)
    registro = cuidado || novo_cuidado(user)
    registro.assign_attributes(atributos)
    registro.save!
    @cuidado = registro
  rescue ActiveRecord::RecordNotUnique
    raise if de_novo

    reler_e_gravar!(atributos, user)
  rescue ActiveRecord::RecordInvalid => e
    return reler_e_gravar!(atributos, user) if !de_novo && e.record.new_record? && e.record.errors.of_kind?(:target_id, :taken)

    raise Error, "invalid_#{e.record.errors.attribute_names.first}"
  end

  def reler_e_gravar!(atributos, user)
    remove_instance_variable(:@cuidado) if defined?(@cuidado)
    gravar!(atributos, user, de_novo: true)
  end

  def novo_cuidado(user)
    Crm::MetaAdsCommentCare.new(account: @account, target_kind: target_kind, target_id: target_id, started_at: Time.current,
                                created_by: user)
  end

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
    to_see = lido[:linhas].filter_map { |linha| item(linha, acoes[linha[:id].to_s]) }
    contagens(lido[:linhas]).merge(status: 'ready', to_see: to_see, hidden: escondidas_pela_ia(lido[:escondidas], acoes),
                                   results: resultados.merge(skipped: to_see.count { |linha| linha[:kind] == 'skipped' }))
  end

  # unanswered: o que o "Ler e mandar" pode cuidar (até 7 dias e de antes de ligar); older: mais de 7 dias.
  def contagens(linhas)
    { unanswered: linhas.count { |linha| recente?(linha) && antes_de_ligar?(linha) }, older: linhas.count { |linha| !recente?(linha) } }
  end

  def escondidas_pela_ia(escondidas, acoes)
    escondidas.select { |linha| acoes[linha[:id].to_s].key?('hide') }.map { |linha| comentario(linha) }
  end

  def item(linha, acoes)
    acoes ||= {}
    kind = acoes.keys.filter_map { |acao| MOTIVO_DA_ACAO[acao] }.first || tipo_sem_acao(linha, acoes)
    return if kind.nil?

    comentario(linha).merge(kind: kind, conversation_path: caminho(acoes.values.compact.first))
  end

  # nil: chegou depois de ligar, com o cuidado ligado, e a IA ainda não leu (está na fila dela): não fica com o dono.
  # Com o cuidado pausado, a IA não lê: fica com o dono (`paused`).
  def tipo_sem_acao(linha, acoes)
    return 'older' unless recente?(linha)
    return 'skipped' if acoes.key?(Crm::MetaAds::ComentariosIa::Registro::LIDO)
    return 'waiting' if antes_de_ligar?(linha)

    'paused' if cuidado.status == 'paused'
  end

  # Sem cuidado, tudo é de antes de ligar.
  def antes_de_ligar?(linha)
    cuidado.nil? || linha[:momento].nil? || linha[:momento] < cuidado.started_at
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
    cuidado ? self.class.resultados(@account, [cuidado], @viewer).fetch(cuidado.id) : SEM_RESULTADO
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
    self.class.target_id_do(@alvo)
  end
end
