json.extract! stage, :id, :account_id, :pipeline_id, :name, :description, :color, :position,
              :win_probability, :wip_limit, :sla_seconds, :sla_warning_seconds,
              :is_won_stage, :is_lost_stage, :metadata, :created_at, :updated_at
# Only the index view (funnel-edit drawer) passes this local — show/create/update responses
# don't need it, so it's omitted there instead of forcing an extra count query.
json.total_cards_count total_cards_count if local_assigns.key?(:total_cards_count)
