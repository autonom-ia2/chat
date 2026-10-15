# Quem atende, no agente: `operating?` (ativo e ligado), `atende_cliente?` e — #1366 — `tem_onde_trabalhar?`.
# O agente não fica atendendo (active + enabled) sem ter onde trabalhar.
#
# `tem_onde_trabalhar?` é o PREDICADO ÚNICO: a validação de ativar, a parada automática e a tela (jbuilder `_agent`)
# leem daqui. O agente tem onde trabalhar quando:
# - é interno (Copiloto da equipe): trabalha dentro do painel, sem caixa;
# - tem vínculo ativo numa caixa da conta, de porta ou de área (#1433). O `both` segue a regra do externo.
# O ajudante (#1434) é um agente interno marcado pelo vínculo (`vinculos_de_ajudante`): já entra pelo primeiro "ou".
#
# Ativar sem onde trabalhar é recusado em toda atualização; na criação, só no contexto :ativacao (a API,
# AgentsController#create, e o QuoteAgent::Builder, #1525). Os outros nascimentos não atendem: rascunho (Builder) e
# interno (Guia). O Agente de Cotação nasce parado desde o #1525. Começar a atender num canal é o InboxConnector com
# `ativar`, que cria o vínculo e liga o agente na mesma transação.
module Autonomia::Agents::OndeTrabalhar
  extend ActiveSupport::Concern

  # Os campos que decidem se o agente atende. Mudando algum, quem grava trava o agente antes (AgentsController#update).
  CAMPOS_DE_ATENDIMENTO = %w[status enabled actuation].freeze
  # A marca de origem do ajudante (tema 14), em `config['papel']`. Só nasce pelo início do Construtor com
  # `papel: 'ajudante'` (BuildThread); a API do agente não a aceita (`AgentsController::RESERVED_CONFIG_KEYS`).
  PAPEL_AJUDANTE = 'ajudante'.freeze

  included do
    validate :atender_exige_onde_trabalhar, on: %i[update ativacao], if: :passa_a_atender?

    # Tema 14 (#1434) — o AJUDANTE: um agente interno que outro agente consulta (o `Specialist` que aponta para ele).
    # Interno já tem onde trabalhar (`tem_onde_trabalhar?`), já não fala com cliente e já não aceita caixa. Só vira
    # ajudante quem NASCEU como ajudante (`ajudante_de_origem?`, decisão do Rodrigo em 14/10): um Copiloto da equipe
    # nunca. O banco cascateia; o caminho normal é o soft delete, que só o tira do turno.
    has_many :vinculos_de_ajudante, class_name: 'Autonomia::Agents::Specialist', foreign_key: :delegate_agent_id,
                                    inverse_of: :delegate, dependent: :delete_all

    # Os copilotos que a equipe escolhe na conversa: internos ou ambos, ligados, com instrução, fora os de sistema (o
    # Guia) e fora os ajudantes (a marca de origem) — esses trabalham para outro agente, não para a equipe.
    scope :copilotos_da_equipe, lambda {
      where(actuation: %i[internal both], status: :active, enabled: true)
        .where.not(instruction: [nil, '']).where("config->>'system_key' IS NULL")
        .where("config->>'papel' IS DISTINCT FROM ?", PAPEL_AJUDANTE)
    }
  end

  class_methods do
    def muda_atendimento?(attrs)
      attrs.keys.map(&:to_s).intersect?(CAMPOS_DE_ATENDIMENTO)
    end
  end

  # Mesmo predicado de Operate.authorized_agent_inbox e do InboxConnector#connect!.
  def operating?
    !deleted? && enabled? && active?
  end

  # Pode falar com cliente agora: atendendo, não interno (copiloto) e não de sistema (o Guia). É o mesmo predicado
  # do agente em Operate.authorized_agent_inbox, sem a allowlist de teste, que depende da conversa (#1433).
  def atende_cliente?
    operating? && !actuation_internal? && config&.dig('system_key').blank?
  end

  # Nasceu como "Ajuda outros agentes": só este agente pode ser ajudante.
  def ajudante_de_origem?
    config.to_h['papel'] == PAPEL_AJUDANTE
  end

  def tem_onde_trabalhar?
    actuation_internal? || vinculo_ativo_numa_caixa?
  end

  # Saiu o último vínculo: o agente para (paused + enabled false). Chamado só pelo AgentInbox, quando `vinculo` sai da
  # caixa (destroy ou arquivamento).
  # - TRAVA O AGENTE antes de reler os vínculos: duas saídas ao mesmo tempo (caixas diferentes) não veem, cada uma, o
  #   vínculo da outra e deixam o agente atendendo sem nada. Quem chama já trava o agente antes da caixa
  #   (InboxConnector#disconnect!, Areas, SoftDelete): a ordem é sempre agente → caixa.
  # - `update_columns` e não `update!`: validação antiga do agente (público-alvo, tom, página da agenda gravados antes
  #   de uma regra nova) faria o `update!` recusar, e a caixa não conseguiria soltar o agente. O que o callback do
  #   `update!` faria (sync_mirror_bots) é chamado aqui à mão, para o espelho seguir o estado.
  def parar_se_sem_onde_trabalhar!(vinculo: nil)
    with_lock do
      next if deleted? || !(active? || enabled?)

      agent_inboxes.reset # o vínculo acabou de sair: lê do banco, nunca da associação carregada antes
      next if tem_onde_trabalhar?

      update_columns(status: self.class.statuses[:paused], enabled: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      sync_mirror_bots
      registrar_parada(vinculo)
    end
  end

  private

  # Lê a associação já carregada (a lista do index pré-carrega os vínculos, sem N+1); senão, consulta. Só vínculos desta
  # conta contam, como defesa: o AgentInbox já recusa vínculo de outra conta.
  def vinculo_ativo_numa_caixa?
    papeis = ::Autonomia::Agents::AgentInbox::PAPEIS
    if agent_inboxes.loaded?
      return agent_inboxes.any? { |vinculo| vinculo.deleted_at.nil? && vinculo.account_id == account_id && papeis.include?(vinculo.papel) }
    end

    agent_inboxes.kept.exists?(account_id: account_id, papel: papeis)
  end

  # Vai ficar atendendo depois deste save, e algo que decide isso mudou (inclusive deixar de ser interno).
  def passa_a_atender?
    return false if deleted? || !(active? && enabled?)

    will_save_change_to_status? || will_save_change_to_enabled? || will_save_change_to_actuation?
  end

  # Só metadados (ids e papel), nunca conteúdo: o evento existe para a página e o suporte verem por que o agente parou.
  def registrar_parada(vinculo)
    events.create!(account_id: account_id, event_type: :parado_sem_onde_trabalhar,
                   metadata: { motivo: 'sem_onde_trabalhar', vinculo_id: vinculo&.id, inbox_id: vinculo&.inbox_id,
                               papel: vinculo&.papel }.compact)
  end

  def atender_exige_onde_trabalhar
    agent_inboxes.reset # o vínculo pode ter nascido agora (InboxConnector com ativar): lê do banco
    errors.add(:base, I18n.t('autonomia.agents.sem_onde_trabalhar')) unless tem_onde_trabalhar?
  end
end
