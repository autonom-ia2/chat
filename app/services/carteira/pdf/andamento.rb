# A leitura do PDF anexado a um seguro (E6.2, #2899), como a tela pergunta até ela terminar:
#   { leituraId:, estado: 'lendo' }
#   { leituraId:, estado: 'lido', outraApolice:, mudancas: [...] }        (Carteira::Pdf::OQueMudou)
#   { leituraId:, estado: 'recusado', recusa: 'nao_e_apolice' }
#   { leituraId:, estado: 'falhou', recusa: 'nao_deu_para_ler' }
# A leitura é procurada só entre as do anexar deste seguro, na conta dele; a que não existe mais (guardada, ou que saiu
# na limpeza) responde `leitura_expirou`. O item que passou do tempo limite na fila conta como `falhou`, mesmo antes de
# o job chegar a ele (Carteira::LerItem::PRAZO): a tela nunca espera para sempre.
class Carteira::Pdf::Andamento
  NAO_E_APOLICE = Carteira::Leitor::Resultado::NAO_E_APOLICE
  NAO_DEU = Carteira::Leitor::Resultado::NAO_DEU

  def initialize(apolice, leitura_id)
    @apolice = apolice
    @leitura_id = leitura_id
  end

  def call
    item = Carteira::LeituraItem.where(leitura_id: Carteira::Leitura.do_anexar.select(:id))
                                .find_by(leitura_id: @leitura_id, account_id: @apolice.account_id, apolice_id: @apolice.id)
    raise CustomExceptions::CarteiraRecusa, 'leitura_expirou' unless item

    { leituraId: item.leitura_id }.merge(do_item(item))
  end

  private

  def do_item(item)
    case item.estado
    when 'lido' then { estado: 'lido' }.merge(Carteira::Pdf::OQueMudou.new(@apolice, item).call)
    when 'recusado' then { estado: 'recusado', recusa: NAO_E_APOLICE }
    when 'lendo' then demorou?(item) ? falhou : { estado: 'lendo' }
    else falhou
    end
  end

  def demorou?(item)
    item.created_at < Carteira::LerItem::PRAZO.ago
  end

  def falhou
    { estado: 'falhou', recusa: NAO_DEU }
  end
end
