require 'rails_helper'

# O "para cada item" (#2414 G24, #2771) no salvar: o esquema, as conferências do próprio passo (ProblemasDoParaCada) e os
# valores que ele deixa para os passos seguintes (`ia.<id>.quantos`, `ia.<id>.nomes`).
RSpec.describe Autonomia::Automacao::Receita, :automacao_motor do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:etapa) { create_crm_pipeline(account: account, user: admin, name: 'Inclusões').last }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos', 'automacao_mensagens')
  end

  def para_cada(**mudancas)
    { 'id' => 'lista', 'tipo' => 'para_cada', 'descricao' => 'Cada funcionário novo da lista',
      'campos' => [{ 'chave' => 'nome', 'descricao' => 'Nome completo' }, { 'chave' => 'telefone', 'descricao' => 'WhatsApp' }],
      'etapa_id' => etapa.id, 'maximo' => 20 }.merge(mudancas.transform_keys(&:to_s))
  end

  def mensagem(caminho) = { 'id' => 'oi', 'tipo' => 'mensagem', 'texto' => ['Recebi ', { '$valor' => caminho }, ' nomes'] }

  def receita(*passos) = { 'gatilho' => { 'tipo' => 'mensagem.criada' }, 'passos' => passos }

  def problemas(*passos, account_user: nil) = described_class.new(receita(*passos), conta: account, account_user: account_user).problemas

  def erro(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  it 'aceita o passo e os valores que ele deixa, depois dele', :aggregate_failures do
    receita = receita(para_cada, mensagem('ia.lista.quantos'), mensagem('ia.lista.nomes').merge('id' => 'oi2'))

    expect(described_class.esquema_valido?(receita)).to be(true)
    expect(problemas(*receita['passos'], account_user: account.account_users.find_by(user: admin))).to eq([])
  end

  it 'o esquema recusa o máximo fora de 1 a 50 e o passo sem etapa', :aggregate_failures do
    expect(described_class.esquema_valido?(receita(para_cada(maximo: 0)))).to be(false)
    expect(described_class.esquema_valido?(receita(para_cada(maximo: 51)))).to be(false)
    expect(described_class.esquema_valido?(receita(para_cada.except('etapa_id')))).to be(false)
  end

  it 'recusa o valor que o passo não deixa, o passo sem sufixo e o valor lido antes dele', :aggregate_failures do
    expect(problemas(para_cada, mensagem('ia.lista.idades'))).to eq([erro(:texto_da_ia_sem_passo, passo: 'oi', caminho: 'ia.lista.idades')])
    expect(problemas(para_cada, mensagem('ia.lista'))).to eq([erro(:texto_da_ia_sem_passo, passo: 'oi', caminho: 'ia.lista')])
    expect(problemas(mensagem('ia.lista.quantos'), para_cada)).to eq([erro(:texto_da_ia_depois, passo: 'oi', caminho: 'ia.lista.quantos')])
  end

  it 'confere as flags, o campo nome, as chaves repetidas e a etapa da conta', :aggregate_failures do
    sem_nome = para_cada(campos: [{ 'chave' => 'telefone', 'descricao' => 'WhatsApp' }, { 'chave' => 'telefone', 'descricao' => 'outro' }])
    expect(problemas(sem_nome)).to eq([erro(:campo_repetido, passo: 'lista', chave: 'telefone'), erro(:para_cada_sem_nome, passo: 'lista')])
    expect(problemas(para_cada(etapa_id: 999_999))).to eq([erro(:etapa_do_card_de_fora, passo: 'lista', id: 999_999)])

    account.disable_features!('automacao_ia', 'automacao_gatilhos')
    expect(problemas(para_cada)).to eq([erro(:ia_desligada, passo: 'lista'), erro(:card_desligado, passo: 'lista')])
  end

  it 'recusa o campo de chave só com espaços, que o esquema aceita e viraria um atributo do contato sem nome' do
    campos = [{ 'chave' => 'nome', 'descricao' => 'Nome' }, { 'chave' => ' ', 'descricao' => 'Data de nascimento' }]

    expect(described_class.esquema_valido?(receita(para_cada(campos: campos)))).to be(true)
    expect(problemas(para_cada(campos: campos))).to eq([erro(:para_cada_chave_em_branco, passo: 'lista')])
  end

  it 'quem salva precisa poder importar contatos' do
    agente = create(:user, account: account, role: :agent)
    allow(Autonomia::Automacao::PassoDeCard).to receive(:cria_card?).and_return(true)
    allow(Crm::Access::VisiblePipelines).to receive(:new).and_return(instance_double(Crm::Access::VisiblePipelines, visible?: true))

    expect(problemas(para_cada, account_user: account.account_users.find_by(user: agente))).to eq([erro(:para_cada_sem_importar, passo: 'lista')])
  end
end
