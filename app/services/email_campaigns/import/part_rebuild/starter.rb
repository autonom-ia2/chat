# The click on "Refazer para editar" (#1099, delivery D). Refused, with a code the screen explains, when the AI is not
# configured for the account, the import is not ready, the part is no longer an image, the part was already sent once
# (each part goes to the AI at most once: the cost of a second try is the person's other ways out), the import already
# sent MAX_PER_IMPORT parts, or the account reached its monthly Quota. Otherwise the part is counted — the import under
# its row lock, the month atomically — marked running with a fresh token and handed to RebuildJob.
class EmailCampaigns::Import::PartRebuild::Starter
  def self.call(import, target)
    new(import, target.to_s).call
  end

  def initialize(import, target)
    @import = import
    @target = target
  end

  def call
    refuse(:ai_not_configured) unless EmailCampaigns::Import::PartRebuild.available?(@import.account)

    token = SecureRandom.hex(12)
    @import.with_lock do
      check!
      period = EmailCampaigns::Import::PartRebuild::Quota.take(@import.account)
      refuse(:rebuild_month_limit) if period.nil?

      entry = { 'status' => EmailCampaigns::Import::PartRebuild::RUNNING, 'token' => token, 'period' => period.iso8601,
                'started_at' => Time.current.iso8601 }
      @import.update!(rebuilds: @import.rebuilds.merge(@target => entry))
    end
    EmailCampaigns::Import::RebuildJob.perform_later(@import.id, @target, token)
    @import
  end

  private

  def check!
    refuse(:not_ready) unless @import.status == 'ready'
    refuse(:fix_gone) unless EmailCampaigns::Import::Fixer.parts(@import, @import.result_mjml.to_s).any? { |part| part[:id] == @target }
    check_count!
  end

  def check_count!
    state = EmailCampaigns::Import::PartRebuild.view(@import)[@target]
    refuse(:rebuild_running) if state && state[:status] == EmailCampaigns::Import::PartRebuild::RUNNING
    refuse(:rebuild_used) if state
    refuse(:rebuild_limit) if @import.rebuilds.size >= EmailCampaigns::Import::PartRebuild::MAX_PER_IMPORT
  end

  def refuse(code)
    raise EmailCampaigns::Import::Error, code
  end
end
