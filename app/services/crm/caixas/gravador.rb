# Caixas no CRM (#1149): grava a caixa inteira de uma vez (R16) — o que chega, o que o sistema faz sozinho e quem
# cuida de quê.
#
# - Um funil: o card nasce nele, na etapa escolhida, assim que a conversa chega ('chegou') ou à mão ('off'). É o
#   comportamento de sempre (InboxSetting + vínculo com auto_create_card).
# - Vários funis: nenhum card nasce num funil fixo (R9). Quem cria é a IA de assunto ('auto' ou 'suggest') ou a
#   equipe ('off').
# - Nenhum funil: a caixa sai do CRM. Os vínculos ficam, com a criação desligada, como o PipelineLinkSyncer faz.
# - Caixa ainda em "Agente vê apenas atribuídos" (R6) só sai dele com escolha explícita ('manter' ou 'mudar'; com
#   'manter' a tela já manda cada agente em "Só as que atende"). Sem escolha, nada é gravado.
# - Funil arquivado não aparece na tela: seus vínculos e liberações ficam como estão.
# - Pessoa que cuida de tudo (sem assunto, todos os funis, todas as conversas) fica sem linha de acesso: é o mesmo
#   que não ter configuração (R5). Administrador e usuário de integração nunca ganham linha.
# - Agentes de IA de área e os funis deles (#1447): só quando a tela manda `ai_agents` (Crm::Caixas::GravadorDeAgentes).
#   Funil que sai da caixa leva junto o agente responsável por ele nela.
class Crm::Caixas::Gravador
  class Invalida < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  MODOS_UM_FUNIL = %w[chegou off].freeze
  MODOS_VARIOS = %w[auto suggest off].freeze
  ESCOLHAS_DO_LEGADO = %w[manter mudar].freeze

  def initialize(account:, inbox:, user:, dados:)
    @account = account
    @inbox = inbox
    @user = user
    @dados = dados
  end

  def perform
    ActiveRecord::Base.transaction do
      validar!
      funis_retirados = gravar_vinculos!
      gravar_configuracao!
      gravar_acessos!
      gravar_agentes!(funis_retirados)
      expirar_sugestoes!(funis_retirados)
    end
  end

  private

  def validar!
    erro = primeiro_erro
    raise Invalida, erro if erro
  end

  # Na ordem: o primeiro que falhar é o código devolvido à tela.
  VALIDACOES = {
    'crm.caixas.funil_invalido' => :funil_de_fora?,
    'crm.caixas.modo_invalido' => :modo_invalido?,
    'crm.caixas.etapa_invalida' => :etapa_invalida?,
    'crm.caixas.pessoa_invalida' => :pessoa_de_fora?,
    'crm.caixas.legado_pendente' => :legado_sem_escolha?,
    'crm.caixas.sem_triagem' => :falta_triagem?
  }.freeze

  def primeiro_erro
    VALIDACOES.find { |_codigo, regra| send(regra) }&.first
  end

  def funil_de_fora?
    (pipeline_ids - funis_da_conta.map(&:id)).any?
  end

  def modo_invalido?
    modos_validos.exclude?(modo)
  end

  def etapa_invalida?
    um_funil? && etapa.nil?
  end

  def pessoa_de_fora?
    (pessoas.keys - agentes.keys).any?
  end

  def legado_sem_escolha?
    legado? && ESCOLHAS_DO_LEGADO.exclude?(@dados[:legado].to_s)
  end

  def modos_validos
    return %w[off] if pipeline_ids.empty?

    um_funil? ? MODOS_UM_FUNIL : MODOS_VARIOS
  end

  # R7: com mais de um funil, alguém da caixa precisa ver as conversas ainda sem assunto.
  def falta_triagem?
    return false if pipeline_ids.size < 2 || agentes.empty?

    agentes.keys.none? { |user_id| triagem?(user_id) }
  end

  def setting
    @setting ||= @account.crm_inbox_settings.find_or_initialize_by(inbox: @inbox)
  end

  def legado?
    setting.persisted? && setting.crm_enabled? && setting.assigned_only?
  end

  def gravar_configuracao!
    setting.update!(
      crm_enabled: pipeline_ids.any?,
      default_pipeline_id: um_funil? ? pipeline_ids.first : nil,
      default_stage_id: etapa&.id,
      auto_create_card: um_funil? && modo == 'chegou',
      subject_ai_mode: um_funil? || pipeline_ids.empty? ? 'off' : modo,
      visibility_mode: :all_inbox_cards
    )
  end

  # Devolve os funis que saíram da caixa.
  def gravar_vinculos!
    vinculos = @account.crm_pipeline_inboxes.where(inbox_id: @inbox.id, pipeline_id: funis_da_conta.map(&:id))
    return desligar_vinculos!(vinculos) if pipeline_ids.empty?

    retirados = vinculos.where.not(pipeline_id: pipeline_ids)
    ids_retirados = retirados.pluck(:pipeline_id)
    retirados.destroy_all
    pipeline_ids.each { |pipeline_id| gravar_vinculo!(vinculos, pipeline_id) }
    ids_retirados
  end

  # Caixa sem funil sai do CRM: os vínculos ficam, com a criação desligada. Nenhum funil saiu de fato.
  def desligar_vinculos!(vinculos)
    vinculos.find_each { |vinculo| vinculo.update!(auto_create_card: false) }
    []
  end

  def gravar_vinculo!(vinculos, pipeline_id)
    vinculo = vinculos.find_or_initialize_by(pipeline_id: pipeline_id, account_id: @account.id)
    vinculo.assign_attributes(auto_create_card: um_funil? && modo == 'chegou', default_stage_id: um_funil? ? etapa.id : nil)
    vinculo.created_by ||= @user
    vinculo.save!
  end

  def gravar_agentes!(funis_retirados)
    Crm::InboxAiAgent.where(account_id: @account.id, inbox_id: @inbox.id, pipeline_id: funis_retirados).delete_all if funis_retirados.any?
    return unless @dados.key?(:ai_agents)

    Crm::Caixas::GravadorDeAgentes.new(account: @account, inbox: @inbox, lista: @dados[:ai_agents], pipeline_ids: pipeline_ids).perform
  end

  # Sugestão de assunto que esperava resposta num funil que saiu da caixa não pode mais ser aceita: sai da tela,
  # como quando a caixa deixa de sugerir (#1221).
  def expirar_sugestoes!(funis_retirados)
    return if funis_retirados.empty?

    pendentes = Crm::SubjectDecision.suggested.where(account_id: @account.id, pipeline_id: funis_retirados,
                                                     conversation_id: @inbox.conversations.select(:id))
    conversation_ids = pendentes.distinct.pluck(:conversation_id)
    return if conversation_ids.empty?

    pendentes.update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @account.conversations.where(id: conversation_ids).find_each { |conversation| Crm::Subjects::Notifier.notify(conversation) }
  end

  def gravar_acessos!
    agentes.each_key do |user_id|
      next unless pessoas.key?(user_id)

      restrito?(user_id) ? gravar_acesso!(user_id) : apagar_acesso!(user_id)
    end
  end

  def gravar_acesso!(user_id)
    access = Crm::InboxAgentAccess.find_or_initialize_by(account_id: @account.id, inbox_id: @inbox.id, user_id: user_id)
    access.update!(all_pipelines: todos_os_funis?(user_id), triage: triagem?(user_id), only_own: so_as_suas?(user_id))
    desejados = todos_os_funis?(user_id) ? [] : funis_da_pessoa(user_id)
    access.agent_pipelines.where(pipeline_id: funis_da_conta.map(&:id)).where.not(pipeline_id: desejados).destroy_all
    (desejados - access.agent_pipelines.pluck(:pipeline_id)).each do |pipeline_id|
      access.agent_pipelines.create!(account_id: @account.id, pipeline_id: pipeline_id)
    end
  end

  def apagar_acesso!(user_id)
    Crm::InboxAgentAccess.find_by(account_id: @account.id, inbox_id: @inbox.id, user_id: user_id)&.destroy!
  end

  def restrito?(user_id)
    !(triagem?(user_id) && todos_os_funis?(user_id) && !so_as_suas?(user_id))
  end

  # Com um funil só não existe "sem assunto" separado: quem cuida do funil cuida também da conversa sem card.
  def triagem?(user_id)
    return funis_da_pessoa(user_id).any? if um_funil?

    ActiveModel::Type::Boolean.new.cast(pessoas.dig(user_id, 'triage')) || false
  end

  def todos_os_funis?(user_id)
    (pipeline_ids - funis_da_pessoa(user_id)).empty?
  end

  def funis_da_pessoa(user_id)
    Array(pessoas.dig(user_id, 'pipeline_ids')).map(&:to_i) & pipeline_ids
  end

  def so_as_suas?(user_id)
    ActiveModel::Type::Boolean.new.cast(pessoas.dig(user_id, 'only_own')) || false
  end

  def um_funil?
    pipeline_ids.size == 1
  end

  def modo
    @dados[:modo].to_s
  end

  def pipeline_ids
    @pipeline_ids ||= Array(@dados[:pipeline_ids]).map(&:to_i).uniq
  end

  def etapa
    return unless um_funil?

    @etapa ||= begin
      stages = funis_da_conta.find { |pipeline| pipeline.id == pipeline_ids.first }.stages.order(:position, :id)
      # Etapa de outro funil é recusada; sem etapa, a primeira.
      @dados[:default_stage_id].present? ? stages.find_by(id: @dados[:default_stage_id]) : stages.first
    end
  end

  def funis_da_conta
    @funis_da_conta ||= @account.crm_pipelines.active.to_a
  end

  # Quem a tela pode mudar: membro da caixa, nem administrador nem usuário de integração.
  def agentes
    @agentes ||= @account.account_users.where(user_id: @inbox.inbox_members.select(:user_id))
                         .reject { |account_user| account_user.administrator? || account_user.integration? }
                         .index_by(&:user_id)
  end

  def pessoas
    @pessoas ||= Array(@dados[:people]).index_by { |pessoa| pessoa['id'].to_i }
  end
end
