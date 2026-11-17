# O gatilho da cotação da renovação (E8, #2901): o card de renovação que ACABOU de nascer (Carteira::Renovacao::CriarCard,
# dentro da trava do seguro) pede o começo da cotação. Só o card novo: card recriado, ou outro card da mesma vigência,
# não recota (a trava por vigência fica no Carteira::Cotacao::ComecarJob).
#
# O job entra na fila depois do commit: se a transação do card voltar, nada é pedido. Com o portão fechado (sem a chave,
# sem a carteira, `quem_cota = ninguem`), nada acontece e a renovação é a da E5.
module Carteira::Cotacao::Gatilho
  def self.card_nasceu(account, config, apolice)
    return unless Carteira::Cotacao.aberta?(account, config)

    id = apolice.id
    vigencia = apolice.fim_vigencia.iso8601
    ActiveRecord.after_all_transactions_commit { Carteira::Cotacao::ComecarJob.perform_later(id, vigencia) }
  end
end
