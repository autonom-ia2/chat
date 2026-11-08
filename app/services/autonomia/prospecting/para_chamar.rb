# A fila "Para chamar" da Prospecção nova (#2697, F5): uma empresa por vez, a de melhor chance primeiro.
#
# Quem entra (decisão do Rodrigo, 08/11, opção A): só as empresas ainda não tratadas. O lead que a pessoa vê (o
# leads_scope do controller, pela Visibility), com status new_lead, sem recusa de contato, sem card no funil, que não
# está fechado no cadastro do governo e que tem telefone. Fica de fora, até o dia seguinte, a empresa que a própria
# pessoa marcou como "Depois".
#
# Ordem: a prioridade da busca (priority_score), da maior para a menor; é ela que dá a chance da tela (acharChance.js:
# boa, média, pouca), então as de boa chance vêm primeiro. Sem prioridade, no fim. Empate, pelo id.
#
# "Depois" vale por pessoa e é guardado no próprio lead, sem migration: metadata['para_chamar']['depois'][user_id] =
# o dia (no fuso da conta) em que a pessoa apertou. A empresa volta para essa pessoa no dia seguinte. A escrita mexe só
# nessa chave, sem reescrever o resto do metadata (o mesmo padrão de LeadWorkQueue.mark_whatsapp_queued).
class Autonomia::Prospecting::ParaChamar
  MAX_LEADS = 100
  ACTIVE_REGISTRATION = 'ATIVA'.freeze

  # Fechado no cadastro do governo, com a mesma regra da tela (acharLead.js, motivoDeFora → 'fechou'): a situação da
  # empresa confirmada pela pesquisa (Research::Payload.company: o retrato no metadata do lead, senão o perfil), quando
  # existe e não é ATIVA.
  CLOSED_SQL = <<~SQL.squish.freeze
    autonomia_prospecting_leads.company_research_status IN ('confirmed', 'possible')
    AND autonomia_prospecting_leads.company_profile_id IS NOT NULL
    AND UPPER(COALESCE(NULLIF(
      CASE
        WHEN jsonb_typeof(autonomia_prospecting_leads.metadata #> '{research,company}') = 'object'
             AND autonomia_prospecting_leads.metadata #> '{research,company}' <> '{}'::jsonb
          THEN autonomia_prospecting_leads.metadata #>> '{research,company,registration_status}'
        ELSE (SELECT profiles.registration_status FROM autonomia_prospecting_company_profiles profiles
              WHERE profiles.id = autonomia_prospecting_leads.company_profile_id)
      END, ''), '#{ACTIVE_REGISTRATION}')) <> '#{ACTIVE_REGISTRATION}'
  SQL

  POSTPONED_SQL = "COALESCE(autonomia_prospecting_leads.metadata #>> ARRAY['para_chamar', 'depois', ?], '') >= ?".freeze

  ORDER_SQL = 'autonomia_prospecting_leads.priority_score DESC NULLS LAST, autonomia_prospecting_leads.id ASC'.freeze

  # O objeto em `chave` do jsonb, ou um objeto vazio quando falta ou não é objeto.
  OBJECT_AT = "CASE WHEN jsonb_typeof(metadata #> '%<path>s') = 'object' THEN metadata #> '%<path>s' ELSE '{}'::jsonb END".freeze

  POSTPONE_SQL = <<~SQL.squish.freeze
    metadata = metadata || jsonb_build_object('para_chamar',
      #{format(OBJECT_AT, path: '{para_chamar}')} || jsonb_build_object('depois',
        #{format(OBJECT_AT, path: '{para_chamar,depois}')} || jsonb_build_object(?::text, ?::text))),
    updated_at = ?
  SQL

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # `scope`: os leads que a pessoa vê (leads_scope do controller).
  def leads(scope)
    scope.where(status: :new_lead, consent_refused_at: nil, crm_card_id: nil)
         .where.not(phone: [nil, ''])
         .where.not(CLOSED_SQL)
         .where.not(self.class.sanitize(POSTPONED_SQL, @user.id.to_s, today.iso8601))
         .order(Arel.sql(ORDER_SQL))
         .limit(MAX_LEADS)
  end

  # "Depois": some da fila desta pessoa até amanhã.
  def postpone!(lead)
    lead.class.where(id: lead.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      [POSTPONE_SQL, @user.id.to_s, today.iso8601, Time.current]
    )
    today
  end

  # O "Desfazer" do "Depois": tira só a marca desta pessoa.
  def resume!(lead)
    lead.class.where(id: lead.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["metadata = metadata #- ARRAY['para_chamar', 'depois', ?], updated_at = ?", @user.id.to_s, Time.current]
    )
  end

  # O dia de hoje no fuso da conta (o mesmo do CRM e do painel), nunca no do servidor.
  def today
    Time.current.in_time_zone(Crm::Timezone::Resolver.new(account: @account).name_or_default).to_date
  end

  def self.sanitize(sql, *values)
    Autonomia::Prospecting::Lead.sanitize_sql_array([sql, *values])
  end
end
