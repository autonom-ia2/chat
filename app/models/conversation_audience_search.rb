# "Novo público pedindo em palavras" (#2277): one request written by the person, read against the account's
# conversations by the account's own AI.
#
# planning → question (the planner needs one answer) → planned → queued → reading → done.
# A reading search can also end in stopped (the person), ceiling (the agreed cost was reached) or failed (the AI
# stopped answering, or the key is gone); the three resume from the next pending batch. saved is the end: the list
# became a campaign_imports audience.
class ConversationAudienceSearch < ApplicationRecord
  PLANNING = 'planning'.freeze
  QUESTION = 'question'.freeze
  PLANNED = 'planned'.freeze
  QUEUED = 'queued'.freeze
  READING = 'reading'.freeze
  DONE = 'done'.freeze
  STOPPED = 'stopped'.freeze
  CEILING = 'ceiling'.freeze
  FAILED = 'failed'.freeze
  SAVED = 'saved'.freeze
  STATUSES = [PLANNING, QUESTION, PLANNED, QUEUED, READING, DONE, STOPPED, CEILING, FAILED, SAVED].freeze
  RUNNING = [QUEUED, READING].freeze
  RESUMABLE = [STOPPED, CEILING, FAILED].freeze
  # Working on the account's key right now: the planner or the readers.
  BUSY = [PLANNING, *RUNNING].freeze

  # The period keys the screen offers, and how far back each one reaches (nil: every conversation).
  PERIODS = { '7d' => 7.days, '30d' => 30.days, '3m' => 3.months, '12m' => 12.months, 'all' => nil }.freeze
  REQUEST_MAX = 1000

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :campaign_import, optional: true
  has_many :batches, class_name: 'ConversationAudienceBatch', foreign_key: :search_id, inverse_of: :search, dependent: :delete_all
  has_many :people, class_name: 'ConversationAudiencePerson', foreign_key: :search_id, inverse_of: :search, dependent: :delete_all

  validates :request, presence: true, length: { maximum: REQUEST_MAX }
  validates :period, inclusion: { in: PERIODS.keys }
  validates :status, inclusion: { in: STATUSES }

  # A running search whose job was lost (process killed between waves): no heartbeat for LOST_AFTER. The same for
  # a planning search whose PlanJob was lost.
  LOST_AFTER = 10.minutes

  def running? = RUNNING.include?(status)
  def resumable? = RESUMABLE.include?(status)

  # Conditional status change: only while the search is still in `from`, so a "Parar" clicked while a job runs is
  # never overwritten (and the job never moves a search the person already stopped). With `token`, only while the
  # search still belongs to that chain of ReadJob. -> true when it moved.
  def self.move(id, from:, to:, token: nil, **attributes)
    scope = where(id: id, status: from)
    scope = scope.where(run_token: token) if token
    scope.update_all(attributes.merge(status: to, updated_at: Time.current)) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # Each start or resume hands the reading to ONE chain of ReadJob, with a new token: a job of an older chain (a
  # repeated click, a revived search) finds another token and ends, so a search never has two chains requeueing
  # themselves. -> the token, or nil when the search was not in `from`.
  def self.queue!(id, from:, **attributes)
    token = SecureRandom.hex(8)
    move(id, from: from, to: QUEUED, run_token: token, **attributes) ? token : nil
  end

  # A lost running search gets a new chain once: only the call that moves the old heartbeat takes it. -> token or nil.
  def self.revive(id)
    token = SecureRandom.hex(8)
    lost = where(id: id, status: RUNNING).where('COALESCE(heartbeat_at, updated_at) < ?', LOST_AFTER.ago)
    lost.update_all(run_token: token, heartbeat_at: Time.current) == 1 ? token : nil # rubocop:disable Rails/SkipsModelValidations
  end

  # A planning search whose PlanJob was lost is planned again, once. -> true when this call took it.
  def self.replan(id)
    lost = where(id: id, status: PLANNING).where(updated_at: ...LOST_AFTER.ago)
    lost.update_all(updated_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def since
    PERIODS[period]&.ago
  end

  # The bell (#2277): the notification points here; the screen opens the search by its id.
  def push_event_data
    { id: id, name: plan['name'], status: status }
  end
end
