require 'rails_helper'

# R15 DA RECEITA DE RAMO: O MANUAL NO PADRÃO DO ESPECIALISTA.
#
# Auto, residencial e empresarial chegaram ao mesmo esqueleto sem ninguém escrevê-lo, e o empresarial esqueceu peças
# que o residencial tinha. O modelo abaixo foi deduzido dos três manuais de 25/09/2026, e a comparação é pelo TÍTULO
# de cada seção, sem o número (os ramos numeram diferente), com método de string.
#
# O que um ramo pode ter a mais, ou com outro título, está escrito aqui com o motivo. Seção nova que não é do modelo
# nem está declarada reprova: ou ela vai para o bloco comum, ou entra aqui como particularidade do ramo.
module PadraoDoEspecialista
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder

  # As seções de nível 2, nesta ordem. `:particularidades` é o lugar da seção própria do ramo (a atividade no
  # empresarial, a profissão em vida): depois do mínimo, antes da jornada.
  SECOES = ['Quem você é', 'O que você cota, e o que recusa', 'O mínimo de %<ramo>s', :particularidades, 'A jornada',
            'As regras que ligam um campo a outro', 'O que você nunca faz'].freeze
  # As subseções da jornada, nesta ordem. É a única seção com subseção.
  JORNADA = ['A apólice atual', 'Coleta, na ordem do mínimo', 'Cotar, sem pedir licença', 'Lapidação, quando ele quer mexer'].freeze
  TITULO = 'O que é só de %<ramo>s'.freeze

  # A SEÇÃO PRÓPRIA DE CADA RAMO, entre o mínimo e a jornada.
  PARTICULARIDADES = {
    # A atividade da empresa decide quantas seguradoras cotam, e cada seguradora tem a lista dela (chat#641).
    'empresarial' => ['A atividade da empresa']
  }.freeze

  # O TÍTULO QUE UM RAMO ESCREVE NO LUGAR DO DO MODELO.
  VARIANTES = {
    # As coberturas do cliente (25/09/2026) ficaram na mesma seção das regras entre campos: as travas de RC Operações,
    # despesas fixas e roubo são regra entre a cobertura e o valor a segurar.
    'empresarial' => { 'As regras que ligam um campo a outro' => 'As coberturas, e as regras que ligam um campo a outro' }
  }.freeze

  # AUTO É A EXCEÇÃO HISTÓRICA (receita v3): a renovação de auto nasceu antes da §D.2 do bloco comum e ocupa o lugar
  # da apólice atual em duas subseções; os preços e a escolha ficaram como subseções que apontam para a §K e a §L do
  # bloco comum. As seções de nível 2 de auto seguem o modelo.
  JORNADA_DE_AUTO = ['Novo ou renovação, a primeira coisa a saber', 'Renovação: a apólice não é opcional',
                     'Coleta, na ordem do mínimo', 'Cotar, sem pedir licença', 'Os preços e o comparativo',
                     'Lapidação, quando ele quer mexer', 'Quando o cliente escolhe'].freeze

  Manual = Struct.new(:titulo, :secoes, :subsecoes)

  module_function

  def ramos
    BUILDER::ESPECIALISTAS.pluck(:ramo)
  end

  def arquivo(ramo)
    BUILDER::INSTRUCOES.join(BUILDER::ESPECIALISTAS.find { |dados| dados[:ramo] == ramo }.fetch(:arquivo))
  end

  # O título, as seções de nível 2 e as subseções de cada uma, sem o número.
  def ler(texto)
    manual = Manual.new(nil, [], Hash.new { |hash, chave| hash[chave] = [] })
    texto.each_line do |linha|
      if linha.start_with?('# ') then manual.titulo = sem_numero(linha.delete_prefix('# '))
      elsif linha.start_with?('## ') then manual.secoes << sem_numero(linha.delete_prefix('## '))
      elsif linha.start_with?('### ') then manual.subsecoes[manual.secoes.last] << sem_numero(linha.delete_prefix('### '))
      end
    end
    manual
  end

  # "4.1 A apólice atual" -> "A apólice atual". O número é o primeiro termo quando ele só tem dígitos e pontos.
  def sem_numero(titulo)
    primeiro, resto = titulo.strip.split(' ', 2)
    numero = primeiro.to_s.delete('0-9.').empty? && resto.present?
    numero ? resto.strip : titulo.strip
  end

  def secoes_esperadas(ramo)
    variantes = VARIANTES.fetch(ramo, {})
    SECOES.flat_map do |secao|
      next PARTICULARIDADES.fetch(ramo, []) if secao == :particularidades

      titulo = format(secao, ramo: ramo)
      variantes.fetch(titulo, titulo)
    end
  end

  def jornada_esperada(ramo)
    ramo == 'auto' ? JORNADA_DE_AUTO : JORNADA
  end
end

RSpec.describe 'R15: o manual no padrão do especialista' do # rubocop:disable RSpec/DescribeClass
  PadraoDoEspecialista.ramos.each do |ramo|
    describe "o manual de #{ramo}" do
      let(:manual) { PadraoDoEspecialista.ler(PadraoDoEspecialista.arquivo(ramo).read) }

      it 'abre com o título do ramo' do
        expect(manual.titulo).to eq(format(PadraoDoEspecialista::TITULO, ramo: ramo))
      end

      it 'tem as seções do modelo, nesta ordem, e só as declaradas a mais' do
        expect(manual.secoes).to eq(PadraoDoEspecialista.secoes_esperadas(ramo))
      end

      it 'a jornada tem as subseções do modelo, nesta ordem' do
        expect(manual.subsecoes['A jornada']).to eq(PadraoDoEspecialista.jornada_esperada(ramo))
      end

      it 'só a jornada tem subseção' do
        expect(manual.subsecoes.keys - ['A jornada']).to be_empty
      end
    end
  end

  it 'todo manual de especialista na pasta é de um especialista do Builder' do
    na_pasta = Dir[PadraoDoEspecialista::BUILDER::INSTRUCOES.join('especialista_*.md').to_s].map { |caminho| File.basename(caminho) }

    expect(na_pasta).to match_array(PadraoDoEspecialista::BUILDER::ESPECIALISTAS.map { |dados| dados[:arquivo] })
  end

  it 'a exceção de auto e as declarações de ramo só valem para ramos que existem' do
    declarados = PadraoDoEspecialista::PARTICULARIDADES.keys | PadraoDoEspecialista::VARIANTES.keys

    expect(declarados - PadraoDoEspecialista.ramos).to be_empty
    expect(PadraoDoEspecialista.ramos).to include('auto')
  end

  it 'lê o número de seção como número, e o resto como título' do
    expect(PadraoDoEspecialista.sem_numero("4.1 A apólice atual\n")).to eq('A apólice atual')
    expect(PadraoDoEspecialista.sem_numero('6. O que você nunca faz')).to eq('O que você nunca faz')
    expect(PadraoDoEspecialista.sem_numero('O que é só de auto')).to eq('O que é só de auto')
  end
end
