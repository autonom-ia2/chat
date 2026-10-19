# chat#1709 (fase 3): assina o `poll.vote` nas sessões híbridas de uma conta com a flag `whatsapp_rich_native`.
# Cada sessão que ainda não assina reinicia UMA vez no motor: rodar num horário escolhido.
#   bundle exec rake whatsapp_hybrid:poll_vote:subscribe ACCOUNT_ID=16            # lista (DRY_RUN)
#   bundle exec rake whatsapp_hybrid:poll_vote:subscribe ACCOUNT_ID=16 APPLY=true # grava agora
namespace :whatsapp_hybrid do
  namespace :poll_vote do
    desc 'Subscribe hybrid sessions of ACCOUNT_ID to poll.vote (restarts each session once). DRY_RUN by default.'
    task subscribe: :environment do
      account_id = Integer(ENV.fetch('ACCOUNT_ID', ''), 10, exception: false)
      abort('[whatsapp_hybrid][poll_vote] ACCOUNT_ID deve ser um inteiro positivo.') unless account_id&.positive?

      apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', nil)) || false
      account = Account.find(account_id)
      abort('[whatsapp_hybrid][poll_vote] a conta não tem a flag whatsapp_rich_native.') unless Waha::RichNative.enabled?(account)

      connections = WhatsappHybrid::Connection.where(account_id: account_id)
      puts("[whatsapp_hybrid][poll_vote] mode=#{apply ? 'APPLY' : 'DRY_RUN'} account_id=#{account_id} sessions=#{connections.count}")
      connections.find_each { |connection| puts("  inbox=#{connection.inbox_id} paused=#{connection.paused?}") }
      next puts('[whatsapp_hybrid][poll_vote] DRY_RUN only. Re-run with APPLY=true.') unless apply

      WhatsappHybrid::RichNative::PollVoteSubscribeJob.perform_now(account_id)
      puts('[whatsapp_hybrid][poll_vote][done] see the log lines "poll vote subscribe" for each inbox.')
    end
  end
end
