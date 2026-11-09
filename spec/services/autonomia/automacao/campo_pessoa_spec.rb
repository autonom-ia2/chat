require 'rails_helper'

# G62 (#2829): o campo do card do tipo "pessoa da equipe". Guarda o id de uma pessoa da conta; a receita lê também o
# nome e se ela está ausente (`card.atributos.<campo>.nome` e `.ausente`). O ponta a ponta (a responsável original do
# exemplo 17, gravada e devolvida) está em spec/fechamento/automacao/g9_troca_de_responsavel_spec.rb.
RSpec.describe 'Automação livre: campo do card do tipo pessoa da equipe', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Paula') }
  let(:julia) { create(:user, account: account, role: :agent, name: 'Júlia') }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Proposta', currency: 'BRL') }
  let(:valores) { Autonomia::Automacao::Valores.new(alvo: card, quem: admin) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'original',
                                         attribute_display_name: 'Responsável original', attribute_display_type: :pessoa)
  end

  describe 'o campo no card' do
    it 'guarda a pessoa da conta pelo id, e o número que chega como texto vira número' do
      card.update!(custom_attributes: { 'original' => julia.id.to_s })

      expect(card.reload.custom_attributes['original']).to eq(julia.id)
    end

    it 'recusa quem não é da conta' do
      de_fora = create(:user, name: 'Outra')

      expect(card.update(custom_attributes: { 'original' => de_fora.id })).to be(false)
      expect(card.errors[:custom_attributes].join).to include('original')
    end

    it 'vazio apaga' do
      card.update!(custom_attributes: { 'original' => julia.id })
      card.update!(custom_attributes: { 'original' => nil })

      expect(card.reload.custom_attributes['original']).to be_nil
    end

    it 'só existe no card' do
      definicao = build(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                                      attribute_key: 'vendedor', attribute_display_type: :pessoa)

      expect(definicao).not_to be_valid
    end

    it 'fica fora da extração da IA: quem é a pessoa a equipe escolhe' do
      chaves = Crm::Ai::AttributeSchemaBuilder.new(account: account, prefix: '').perform[:card].pluck(:key)

      expect(chaves).not_to include('original')
    end
  end

  describe 'o que a receita lê' do
    before { card.update!(custom_attributes: { 'original' => julia.id }) }

    it 'o id, o nome e a ausência da pessoa', :aggregate_failures do
      expect(valores.ler('card.atributos.original')).to eq(julia.id)
      expect(valores.ler('card.atributos.original.nome')).to eq('Júlia')
      expect(valores.ler('card.atributos.original.ausente')).to be(false)
    end

    it 'a ausência segue o "ausente até" dela na conta' do
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: 2.days.from_now)

      expect(valores.ler('card.atributos.original.ausente')).to be(true)
    end

    it 'a pessoa que saiu da conta lê vazio: é achada na conta, nunca só pelo id', :aggregate_failures do
      AccountUser.find_by!(account: account, user: julia).destroy!

      expect(valores.ler('card.atributos.original.nome')).to be_nil
      expect(valores.ler('card.atributos.original.ausente')).to be(false)
    end

    it 'um campo de verdade com ponto na chave vale primeiro' do
      create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'original.nome',
                                           attribute_display_type: :text)
      card.update!(custom_attributes: card.custom_attributes.merge('original.nome' => 'escrito à mão'))

      expect(valores.ler('card.atributos.original.nome')).to eq('escrito à mão')
    end

    it 'a ausência é fechada em sim e não, como a G23' do
      expect(Autonomia::Automacao::Valores.fechado('card.atributos.original.ausente')['opcoes']).to eq([true, false])
    end
  end

  describe 'o salvar' do
    def problemas(caminho)
      receita = { 'gatilho' => { 'tipo' => 'card.ganho' },
                  'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'entao' => [esperar_passo('p2')],
                                 'condicao' => { 'campo' => { '$valor' => caminho }, 'op' => 'igual', 'valor' => true } }] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    before do
      ligar_motor(account)
      account.enable_features!('automacao_gatilhos')
    end

    it 'aceita a ausência da pessoa do campo' do
      expect(problemas('card.atributos.original.ausente')).to be_empty
    end

    it 'recusa o nome de um campo que não é de pessoa' do
      create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'placa',
                                           attribute_display_type: :text)

      expect(problemas('card.atributos.placa.ausente')).not_to be_empty
    end
  end
end
