# "Apagar" da Lista nova de Relacionamentos (#2894): apaga cada pessoa marcada pelo serviço do lote de hoje
# (Contacts::BulkDeleteService), que é quem aplica a LGPD do #2096 (card sem dado pessoal, reunião futura cancelada e a
# linha na Auditoria). Chamado pessoa por pessoa, para a resposta dizer quantas saíram e quem ficou.
#
# A pessoa que o serviço não deixou sair fica inteira e "de fora"; o porquê dela ele grava na Auditoria da conta. Quem
# já tinha sido apagada por outro pedido conta como apagada: é o que a tela pediu.
class Relacionamentos::Apagar < Relacionamentos::AcaoEmGrupo
  NAO_APAGADA = 'nao_apagada'.freeze

  # O Guia não apaga as pessoas marcadas por ninguém (`Guide::Acoes::SO_NA_TELA`): é excluir contato, em lote, e isso
  # só se faz na tela (#2096). A resposta do Guia é a mesma de excluir um contato.
  SO_NA_TELA_DO_GUIA = { 'POST relacionamentos/apagar' => 'contact_delete' }.freeze

  private

  def contagem
    :apagadas
  end

  def fazer(pessoa_id)
    Contacts::BulkDeleteService.new(account: @account, contact_ids: [pessoa_id], user: @user).perform
    NAO_APAGADA if @account.contacts.exists?(id: pessoa_id)
  end
end
