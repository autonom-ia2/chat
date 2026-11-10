require 'rails_helper'

# O modelo aprovado da Meta do passo "mensagem" (#2468, F4b): a régua de quando ele serve, e a conferência ao salvar.
RSpec.describe Autonomia::Automacao::ModeloWhatsapp do
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:aprovado) do
    { 'name' => 'pedido_saiu', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu pedido {{2}} saiu.' }] }
  end
  let(:modelo) { { 'nome' => 'pedido_saiu', 'idioma' => 'pt_BR', 'variaveis' => [[{ '$valor' => 'contato.nome' }], ['nº 42']] } }

  before do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens')
    canal.update!(message_templates: [aprovado])
  end

  describe '.serve?' do
    it 'aprovado, de utilidade, com {{1}}..{{n}} no corpo e nada a preencher fora dele' do
      expect(described_class.serve?(aprovado, 2)).to be(true)
    end

    {
      'outra quantidade de variáveis' => [{}, 3],
      'pendente' => [{ 'status' => 'PENDING' }, 2],
      'variável fora da sequência' => [{ 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{3}}.' }] }, 2],
      'variável no topo' => [{ 'components' => [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Olá {{1}}' },
                                                { 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}.' }] }, 2],
      'botão com link variável' => [{ 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}.' },
                                                       { 'type' => 'BUTTONS', 'buttons' => [{ 'url' => 'https://x.com/{{1}}' }] }] }, 2]
    }.each do |caso, (troca, quantas)|
      it "não serve: #{caso}" do
        expect(described_class.serve?(aprovado.merge(troca), quantas)).to be(false)
      end
    end

    # Lote 5 (#2681), decisão do Rodrigo de 07/11: propaganda liberada, com aviso de custo na tela.
    it 'aceita utilidade e propaganda; autenticação não' do
      expect(described_class.serve?(aprovado.merge('category' => 'MARKETING'), 2)).to be(true)
      expect(described_class.serve?(aprovado.merge('category' => 'AUTHENTICATION'), 2)).to be(false)
    end
  end

  describe 'ao salvar a receita' do
    def problemas(passo)
      receita = { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    def passo_com(modelo) = { 'id' => 'p1', 'tipo' => 'mensagem', 'texto' => ['Oi.'], 'modelo' => modelo }

    it 'aceita o modelo que alguma caixa oficial da conta tem pronto' do
      expect(problemas(passo_com(modelo))).to be_empty
    end

    it 'recusa o modelo que nenhuma caixa oficial tem pronto, com o nome' do
      sem = modelo.merge('nome' => 'nao_existe')

      expect(problemas(passo_com(sem))).to eq([I18n.t('autonomia.automacao.receita.modelo_indisponivel', passo: 'p1', nome: 'nao_existe')])
    end

    it 'recusa o modelo com outra quantidade de variáveis' do
      expect(problemas(passo_com(modelo.merge('variaveis' => [['x']])))).to include(
        I18n.t('autonomia.automacao.receita.modelo_indisponivel', passo: 'p1', nome: 'pedido_saiu')
      )
    end

    it 'confere os valores de cada variável como os do texto' do
      errado = modelo.merge('variaveis' => [[{ '$valor' => 'contato.nao_existe' }], ['x']])

      expect(problemas(passo_com(errado))).to include(
        I18n.t('autonomia.automacao.receita.valor_desconhecido', passo: 'p1', caminho: 'contato.nao_existe')
      )
    end

    it 'o esquema não aceita modelo no avisar' do
      avisar = { 'id' => 'p1', 'tipo' => 'avisar', 'texto' => ['Oi.'], 'para' => { 'responsavel' => true }, 'modelo' => modelo }

      expect(Autonomia::Automacao::Receita.esquema_valido?('gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [avisar])).to be(false)
    end
  end
end
