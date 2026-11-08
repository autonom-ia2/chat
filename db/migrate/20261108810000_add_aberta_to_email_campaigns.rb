# #2717: campanha de e-mail aberta. A lista segue o Público depois do primeiro envio: quem entra depois também
# recebe, uma vez, pela régua de sempre (recusa, supressão, higiene). Nasce falsa em todas as que já existem.
class AddAbertaToEmailCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :email_campaigns, :aberta, :boolean, default: false, null: false
  end
end
