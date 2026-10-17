# Mescla de contatos (#1601, C1 da 2ª revisão). O ContactMergeAction apaga o contato absorvido (destroy!) antes de
# avisar a mescla, e a memória dele tem FK com ON DELETE CASCADE: sem isto, a autoria das mensagens (e o que mais a
# memória guardar do absorvido) sumiria com ele. Roda dentro de merge_crm_records, na transação da mescla e ANTES do
# destroy!, como os outros registros do CRM.
module Crm::Memoria::Mescla
  module_function

  def mesclar!(account:, absorvido:, fica:)
    agora = Time.current
    Crm::MensagemOrigem.where(account_id: account.id, contact_id: absorvido.id)
                       .update_all(contact_id: fica.id, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
    conflitos_do_contato!(account, absorvido, fica, agora)
    Crm::MemoriaFato.where(account_id: account.id, contact_id: absorvido.id)
                    .update_all(contact_id: fica.id, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
  end

  # Fato do CLIENTE com a mesma chave nos dois contatos, ANTES de mover (senão o índice de vigente estoura e desfaz a
  # mescla inteira): o mesmo valor, a versão do absorvido expira; valor diferente, a do absorvido vira divergente da
  # que fica ("confirmar"). A correção travada da equipe nunca some: ou fica como está, ou vira divergente visível.
  def conflitos_do_contato!(account, absorvido, fica, agora)
    vigentes = Crm::MemoriaFato.vigentes.where(account_id: account.id, escopo: 'contato').where.not(tipo: 'decisao')
    dos_que_ficam = vigentes.where(contact_id: fica.id).index_by { |fato| [fato.chave, fato.item_ref] }
    vigentes.where(contact_id: absorvido.id).find_each do |fato|
      igual = dos_que_ficam[[fato.chave, fato.item_ref]]
      next if igual.nil?

      mesmo = Crm::Memoria::Normal.chave(igual.valor) == Crm::Memoria::Normal.chave(fato.valor)
      fato.update!(mesmo ? { expirado_em: agora } : { situacao: 'divergente', divergente_de_id: igual.id })
    end
  end
end
