# O aviso à equipe da cotação da renovação (E8, #2901), no molde do aviso do Agendamento
# (Crm::BookingV2::Notices::AgentAlert): o que precisa de alguém vira atividade no card de renovação e tarefa vencendo
# agora para quem cuida do card (Crm::FollowUp, lembrete), que o cron de tarefas transforma em aviso conforme as
# preferências da pessoa. Sem tipo novo de Notification.
#
# Motivos (`MOTIVOS`, cada um com a frase de leigo em `carteira.cotacao.avisos`): o "Algo mudou?" ou a proposta que não
# saiu (com o motivo do envio), o segurado que disse que mudou algo, o que respondeu depois, o dado que faltou para cotar
# (com os nomes dos campos), a conferência que caiu três vezes, a cotação que não trouxe preço, a proposta que não se
# sabe se chegou e a resposta do segurado numa conversa que está com alguém quando era a Lia quem ia responder
# (`textos`: o nome de quem está com a conversa e o do agente, só no título).
#
# A atividade entra SEMPRE (é o registro no card, `carteira_cotacao_aviso`); a tarefa sai UMA vez por seguro, vigência e
# motivo. Card que sumiu: nada a avisar. O título leva o nome do contato (é a lista de tarefas da equipe) e nunca o
# texto do cliente; o `metadata` leva só ids, o motivo e os nomes dos campos.
class Carteira::Cotacao::Aviso
  SOURCE = 'carteira_cotacao'.freeze
  ATIVIDADE = 'carteira_cotacao_aviso'.freeze
  CONVERSA_COM_PESSOA = 'conversa_com_pessoa'.freeze
  MOTIVOS = (%w[algo_mudou_nao_saiu mudou cliente_respondeu faltou_dado conferencia_caiu proposta_nao_saiu sem_preco] +
             ['proposta_incerta', CONVERSA_COM_PESSOA]).freeze

  # detalhe: o motivo do envio que não saiu (Carteira::Cotacao::Envio::NaoSaiu); faltam: os nomes dos campos; textos: o que
  # mais a frase do motivo pede (`pessoa`, `agente`); uma_vez: nem a atividade entra de novo quando a tarefa já saiu.
  def initialize(apolice, motivo, detalhe: nil, faltam: [], textos: {}, uma_vez: false) # rubocop:disable Metrics/ParameterLists
    @apolice = apolice
    @motivo = motivo.to_s
    @detalhe = detalhe
    @faltam = Array(faltam)
    @textos = textos.to_h.symbolize_keys
    @uma_vez = uma_vez
  end

  def call
    raise ArgumentError, "motivo desconhecido: #{@motivo}" unless MOTIVOS.include?(@motivo)

    card = @apolice.crm_card
    return if card.nil? || (@uma_vez && ja_avisado?(card))

    Crm::ActivityLogger.new(card: card, actor: nil, event_type: ATIVIDADE, payload: payload).perform
    criar_tarefa!(card) unless ja_avisado?(card)
  end

  private

  def payload
    { apolice_id: @apolice.id, motivo: @motivo, detalhe: @detalhe, faltam: @faltam.presence, by: 'system' }.compact
  end

  def vigencia
    @apolice.fim_vigencia.iso8601
  end

  def ja_avisado?(card)
    Crm::FollowUp.where(account_id: @apolice.account_id, card_id: card.id)
                 .where("crm_follow_ups.metadata->>'source' = ?", SOURCE)
                 .where("crm_follow_ups.metadata->>'apolice_id' = ?", @apolice.id.to_s)
                 .where("crm_follow_ups.metadata->>'vigencia' = ?", vigencia)
                 .exists?(["crm_follow_ups.metadata->>'motivo' = ?", @motivo])
  end

  def criar_tarefa!(card)
    Crm::FollowUp.create!(
      account_id: @apolice.account_id, card: card, contact: card.contact, assignee: card.owner, created_by: nil,
      title: titulo(card).first(255), due_at: Time.current, timezone: fuso,
      follow_up_type: :task, automation_mode: :reminder_only, status: :pending,
      metadata: { 'source' => SOURCE, 'apolice_id' => @apolice.id, 'vigencia' => vigencia, 'motivo' => @motivo,
                  'detalhe' => @detalhe, 'faltam' => @faltam.presence }.compact
    )
  end

  def titulo(card)
    nome = card.contact&.name.presence || card.title
    frase = I18n.t("carteira.cotacao.avisos.#{@motivo}", **@textos, nome: nome, locale: locale)
    [frase, motivo_texto, faltam_texto].compact.join(' ')
  end

  # O motivo do envio ou da cotação que não saiu, quando a equipe pode agir sobre ele.
  def motivo_texto
    chave = "carteira.cotacao.avisos.motivos.#{@detalhe}"
    I18n.t(chave, locale: locale) if @detalhe.present? && I18n.exists?(chave, locale)
  end

  # O que faltou, com os nomes que a equipe reconhece (`carteira.cotacao.campos`); campo sem nome conhecido vai como veio.
  def faltam_texto
    return if @faltam.empty?

    nomes = @faltam.map { |campo| I18n.t("carteira.cotacao.campos.#{campo.tr('.', '_')}", locale: locale, default: campo) }
    I18n.t('carteira.cotacao.avisos.faltam', campos: nomes.join(', '), locale: locale)
  end

  def fuso
    Crm::Timezone::Resolver.new(account: @apolice.account).name_or_default
  end

  def locale
    @apolice.account.locale.presence || I18n.default_locale
  end
end
