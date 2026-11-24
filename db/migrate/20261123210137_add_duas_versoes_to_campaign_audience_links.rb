# #3099 (F3 do épico #3095): duas versões da mensagem, na campanha com público e no passo de mensagem da Automação livre.
# Uma migration para a fase inteira (campanha agora, automação no PR seguinte).
#
# Campanha (`campaign_audience_links`, tabela do fork; o Chatwoot não ganha coluna):
# - `teste_criterio`: nil = campanha sem duas versões; 'respostas' | 'compras' | 'eu_escolho';
# - `teste_divisao`: a parte do teste que vai para a versão 1 (50 ou 70); `teste_espera_horas`: 2, 4 ou 24;
# - `teste_estado`: 'testando' | 'esperando_voce' | 'escolhida' | 'todos' (público pequeno: todos recebem uma das duas);
# - `teste_resto`: quantas pessoas ficam para depois do teste (o plano; depois da escolha, quantas foram de fato);
# - `teste_escolhe_em`: primeiro envio do teste + espera, gravado pelo cron quando o teste começa a sair;
# - `teste_vencedora`, `teste_escolhida_por` ('sistema' | 'voce' | 'empate'), `teste_escolhida_por_user_id`,
#   `teste_escolhida_em`: a escolha. O id de quem escolheu fica sem chave estrangeira (só mostra quem foi; a tabela de
#   usuários não leva trava por uma coluna de leitura rara);
# - `segunda_versao`: o que muda na versão 2, por canal ({ message_body } | { template_name, template_language,
#   message } | { subject }).
#
# `campaign_version_contacts`: quem recebeu qual versão, uma linha por pessoa ('teste' no sorteio, 'resto' na escolha).
#
# Automação livre (lidas e escritas no PR da automação):
# - `autonomia_automacao_versoes_envios`: qual versão cada execução mandou num passo;
# - `autonomia_automacao_versoes_vencedoras`: a versão que ficou, por automação e passo (`teste_desde` zera o teste
#   quando o texto muda).
#
# Colunas com default constante e tabelas novas vazias: sem reescrever tabela e sem trava longa. Nenhum job é enfileirado
# aqui (blue/green): a escolha da vencedora roda pelo cron (CampaignJourney::EscolherVencedoraJob).
class AddDuasVersoesToCampaignAudienceLinks < ActiveRecord::Migration[7.2]
  def change
    add_colunas_da_campanha
    create_campaign_version_contacts
    create_versoes_envios
    create_versoes_vencedoras
  end

  private

  def add_colunas_da_campanha
    add_column :campaign_audience_links, :teste_criterio, :string
    add_column :campaign_audience_links, :teste_divisao, :integer, null: false, default: 50
    add_column :campaign_audience_links, :teste_espera_horas, :integer, null: false, default: 4
    add_column :campaign_audience_links, :teste_estado, :string
    add_column :campaign_audience_links, :teste_resto, :integer, null: false, default: 0
    add_column :campaign_audience_links, :teste_escolhe_em, :datetime
    add_column :campaign_audience_links, :teste_vencedora, :integer
    add_column :campaign_audience_links, :teste_escolhida_por, :string
    add_column :campaign_audience_links, :teste_escolhida_por_user_id, :bigint
    add_column :campaign_audience_links, :teste_escolhida_em, :datetime
    add_column :campaign_audience_links, :segunda_versao, :jsonb, null: false, default: {}
  end

  def create_campaign_version_contacts
    create_table :campaign_version_contacts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :campaign_audience_link, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.integer :versao, null: false
      t.string :fase, null: false
      t.datetime :created_at, null: false
      t.index %i[campaign_audience_link_id contact_id], unique: true, name: 'idx_campaign_version_contacts_link_contact'
      t.index %i[campaign_audience_link_id versao fase], name: 'idx_campaign_version_contacts_link_versao'
    end
  end

  def create_versoes_envios
    create_table :autonomia_automacao_versoes_envios do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes, on_delete: :cascade }, index: false
      t.string :passo, null: false
      t.references :execucao, foreign_key: { to_table: :autonomia_automacao_execucoes, on_delete: :nullify }
      t.string :alvo_type, null: false
      t.bigint :alvo_id, null: false
      t.references :contact, foreign_key: { on_delete: :cascade }
      t.integer :versao, null: false
      t.datetime :created_at, null: false
      t.index %i[automacao_id passo versao], name: 'idx_autonomia_automacao_versoes_envios_passo'
    end
  end

  def create_versoes_vencedoras
    create_table :autonomia_automacao_versoes_vencedoras do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes, on_delete: :cascade }, index: false
      t.string :passo, null: false
      t.integer :vencedora
      t.string :escolhida_por
      t.references :escolhida_por_user, foreign_key: { to_table: :users, on_delete: :nullify },
                                        index: { name: 'idx_autonomia_automacao_vencedoras_user' }
      t.datetime :escolhida_em
      t.datetime :teste_desde, null: false
      t.timestamps
      t.index %i[automacao_id passo], unique: true, name: 'idx_autonomia_automacao_vencedoras_passo'
    end
  end
end
