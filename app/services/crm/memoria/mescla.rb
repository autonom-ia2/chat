# Mescla de contatos (#1601, C1 da 2ª revisão). O ContactMergeAction apaga o contato absorvido (destroy!) antes de
# avisar a mescla, e os fatos dele têm FK com ON DELETE CASCADE: sem isto, os fatos do absorvido (inclusive a correção
# travada da equipe) sumiriam com ele. Roda dentro de merge_crm_records, na transação da mescla e ANTES do destroy!,
# como os outros registros do CRM.
module Crm::Memoria::Mescla
  module_function

  def mesclar!(account:, absorvido:, fica:)
    agora = Time.current
    # A mesma trava do Gravador no escopo contato, para os dois contatos (na ordem do id): uma gravação ao mesmo tempo
    # não se perde no meio da mescla.
    [absorvido, fica].sort_by(&:id).each { |contato| Crm::Memoria::Gravador.travar_contato(account_id: account.id, contact_id: contato.id) }
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

      resolver!(fato, igual, agora)
    end
  end

  # O mesmo valor: a trava da pessoa passa para a versão que fica e a do absorvido expira. Valor diferente: divergente.
  def resolver!(fato, igual, agora)
    mesmo = Crm::Memoria::Normal.chave(igual.valor) == Crm::Memoria::Normal.chave(fato.valor)
    return fato.update!(situacao: 'divergente', divergente_de_id: igual.id) unless mesmo

    igual.update!(travado: true, travado_por_user_id: fato.travado_por_user_id) if fato.travado? && !igual.travado?
    fato.update!(expirado_em: agora)
  end
end
