require 'rails_helper'

# A RENOVAÇÃO EM RESIDENCIAL E EMPRESARIAL (25/09/2026). O adapter ganhou o grupo `renovacao` nos dois ramos
# (adapters, branch `feat/renovacao-residencial-empresarial`, commit 5ffa0eb): cinco campos do cliente, todos
# opcionais, e o grupo nulo é seguro novo. O que se prova aqui, do lado do chat:
#   o grupo vira formulário no modo strict da OpenAI, com o rótulo que diz ao modelo que nulo é seguro novo;
#   o grupo chega à entrada da cotação na raiz, como o adapter o lê (`blocoDaRenovacao`), e nulo não vai;
#   o resumo da entrada diz renovação ou seguro novo, e na renovação a seguradora anterior e o bônus;
#   auto não muda: nem o formulário, nem o resumo.
#
# PROVA POR MUTAÇÃO (relatório da branch): tirar o grupo dos mocks; tirar a linha do resumo; tirar a §D.2 do
# bloco comum.
RSpec.describe Autonomia::Insurance::Parametros do
  let(:mock) { Autonomia::Insurance::Connector::Mock }
  let(:schemas) { { 'residencial' => mock::SCHEMA_RESIDENCIAL, 'empresarial' => mock::SCHEMA_EMPRESARIAL } }
  let(:campos_da_renovacao) { %w[seguradoraAnterior bonus sinistros numeroApolice fimVigencia] }

  describe 'o formulário' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
    let(:lia) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                       status: :active, enabled: true, instruction: 'Atenda.')
    end

    before do
      enable_test_encryption!
      Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                      .update!(status: 'ready', metadata: { 'quote_schemas' => schemas.merge('auto' => mock::SCHEMA_AUTO) })
      allow(Autonomia::Insurance::Connector).to receive(:client).and_raise('não deveria chamar o adapter')
    end

    def strict(slug)
      especialista = Autonomia::Agents::Specialist.create!(agent: lia, account: account, slug: slug, name: slug,
                                                           description: 'cota', instruction: 'Cote.')
      Autonomia::Agents::Tools::Native::InsuranceQuote.openai_schema(lia, especialista: especialista)[:parameters]
    end

    %w[residencial empresarial].each do |ramo|
      it "em #{ramo}, o grupo entra em strict: nulo, com o rótulo, toda chave em required e nada além delas" do
        formulario = strict("cotacao_#{ramo}")
        grupo = formulario[:properties]['renovacao']

        expect(formulario[:required]).to include('renovacao')
        expect(grupo[:type]).to eq(%w[object null])
        expect(grupo[:description]).to eq(described_class::GRUPOS.fetch('renovacao'))
        expect(grupo[:properties].keys).to match_array(campos_da_renovacao)
        expect(grupo[:required]).to match_array(campos_da_renovacao)
        expect(grupo[:additionalProperties]).to be(false)
      end

      it "em #{ramo}, cada campo do grupo aceita null, e o enum também" do
        grupo = strict("cotacao_#{ramo}")[:properties]['renovacao']

        expect(grupo[:properties].values.map { |p| p['type'] }).to all(include('null'))
        expect(grupo[:properties]['bonus']['enum']).to eq([0, 1, 2, 3, 4, 5, nil])
        expect(grupo[:properties]['sinistros']['enum']).to eq(['0', '1', nil])
        expect(grupo[:properties]['seguradoraAnterior']['enum']).to include('HDI', 'Zurich - Minas Brasil', nil)
      end
    end

    it 'o rótulo do grupo não é o genérico, e diz que o grupo nulo é seguro novo' do
      rotulo = described_class::GRUPOS.fetch('renovacao')

      expect(rotulo).not_to eq(format(described_class::ROTULO_GENERICO, 'renovacao'))
      expect(rotulo).to include('nulo quando é seguro novo')
      expect(rotulo).not_to include('`', '—', '–')
    end

    # AUTO IDÊNTICO: o formulário de auto é o mesmo de antes da renovação dos ramos, byte a byte. O md5 foi tirado do
    # código da main (84c8964027) e conferido de novo com a mudança aplicada.
    # Voz da Lia, item 6 (`1a15e8d5…` -> `e49be23c…`, 26/09/2026): entram, em todo ramo, os dois parâmetros comuns do
    # pedido (`pedido_que_entrou` e `pedido_que_nao_coube`, texto ou nulo), que ficam na execução e não vão ao portal.
    # Conferido: sem os dois, o md5 volta a ser `1a15e8d5…`; o resto do formulário de auto não mudou.
    it 'auto não muda: o formulário de auto não tem o grupo e é o mesmo de antes' do
      formulario = strict('cotacao_auto')

      expect(formulario[:properties]).not_to have_key('renovacao')
      expect(Digest::MD5.hexdigest(JSON.generate(formulario))).to eq('e49be23c7087a668033ee972c1c0d90c')
      pedido = %w[pedido_que_entrou pedido_que_nao_coube]
      sem_o_pedido = formulario.merge(properties: formulario[:properties].except(*pedido), required: formulario[:required] - pedido)
      expect(Digest::MD5.hexdigest(JSON.generate(sem_o_pedido))).to eq('1a15e8d5b531509a7db10256927df08d')
    end
  end

  # A TRAVESSIA, no molde de `quote_input_travessia_do_ramo_spec`: o grupo que o formulário declara chega à entrada
  # no caminho em que o adapter o lê, e o nulo não vai (o corpo sai o de seguro novo).
  describe 'a travessia do grupo' do
    def entrada(ramo, params)
      grupos = described_class.new(schemas.fetch(ramo), ramo: true).nomes_dos_grupos
      Autonomia::Insurance::QuoteInput.new(produto: ramo, params: { 'cpf' => '52998224725' }.merge(params), dados: {},
                                           commission_percent: 10.0, grupos_do_ramo: grupos).to_h
    end

    let(:renovacao) do
      { 'seguradoraAnterior' => 'HDI', 'bonus' => 3, 'sinistros' => '0', 'numeroApolice' => '123', 'fimVigencia' => '2026-10-15' }
    end

    %w[residencial empresarial].each do |ramo|
      it "em #{ramo}, o grupo vai na raiz da entrada como veio" do
        expect(described_class.new(schemas.fetch(ramo), ramo: true).nomes_dos_grupos).to include('renovacao')
        expect(entrada(ramo, 'renovacao' => renovacao)['renovacao']).to eq(renovacao)
      end

      it "em #{ramo}, o grupo nulo, vazio ou só com nulos não vai: é seguro novo" do
        [nil, {}, campos_da_renovacao.index_with { nil }].each do |nulo|
          expect(entrada(ramo, 'renovacao' => nulo)).not_to have_key('renovacao')
        end
      end

      it "em #{ramo}, o campo que o modelo deixou nulo sai, e o resto vai" do
        sem_numero = renovacao.merge('numeroApolice' => nil)

        expect(entrada(ramo, 'renovacao' => sem_numero)['renovacao']).to eq(renovacao.except('numeroApolice'))
      end
    end
  end

  describe 'o resumo da entrada' do
    def resumo(ramo, extra = {})
      argumentos = { 'produto' => ramo, 'cpf' => '52998224725', 'cep' => '01310-100',
                     'configuracoes' => { 'imovelNumero' => '742', 'imovelTipoResidencia' => 3,
                                          'isDanosIncendioRaioExplosao' => 400_000 } }.merge(extra)
      Autonomia::Insurance::EntradaDaCotacao.new(argumentos, schema: schemas.fetch(ramo)).texto
    end

    %w[residencial empresarial].each do |ramo|
      it "em #{ramo}, a renovação aparece com a seguradora anterior pelo nome e o bônus" do
        texto = resumo(ramo, 'renovacao' => { 'seguradoraAnterior' => 'Zurich - Minas Brasil', 'bonus' => 3,
                                              'sinistros' => '0', 'fimVigencia' => '2026-10-15' })

        expect(texto).to include(Autonomia::Insurance::EntradaDaCotacao::RENOVACAO,
                                 'Seguradora anterior: Zurich.', 'Classe de bônus: 3.')
        expect(texto).not_to include(Autonomia::Insurance::EntradaDaCotacao::SEGURO_NOVO, 'Minas Brasil')
      end

      it "em #{ramo}, sem o grupo é seguro novo, e não fala de seguradora anterior nem de bônus" do
        [resumo(ramo), resumo(ramo, 'renovacao' => nil)].each do |texto|
          expect(texto).to include(Autonomia::Insurance::EntradaDaCotacao::SEGURO_NOVO)
          expect(texto).not_to include('renovação de apólice anterior', 'Seguradora anterior', 'Classe de bônus')
        end
      end

      # A regra do adapter (`ehRenovacao`): grupo só com nulo ou texto vazio é seguro novo, e o resumo diz o mesmo.
      # Pelo formulário o vazio já sai (`QuoteInput#sem_vazios`); pelo `dados`, que vai como veio, não saía, e
      # `{"renovacao":{"bonus":null}}` aparecia como renovação no resumo (revisão de 25/09/2026).
      it "em #{ramo}, o grupo só com nulo ou vazio é seguro novo, como o adapter cota" do
        grupos = [{ 'bonus' => nil }, { 'sinistros' => '' }, { 'bonus' => nil, 'numeroApolice' => '' }]
        textos = grupos.flat_map do |grupo|
          [resumo(ramo, 'renovacao' => grupo), resumo(ramo, 'dados' => { 'renovacao' => grupo }.to_json)]
        end

        textos.each do |texto|
          expect(texto).to include(Autonomia::Insurance::EntradaDaCotacao::SEGURO_NOVO)
          expect(texto).not_to include(Autonomia::Insurance::EntradaDaCotacao::RENOVACAO, 'Seguradora anterior')
        end
        expect(resumo(ramo, 'dados' => { 'renovacao' => { 'bonus' => 0 } }.to_json))
          .to include(Autonomia::Insurance::EntradaDaCotacao::RENOVACAO)
      end

      it "em #{ramo}, a seguradora que não é nome da lista não sai crua" do
        texto = resumo(ramo, 'renovacao' => { 'seguradoraAnterior' => '7', 'bonus' => 1 })

        expect(texto).to include("Seguradora anterior: #{Autonomia::Insurance::EntradaDaCotacao::SEM_NOME}")
        expect(texto).not_to include('anterior: 7')
      end
    end

    # AUTO IDÊNTICO: o texto inteiro de uma renovação de auto, igual ao da main (84c8964027).
    it 'auto não muda: o resumo de auto é o mesmo de antes' do
      argumentos = { 'produto' => 'auto', 'cep' => '01310-930',
                     'quotation' => { 'isRenewal' => true, 'bonusClass' => 9, 'previousInsurerCode' => '657' },
                     'renovacao' => { 'bonus' => 1 } }
      texto = Autonomia::Insurance::EntradaDaCotacao.new(argumentos, schema: mock::SCHEMA_AUTO).texto
      novo = Autonomia::Insurance::EntradaDaCotacao.new({ 'produto' => 'auto', 'cep' => '01310-930' }, schema: mock::SCHEMA_AUTO).texto

      expect(Digest::MD5.hexdigest(texto)).to eq('393c08a7ef9a7abb7d3318558576cef9')
      expect(Digest::MD5.hexdigest(novo)).to eq('9978989163045e5e1f1cb4ee1bebd5c5')
    end
  end
end
