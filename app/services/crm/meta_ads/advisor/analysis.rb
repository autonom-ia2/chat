# O consultor de anúncios de ponta a ponta (#1110, F5, §1.6): Facts (cache) → History → Rules → today →
# Decision, guardado em crm_meta_advisor_runs / _actions, escrito pela IA (Writer + Check) e servido como o
# `Advice` da API (§4.2). Substitui a ação única da F4, escrita pela IA e guardada no Redis.
#
# Um run por conta · dia · idioma · assinatura. A assinatura cobre a versão das regras, a das instruções da IA, a
# conta de anúncios e [tipo, assunto, variante, singulares] de cada ação, na ordem; ficam fora os valores (o render
# usa os atuais; de cada contagem e prazo entra só se é 1, para a concordância) e o status (aceitar não muda a
# assinatura nem pede IA). A conta de anúncios entra porque trocar de conta
# no mesmo dia pode dar a mesma decisão (ações de conta têm assunto `account`), e o run da conta antiga serviria os
# fatos dela. O `GET panel` a cada 2 min, com o run do dia já criado, só lê: cache dos fatos, History, today, um
# find_by e um update_all de `shown_at` que não muda linha. Upsert das ações e expiração das de ontem, só quando
# este processo cria o run, na mesma transação da criação: o run nunca fica visível sem as ações dele.
#
# A escrita (`write!`) nunca segura transação durante a IA: reivindica o run numa troca atômica (update_all com
# condição; `writing` há mais de STALE_WRITING conta como abandonado), só então reserva o teto do dia, chama o
# Writer fora de transação e grava o resultado só se o run ainda é seu. Os horários vêm do Rails (não do now()
# do banco), para a reivindicação seguir o mesmo relógio do resto.
#
# As escritas são por update_all/upsert_all de propósito: a troca de estado com condição é o que torna a
# reivindicação atômica, e o upsert é o único jeito de gravar as ações sem corrida entre duas abas.
# rubocop:disable Rails/SkipsModelValidations
class Crm::MetaAds::Advisor::Analysis
  DAILY_LIMIT = 6
  COUNTER_PREFIX = 'crm:meta_ads:advisor:count'.freeze
  COUNTER_TTL = 36.hours
  STALE_WRITING = 7.minutes
  FILLERS = Crm::MetaAds::Advisor::Decision::FILLERS
  # Os tipos de fato que pedem concordância de número no texto (substantivo depois do valor).
  SINGULAR_TYPES = %i[count days].freeze
  CLAIMABLE = "(writer_status = 'pending' AND (retry_after IS NULL OR retry_after <= :now)) " \
              "OR (writer_status = 'writing' AND writing_started_at < :stale)".freeze

  class << self
    # → Advice. Com trigger 'panel', marca `shown_at` nas ações mostradas, salvo `shown: false` (o pedido veio pelo
    # token de API, como o Guia chama: a métrica de aceite conta só o que o painel mostrou, D5.11).
    def current(connection, locale:, trigger: 'panel', report: nil, shown: true)
      new(connection, locale: locale, report: report).current(trigger, shown: shown)
    end

    # O resumo das 8h: escreve na hora se o run está livre e há vaga no teto.
    def daily(connection, language:)
      analysis = new(connection, locale: language)
      analysis.current('digest')
      run = analysis.run
      write!(run) if claimable?(run) && !limit_reached?(run.account, run.local_date)
      analysis.advice(run.reload)
    end

    def write!(run)
      started = Time.current.floor(6)
      claimed = Crm::MetaAdvisorRun.where(id: run.id).where(CLAIMABLE, now: started, stale: started - STALE_WRITING)
                                   .update_all(writer_status: 'writing', writing_started_at: started, retry_after: nil, updated_at: started)
      return false unless claimed == 1

      outcome = write_outcome(run)
      Crm::MetaAdvisorRun.where(id: run.id, writer_status: 'writing', writing_started_at: started)
                         .update_all(outcome.merge(updated_at: Time.current))
      true
    end

    # O Advice de um run já existente (o job da ação do dia, depois de escrever). Valores atuais quando a decisão
    # de agora é a mesma do run; senão, os guardados nele.
    def serialize(run, locale)
      connection = Crm::MetaAdsConnection.find_by(account_id: run.account_id, ad_account_id: run.ad_account_id)
      new(connection, locale: locale).advice(run)
    end

    # O envio real do resumo das 8h marca a ação que o WhatsApp mostrou.
    def mark_shown!(action_ids)
      Crm::MetaAdvisorAction.where(id: Array(action_ids).compact, shown_at: nil).update_all(shown_at: Time.current, updated_at: Time.current)
    end

    # 'ai_unavailable' | 'credentials_missing' | nil. A credencial é conferida antes de qualquer chamada.
    def unavailable_reason(account)
      return 'ai_unavailable' unless Crm::Ai::Config.enabled?
      return 'credentials_missing' unless Crm::Ai::CredentialResolver.new(account: account).configured?

      nil
    end

    # Só lê o contador: o controller não adia à toa quando o dia já passou do teto.
    def limit_reached?(account, local_date)
      Redis::Alfred.get(counter_key(account.id, local_date)).to_i >= DAILY_LIMIT
    end

    # O motivo para responder pela regra sem passar pela IA, ou nil: IA indisponível, só fillers ou teto do dia.
    def immediate_reason(run)
      unavailable_reason(run.account) || ('not_applicable' if fillers_only?(run)) ||
        ('daily_limit' if limit_reached?(run.account, run.local_date))
    end

    # Fecha um run livre pela regra, com o motivo (§4.4).
    def rule!(run, reason)
      Crm::MetaAdvisorRun.where(id: run.id).where(CLAIMABLE, now: Time.current, stale: Time.current - STALE_WRITING)
                         .update_all(writer_status: 'rule', writer_reason: reason, writing_started_at: nil, retry_after: nil,
                                     updated_at: Time.current)
    end

    def claimable?(run)
      (run.writer_status == 'pending' && (run.retry_after.nil? || run.retry_after <= Time.current)) ||
        (run.writer_status == 'writing' && run.writing_started_at < Time.current - STALE_WRITING)
    end

    def counter_key(account_id, local_date)
      "#{COUNTER_PREFIX}:#{account_id}:#{local_date.iso8601}"
    end

    private

    def write_outcome(run)
      reason = unavailable_reason(run.account) || ('not_applicable' if fillers_only?(run))
      return rule_outcome(reason) if reason
      return rule_outcome('daily_limit') unless reserve!(run)

      actions = run.decision.reject { |action| FILLERS.include?(action['kind']) }
      Crm::MetaAds::Advisor::Writer.new(run: run, actions: actions, facts: run.facts, language: run.locale).perform
    end

    def rule_outcome(reason)
      { writer_status: 'rule', writer_reason: reason, writer_attempts: 0, texts: {}, model: nil, retry_after: nil }
    end

    def fillers_only?(run)
      run.decision.all? { |action| FILLERS.include?(action['kind']) }
    end

    # Uma geração do dia, reservada só depois de reivindicar o run (as duas tentativas do Writer contam uma).
    def reserve!(run)
      key = counter_key(run.account_id, run.local_date)
      count = Redis::Alfred.incr(key)
      Redis::Alfred.expire(key, COUNTER_TTL.to_i) if count == 1
      count <= DAILY_LIMIT
    end
  end

  attr_reader :run

  def initialize(connection, locale:, report: nil)
    @connection = connection
    @locale = locale.to_s
    @report = report
  end

  def current(trigger, shown: true)
    @run = find_or_create_run(trigger)
    payload = advice(@run)
    mark_panel_shown(payload) if trigger == 'panel' && shown
    payload
  end

  def advice(run)
    actions = fresh?(run) ? evaluation[:actions] : run.decision.map(&:deep_symbolize_keys)
    Crm::MetaAds::Advisor::Advice.new(run, actions, today: today_rows(run), locale: @locale).payload
  end

  private

  def evaluation
    @evaluation ||= begin
      facts = Crm::MetaAds::Advisor::Facts.new(@connection, report: @report).payload
      local_date = Date.iso8601(facts[:local_date])
      rules = Crm::MetaAds::Advisor::Rules.evaluate(facts, history: Crm::MetaAds::Advisor::History.for(@connection.account_id, local_date))
      today = Crm::MetaAds::Advisor::History.today(@connection.account_id, local_date)
      actions = Crm::MetaAds::Advisor::Decision.for(facts, rules, today: today)
      { facts: facts, local_date: local_date, rules: rules, today: today, actions: actions, signature: signature(actions) }
    end
  end

  def signature(actions)
    parts = [Crm::MetaAds::Advisor::Rules::RULES_VERSION, Crm::MetaAds::Advisor::Prompt::VERSION, @connection.ad_account_id] +
            actions.map { |action| [action[:kind], action[:subject_key], action[:variant], singulars(action[:facts])] }
    Digest::SHA256.hexdigest(parts.to_json)
  end

  # O texto guardado tem marcadores e é renderizado com o valor atual: "{{count}} propostas" escrito com 4 viraria
  # "1 propostas". Por isso cada contagem e prazo entra na assinatura só como "é 1 ou não" (o valor em si fica fora):
  # cruzar 1 ↔ vários pede texto novo, escrito com o valor que concorda; 4 → 3 mantém o run. Compara o valor como
  # aparece na tela (arredondado, como o Format.integer).
  def singulars(facts)
    facts.to_h.stringify_keys.select { |key, _value| SINGULAR_TYPES.include?(Crm::MetaAds::Advisor::Format::TYPES[key]) }
         .sort.map { |key, value| [key, value.present? && value.to_f.round == 1] }
  end

  def fresh?(run)
    @connection.present? && @connection.ad_account_id == run.ad_account_id && evaluation[:signature] == run.signature &&
      evaluation[:local_date] == run.local_date
  end

  # O `today` lido antes do run vale só se já tem a linha de cada ação: outra aba pode ter criado o run (com as
  # ações) entre essa leitura e o find_by, e a leitura velha daria as ações sem id.
  def today_rows(run)
    return evaluation[:today] if fresh?(run) && !@stored && stored_rows?(evaluation[:today])

    Crm::MetaAds::Advisor::History.today(run.account_id, run.local_date)
  end

  def stored_rows?(today)
    evaluation[:actions].all? { |action| FILLERS.include?(action[:kind]) || today.key?([action[:kind], action[:subject_key]]) }
  end

  # Criação do run e gravação das ações na mesma transação: se o upsert falhar ou o processo cair no meio, nada
  # fica, e a próxima leitura cria tudo. A corrida entre duas abas segue resolvida pelo savepoint do
  # create_or_find_by! (a outra espera o commit desta no índice único e acha o run já com as ações).
  def find_or_create_run(trigger)
    keys = { account_id: @connection.account_id, local_date: evaluation[:local_date], locale: @locale, signature: evaluation[:signature] }
    found = Crm::MetaAdvisorRun.find_by(keys)
    return found if found

    Crm::MetaAdvisorRun.transaction do
      run = Crm::MetaAdvisorRun.create_or_find_by!(keys) { |created| created.assign_attributes(run_attributes(trigger)) }
      store_actions!(run) if run.previously_new_record?
      run
    end
  end

  def run_attributes(trigger)
    {
      ad_account_id: @connection.ad_account_id, rules_version: Crm::MetaAds::Advisor::Rules::RULES_VERSION,
      prompt_version: Crm::MetaAds::Advisor::Prompt::VERSION, trigger: trigger, facts: evaluation[:facts], rules: evaluation[:rules],
      decision: evaluation[:actions].map do |action|
        action.slice(:kind, :subject_key, :variant, :ad_id, :position, :facts).merge(status_at_creation: action[:status])
      end
    }
  end

  # Só na criação do run: vence as abertas dos dias anteriores e grava as ações do dia (o status fica como está).
  def store_actions!(run)
    now = Time.current
    Crm::MetaAdvisorAction.where(account_id: run.account_id, status: :open).where(local_date: ...run.local_date)
                          .update_all(status: Crm::MetaAdvisorAction.statuses[:expired], updated_at: now)
    rows = evaluation[:actions].reject { |action| FILLERS.include?(action[:kind]) }.map do |action|
      { account_id: run.account_id, local_date: run.local_date, run_id: run.id, last_run_id: run.id,
        **action.slice(:kind, :subject_key, :variant, :ad_id, :position, :facts) }
    end
    if rows.any?
      Crm::MetaAdvisorAction.upsert_all(rows, unique_by: :idx_crm_meta_advisor_actions_unique,
                                              update_only: %i[variant ad_id position facts last_run_id])
    end
    @stored = true
  end

  def mark_panel_shown(payload)
    self.class.mark_shown!(payload[:actions].filter_map { |action| action[:id] })
  end
end
# rubocop:enable Rails/SkipsModelValidations
