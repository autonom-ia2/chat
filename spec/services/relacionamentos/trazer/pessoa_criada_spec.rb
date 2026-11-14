require 'rails_helper'

# #2896 (fatia 3) — o resumo "a ficha como a lista deixou", por onde o "Desfazer" sabe se alguém editou a pessoa que a
# lista criou. Ele cobre todas as colunas de `contacts`, menos a lista fechada das que o sistema mantém sozinho
# (Relacionamentos::Trazer::PessoaCriada::DE_FORA). Os exemplos fecham a classe do problema, e não um campo: a coluna
# que for criada amanhã entra no primeiro exemplo sem ninguém lembrar dela.
RSpec.describe Relacionamentos::Trazer::PessoaCriada, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:importacao) do
    account.campaign_imports.create!(user: user, status: :completed, mode: 'single_label',
                                     options: { 'flow' => CampaignImport::CONTACTS_FLOW, 'trazer' => {} })
  end
  let(:empresa) { account.companies.create!(name: 'Oficina Central') }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Da Lista', phone_number: '+5511987650050') }
  # As colunas que apontam para outra tabela precisam de um registro de verdade.
  let(:de_outra_tabela) { { 'company_id' => empresa.id, 'opted_out_by_id' => user.id } }

  # O texto que entra no resumo com segredo (Relacionamentos::CampoPreenchido.resumo): duas fichas com o mesmo texto
  # têm o mesmo resumo.
  def texto
    described_class.new(importacao).conteudo(pessoa.id).to_json
  end

  # Direto na coluna, sem os ganchos do contato: o que se prova é o resumo, não a gravação.
  def gravar(colunas)
    pessoa.update_columns(colunas) # rubocop:disable Rails/SkipsModelValidations
  end

  # Um valor diferente do que a coluna tem hoje, pelo tipo dela. O tipo que este exemplo não conhece levanta erro: quem
  # criar a coluna diz aqui como mudar o valor dela.
  def outro_valor(coluna)
    nome = coluna.name
    return de_outra_tabela.fetch(nome) if de_outra_tabela.key?(nome)
    return (Contact.defined_enums.fetch(nome).keys - [pessoa[nome]]).first if Contact.defined_enums.key?(nome)

    case coluna.type
    when :string then "valor novo de #{nome}"
    when :jsonb then { 'chave' => "valor novo de #{nome}" }
    when :datetime then Time.zone.parse('2026-02-03 04:05:06')
    when :boolean then !pessoa[nome]
    else raise "coluna #{nome}, do tipo #{coluna.type}: diga aqui como mudar o valor dela"
    end
  end

  it 'mudar qualquer coluna da ficha muda o resumo, menos as que o sistema mantém sozinho' do
    colunas = Contact.columns.reject { |coluna| described_class::DE_FORA.include?(coluna.name) }
    expect(colunas.map(&:name)).to match_array(described_class.colunas)

    colunas.each do |coluna|
      antes = texto
      gravar(coluna.name => outro_valor(coluna))

      expect(texto).not_to eq(antes), "mudar #{coluna.name} não mudou o resumo da ficha"
    end
  end

  it 'as colunas que o sistema mantém sozinho existem na tabela e não mudam o resumo' do
    expect(described_class::DE_FORA - Contact.column_names).to be_empty
    antes = texto

    gravar(updated_at: 1.day.from_now, last_activity_at: Time.current, location: 'Recife', country_code: 'BR')

    expect(texto).to eq(antes)
  end

  it 'um conjunto de chave e valor e uma lista de pares com o mesmo conteúdo têm resumos diferentes' do
    gravar(custom_attributes: { 'x' => { 'b' => 1 } })
    de_conjunto = texto

    gravar(custom_attributes: { 'x' => [['b', 1]] })

    expect(texto).not_to eq(de_conjunto)
  end

  it 'as marcas da busca da foto não mudam o resumo' do
    antes = texto

    gravar(additional_attributes: { 'last_avatar_sync_at' => Time.current.iso8601, 'avatar_url_hash' => 'a' * 64 })

    expect(texto).to eq(antes)
  end

  # A API de contatos grava qualquer chave de `additional_attributes`, e esta também: mudá-la é editar a ficha.
  it 'o código da pessoa no CRM de fora (`external`) é um valor como os outros: mudá-lo muda o resumo' do
    antes = texto

    gravar(additional_attributes: { 'external' => { 'crm_de_fora_id' => 'codigo-0042' } })

    expect(texto).not_to eq(antes)
  end

  # O valor igual ao padrão da coluna não entra no resumo. Isso não esconde a volta ao padrão: o valor que a lista pôs
  # estava no resumo, e sem ele o resumo é outro.
  it 'voltar ao padrão da coluna um valor que a lista pôs muda o resumo' do
    { 'relacao' => 'parceiro', 'contact_type' => 'lead', 'blocked' => true }.each do |coluna, da_lista|
      gravar(coluna => da_lista)
      como_a_lista_deixou = texto

      gravar(coluna => Contact.column_defaults.fetch(coluna))

      expect(pessoa.reload[coluna]).not_to eq(da_lista)
      expect(texto).not_to eq(como_a_lista_deixou), "voltar #{coluna} ao padrão não mudou o resumo da ficha"
    end
  end

  # O nome da empresa é um valor como os outros: não se tenta adivinhar se é cópia do nome da empresa ligada.
  describe 'o nome da empresa escrito na ficha' do
    it 'apagado ou trocado em quem tem empresa ligada, muda o resumo; de volta ao que era, o resumo é o mesmo' do
      # Ligar a pessoa à empresa copia o nome dela para a ficha (Enterprise::Concerns::Contact).
      pessoa.update!(company: empresa)
      expect(pessoa.reload.additional_attributes).to include('company_name' => 'Oficina Central')
      com_a_copia = texto

      gravar(additional_attributes: {})
      expect(texto).not_to eq(com_a_copia)

      gravar(additional_attributes: { 'company_name' => 'Oficina do Bairro' })
      expect(texto).not_to eq(com_a_copia)

      gravar(additional_attributes: { 'company_name' => 'Oficina Central' })
      expect(texto).to eq(com_a_copia)
    end

    it 'a empresa renomeada muda o resumo das pessoas dela, quando o sistema regrava o nome na ficha' do
      pessoa.update!(company: empresa)
      com_a_copia = texto

      empresa.update!(name: 'Oficina Central Dois')
      Companies::SyncContactNamesJob.perform_now(company_id: empresa.id)

      expect(pessoa.reload.additional_attributes).to include('company_name' => 'Oficina Central Dois')
      expect(texto).not_to eq(com_a_copia)
    end

    it 'em quem não tem empresa ligada, muda o resumo também' do
      antes = texto

      gravar(additional_attributes: { 'company_name' => 'Oficina Central' })

      expect(texto).not_to eq(antes)
    end
  end
end
