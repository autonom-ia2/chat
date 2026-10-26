# O agente de IA abre um assunto num funil da caixa (#1447, contrato com Agentes IA #1433): é como a porta passa o
# cliente para a área que cuida daquele pedido.
#
#   Crm::Subjects::Abrir.new(conversation:, pipeline:, resumo:, motivo:, origem:, pedido_por: nil, transfer_id: nil).call
#   # => Resultado(ok:, acao: :aberto|:reaproveitado|:ja_no_funil, card:, pipeline:, agente:, recusa:)
#
# - :ja_no_funil: o assunto em atendimento já é daquele funil. Nada muda no card.
# - :reaproveitado: a conversa já tem um card aberto naquele funil; ele volta a ser o assunto atual.
# - :aberto: card novo na 1ª etapa do funil, que vira o assunto atual.
# Em todos, o pedido fica na atividade do card (ai_subject_opened: resumo, motivo, origem, pedido_por, transfer_id), e
# o Crm::Ai::ResponsibleAgentSync roda depois do commit para entregar a conversa ao agente responsável.
#
# Recusa: nada é gravado e `recusa` diz o porquê (texto em crm.subjects.abrir.recusas). O limite de quantas vezes o
# agente pode abrir fica com Agentes IA, que confere antes de chamar. Tudo no lock da conversa (o mesmo do CardSyncer
# e da IA de assunto), numa transação: as recusas são conferidas com a conversa relida, já travada.
class Crm::Subjects::Abrir
  Resultado = Struct.new(:ok, :acao, :card, :pipeline, :agente, :recusa, keyword_init: true) do
    def recusa_i18n_key
      "crm.subjects.abrir.recusas.#{recusa}" if recusa
    end
  end

  # fora_do_funil (#2084): o contato foi marcado parceiro do mercado ou não é negócio.
  RECUSAS = %i[sem_crm funil_invalido sem_agente_responsavel agente_fora_da_caixa pessoa_atribuida esperando_pessoa
               assunto_escolhido_por_pessoa fora_do_funil].freeze
  EVENTO = 'ai_subject_opened'.freeze
  # Teto de cada texto livre na atividade (o payload do card recusa texto maior que 1500).
  MAX_TEXTO = 1_000

  # Assinatura do contrato com Agentes IA (#1433): os sete nomes são combinados, não agrupar num objeto.
  def initialize(conversation:, pipeline:, resumo:, motivo:, origem:, pedido_por: nil, transfer_id: nil) # rubocop:disable Metrics/ParameterLists
    @conversation = conversation
    @account = conversation.account
    @pipeline = pipeline
    @resumo = resumo.to_s.squish
    @motivo = motivo.to_s.squish
    @origem = origem
    @pedido_por = pedido_por
    @transfer_id = transfer_id
  end

  def call
    resultado = nil
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      recusa = recusa_previa || recusa_da_conversa
      resultado = recusa ? recusar(recusa) : aplicar
    end
    avisar(resultado) if resultado.ok
    resultado
  end

  private

  def recusa_previa
    return :sem_crm unless crm_ligado?
    return :fora_do_funil if Crm::Relacao.fora_do_funil?(@conversation.contact)
    return :funil_invalido unless Crm::Ai::Config.funil_de_destino?(@pipeline, @conversation.inbox)
    return :sem_agente_responsavel if agente.nil?

    :agente_fora_da_caixa if Crm::Ai::Config.agent_inbox_for(inbox: @conversation.inbox, agent: agente).nil?
  end

  # Com a conversa relida dentro do lock: uma pessoa pode ter assumido enquanto o agente pensava. Esperando pessoa é o
  # mesmo critério da aba "Não atribuídas": a passagem do robô à espera de alguém, ou nenhum robô atendendo — sem robô
  # no comando não há a quem entregar a conversa.
  def recusa_da_conversa
    return :pessoa_atribuida if @conversation.assignee_id.present?

    :esperando_pessoa if @conversation.awaiting_person?
  end

  def crm_ligado?
    Crm::Config.enabled? &&
      Crm::InboxSetting.exists?(account_id: @account.id, inbox_id: @conversation.inbox_id, crm_enabled: true)
  end

  def agente
    return @agente if defined?(@agente)

    @agente = Crm::Ai::Config.responsible_agent(inbox: @conversation.inbox, pipeline: @pipeline)
  end

  # Dentro do lock. Abrir ou voltar a outro card troca o assunto atual; o assunto que uma pessoa escolheu há pouco
  # (Crm::Subjects::RESPEITO_AO_FOCO) não é trocado pelo agente (#1260): vira a recusa :assunto_escolhido_por_pessoa.
  # Já estar no funil não troca nada e segue valendo.
  def aplicar
    abertos = Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).to_a.select(&:open?)
    return confirmar(abertos.first) if abertos.first&.pipeline_id == @pipeline.id
    return recusar(:assunto_escolhido_por_pessoa) if pessoa_escolheu_assunto?

    existente = abertos.find { |aberto| aberto.pipeline_id == @pipeline.id }
    if existente
      Crm::Subjects::Acoes.focar(conversation: @conversation, card: existente)
      return concluir(:reaproveitado, existente)
    end

    concluir(:aberto, criar)
  end

  def confirmar(atual)
    concluir(:ja_no_funil, atual)
  end

  def concluir(acao, card)
    registrar(card, acao)
    Resultado.new(ok: true, acao: acao, card: card, pipeline: @pipeline, agente: agente)
  end

  def pessoa_escolheu_assunto?
    Crm::Cards::Focus.pessoa_escolheu?(account_id: @account.id, conversation_id: @conversation.id)
  end

  # Sem escolha recente de pessoa, o Creator já marca o card novo como o assunto atual.
  def criar
    titulo = @resumo.first(Crm::SubjectDecision::MAX_TITLE).presence || @pipeline.name
    Crm::Subjects::Acoes.criar(conversation: @conversation, pipeline: @pipeline, titulo: titulo, source: 'agente')
  end

  def registrar(card, acao)
    payload = { acao: acao.to_s, pipeline_id: @pipeline.id, autonomia_agent_id: agente.id,
                resumo: @resumo.first(MAX_TEXTO), motivo: @motivo.first(MAX_TEXTO), origem: texto(@origem),
                pedido_por: texto(@pedido_por), transfer_id: texto(@transfer_id) }.compact_blank
    Crm::ActivityLogger.new(card: card, actor: nil, event_type: EVENTO, payload: payload, conversation: @conversation).perform
  end

  def texto(valor)
    valor&.to_s&.first(MAX_TEXTO)
  end

  # O agente vai junto quando já foi resolvido (recusa depois de achar o responsável).
  def recusar(recusa)
    Resultado.new(ok: false, pipeline: @pipeline, agente: @agente, recusa: recusa)
  end

  # Depois do commit (também quando quem chamou está numa transação maior): o painel relê os assuntos e o agente
  # responsável recebe a conversa. O card novo é avaliado pela IA do card; a troca de foco já agenda em Focus.
  def avisar(resultado)
    ActiveRecord.after_all_transactions_commit do
      Crm::Cards::Broadcaster.broadcast(resultado.card, evento(resultado.acao)) unless resultado.acao == :ja_no_funil
      Crm::Subjects::Notifier.notify(@conversation)
      Crm::Ai::Observer.new(card: resultado.card).schedule_evaluation if resultado.acao == :aberto
      Crm::Ai::ResponsibleAgentSync.agendar(account_id: @account.id, conversation_id: @conversation.id,
                                            motivo: Crm::Ai::ResponsibleAgentSync::ABRIR)
    end
  end

  def evento(acao)
    acao == :aberto ? Events::Types::CRM_CARD_CREATED : Events::Types::CRM_CARD_UPDATED
  end
end
