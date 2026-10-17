# Memória das IAs (#1601). Backfill da autoria: grava só crm_mensagem_origens, sem os efeitos do evento ao vivo (não fecha
# tarefa, não mexe em fato) e sem regravar a linha corrigida por uma pessoa. Os efeitos só rodam pelo
# Crm::MemoriaListener.
#
#   bundle exec rails 'crm:memoria:origens[16,90]'
namespace :crm do
  namespace :memoria do
    desc 'Grava a autoria (crm_mensagem_origens) das mensagens dos últimos N dias de uma conta'
    task :origens, %i[account_id dias] => :environment do |_task, args|
      account = Account.find(args.fetch(:account_id))
      dias = (args[:dias] || 90).to_i
      config = Crm::Memoria.config(account)
      contagem = Hash.new(0)
      Message.where(account_id: account.id, created_at: dias.days.ago..).includes(:conversation, attachments: { file_attachment: :blob })
             .find_each do |message|
        next if config.caixa_excluida?(message.inbox_id)

        linha = Crm::Memoria::Origem.gravar!(message, config: config)
        contagem[linha&.autor_tipo || 'sem_contato'] += 1
      end
      contagem.sort.each { |autor, total| puts "#{autor}: #{total}" }
    end
  end
end
