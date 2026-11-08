class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000

  def perform(object, user = nil, ip = nil)
    # Fork (#2133): a conta é suspensa e as campanhas agendadas param; antes do pré-apagar saem só as tabelas que o
    # barrariam (chave sem cascata para mensagem); o resto do fork sai depois dele, logo antes do destroy!.
    # Ver Autonomia::ExclusaoDaConta.
    exclusao_do_fork = Autonomia::ExclusaoDaConta.new(object) if object.is_a?(Account)
    exclusao_do_fork&.parar_a_conta
    exclusao_do_fork&.antes_do_pre_apagar
    # Pre-purge heavy associations for large objects to avoid
    # timeouts & race conditions due to destroy_async fan-out.
    purge_heavy_associations(object)
    exclusao_do_fork&.perform
    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def heavy_associations
    {
      Account => %i[conversations contacts inboxes reporting_events],
      Inbox => %i[conversations contact_inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end
end

# Exclusão da conta: os contatos não cancelam reunião nem anonimizam cards um a um (#2096, Crm::ContatosSoltamCardsNaExclusaoDaConta).
DeleteObjectJob.prepend(Crm::ContatosSoltamCardsNaExclusaoDaConta)
DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
