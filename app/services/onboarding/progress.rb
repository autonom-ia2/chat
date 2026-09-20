# Calcula o progresso da trilha de onboarding pelo estado real da conta.
# Nenhum passo é marcado por clique: cada regra pergunta ao banco se aquilo
# realmente aconteceu. As consultas usam `exists?`, que vira `SELECT 1 ... LIMIT 1`.
class Onboarding::Progress
  PULADOS_KEY = 'onboarding_passos_pulados'.freeze

  REGRAS = {
    perfil_configurado: :perfil_configurado?,
    chave_ia_conectada: :chave_ia_conectada?,
    canal_recebendo: :canal_recebendo?,
    primeira_resposta_enviada: :primeira_resposta_enviada?,
    funil_em_uso: :funil_em_uso?,
    equipe_convidada: :equipe_convidada?,
    agente_ia_publicado: :agente_ia_publicado?,
    campanha_criada: :campanha_criada?,
    configuracoes_iniciadas: :configuracoes_iniciadas?
  }.freeze

  def initialize(account:, user: nil, perfil: 'administrator')
    @account = account
    @user = user
    @perfil = perfil.to_s
  end

  # [{ id:, ordem:, titulo:, por_que:, rota:, alvo_destaque:, video:, artigo:,
  #    pulavel:, pre_requisitos:, status: 'pendente'|'feito'|'pulado' }]
  def perform
    Onboarding::Trail.para_perfil(@perfil).map { |passo| linha(passo) }
  end

  def pular(passo_id)
    passo = Onboarding::Trail.find(passo_id)
    raise ArgumentError, 'passo desconhecido' if passo.blank?
    raise ArgumentError, 'passo não pode ser pulado' unless passo.pulavel?

    gravar_pulados(pulados | [passo.id])
    passo.id
  end

  def retomar(passo_id)
    passo = Onboarding::Trail.find(passo_id)
    raise ArgumentError, 'passo desconhecido' if passo.blank?

    gravar_pulados(pulados - [passo.id])
    passo.id
  end

  private

  def linha(passo)
    {
      id: passo.id,
      ordem: passo.ordem,
      titulo: passo.titulo,
      por_que: passo.por_que,
      rota: passo.rota,
      alvo_destaque: passo.alvo_destaque,
      video: passo.video,
      artigo: passo.artigo,
      pulavel: passo.pulavel?,
      pre_requisitos: passo.pre_requisitos,
      status: status(passo)
    }
  end

  def status(passo)
    return 'feito' if send(REGRAS.fetch(passo.verificacao.to_sym))
    return 'pulado' if passo.pulavel? && pulados.include?(passo.id)

    'pendente'
  end

  def pulados
    @pulados ||= Array((@account.custom_attributes || {})[PULADOS_KEY])
  end

  def gravar_pulados(lista)
    @account.update!(custom_attributes: (@account.custom_attributes || {}).merge(PULADOS_KEY => lista.uniq))
    @pulados = lista.uniq
  end

  # Passo 0: avisos do navegador ligados para quem está vendo a tela.
  def perfil_configurado?
    return false if @user.blank?

    NotificationSubscription.exists?(user_id: @user.id)
  end

  # Passo 1: integração CRM Kanban IA ligada com chave gravada.
  def chave_ia_conectada?
    Crm::Ai::CredentialResolver.new(account: @account).configured?
  end

  # Passo 2: caixa criada E mensagem de cliente chegando nela.
  def canal_recebendo?
    @account.inboxes.exists? && @account.messages.exists?(message_type: :incoming)
  end

  # Passo 3: resposta enviada por uma pessoa pelo painel, não por robô.
  def primeira_resposta_enviada?
    @account.messages.exists?(message_type: :outgoing, sender_type: 'User')
  end

  # Passo 4: funil com caixa ligada e pelo menos um card.
  def funil_em_uso?
    Crm::PipelineInbox.exists?(pipeline_id: pipelines_da_conta) && Crm::Card.exists?(account_id: @account.id)
  end

  # Passo 5: mais alguém além de quem criou a conta.
  def equipe_convidada?
    @account.account_users.where.not(role: nil).limit(2).count > 1
  end

  # Passo 6: agente de IA ativo e ligado a uma caixa.
  def agente_ia_publicado?
    return false unless defined?(Autonomia::Agents::Agent)

    agentes = Autonomia::Agents::Agent.where(account_id: @account.id, status: :active).select(:id)
    Autonomia::Agents::AgentInbox.where(account_id: @account.id, autonomia_agent_id: agentes).where.not(inbox_id: nil).exists?
  end

  # Passo 7: campanha de WhatsApp ou de e-mail criada.
  def campanha_criada?
    @account.campaigns.exists? || EmailCampaign.exists?(account_id: @account.id)
  end

  # Passo 8: conta ganhou cara própria — etiqueta ou resposta pronta.
  def configuracoes_iniciadas?
    @account.labels.exists? || @account.canned_responses.exists?
  end

  def pipelines_da_conta
    Crm::Pipeline.where(account_id: @account.id).select(:id)
  end
end
