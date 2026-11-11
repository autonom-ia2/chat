# "De onde veio" da ficha da pessoa de Relacionamentos (#2895). A lista, quando uma importação CRIOU a pessoa: a linha
# dela com `was_existing_contact` falso (CampaignImports::Importer#mark_row_imported!), numa importação desta conta. A
# data é a de quando a pessoa foi criada, que é quando a importação a trouxe. Senão, o canal da primeira caixa por onde
# ela entrou e quando. Sem nenhum dos dois (criada à mão, sem conversa), nada.
class Relacionamentos::Ficha::Origem
  def initialize(pessoa)
    @pessoa = pessoa
  end

  def call
    da_lista || do_canal
  end

  private

  # A base de campanha antiga não tem nome: leva o da campanha, como em "Origem e campanhas" (ContactOriginsController).
  def da_lista
    lista = CampaignImport.where(account_id: @pessoa.account_id).joins(:campaign_import_rows)
                          .where(campaign_import_rows: { contact_id: @pessoa.id, was_existing_contact: false }).order(:id).first
    { tipo: 'lista', nome: lista.name.presence || lista.campaign_name, quando: @pessoa.created_at.to_i } if lista
  end

  def do_canal
    entrada = @pessoa.contact_inboxes.order(:created_at, :id).preload(inbox: :channel).first
    { tipo: 'canal', canal: Relacionamentos::Ficha::Canal.de(entrada.inbox), quando: entrada.created_at.to_i } if entrada
  end
end
