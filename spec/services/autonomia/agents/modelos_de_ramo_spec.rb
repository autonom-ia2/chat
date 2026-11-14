require 'rails_helper'

# #2881 — o catálogo dos modelos de agente prontos por ramo de seguro: o conteúdo mora em
# config/agentes_por_pacote/seguros/modelos (`<chave>.yml` e `<chave>.md`) e é conferido na leitura. Arquivo ausente
# ou fora do formato não derruba o Construtor: o modelo só deixa de existir. Só conta com o pacote `seguros` E com a
# flag `agente_modelos_seguro` pode usar.
RSpec.describe Autonomia::Agents::ModelosDeRamo do
  include ModelosDeRamoHelper

  # #3024: os 20 ramos, todos com as perguntas em blocos.
  let(:ramos) do
    %w[acidentes_pessoais aviacao planos_de_saude rc_geral rc_profissional riscos_de_engenharia seguro_aluguel seguro_auto
       seguro_bike seguro_celular seguro_cibernetico seguro_condominio seguro_empresarial seguro_garantia seguro_residencial
       seguro_rural seguro_viagem transporte_carga vida_em_grupo vida_individual]
  end

  describe 'os modelos dos ramos' do
    it 'carrega os vinte, cada um com o tipo comercial, as perguntas em blocos e as listas' do
      expect(described_class.chaves).to match_array(ramos)

      ramos.each do |chave|
        modelo = described_class.buscar(chave)
        expect(modelo.chave).to eq(chave)
        expect(modelo.tipo).to eq('sdr')
        expect(modelo.nome_padrao).to be_present
        expect(modelo.molde_das_perguntas).to be_present.and all(include('bloco'))
        expect(modelo.ja_vem).not_to be_empty
        expect(modelo.teste.size).to eq(3)
      end
    end

    it 'guarda o roteiro cru em até 8.000 bytes, com cada marcador uma vez e sozinho na linha' do
      ramos.each do |chave|
        roteiro = described_class.buscar(chave).roteiro
        linhas = roteiro.lines.map(&:strip)

        expect(roteiro.bytesize).to be <= Autonomia::Agents::ModelosDeRamo::Formato::ROTEIRO_MAX
        expect(described_class::MARCADORES.keys.map { |marcador| linhas.count(marcador) }).to eq([1, 1])
      end
    end

    # O que o ramo explica (o seguro em palavras simples e as dúvidas comuns) vai do roteiro para a marca do agente.
    it 'traz o conhecimento do ramo no roteiro e o copia para a marca com que o agente nasce' do
      ramos.each do |chave|
        modelo = described_class.buscar(chave)
        saber = described_class::Conhecimento.do_roteiro(modelo.roteiro)

        expect(saber).to start_with(described_class::Conhecimento::INICIO).and include('DÚVIDAS COMUNS')
        expect(saber).not_to include(described_class::Conhecimento::FIM)
        expect(described_class::Marca.inicial(modelo)['conhecimento']).to eq(saber)
      end
    end

    it 'só traz ferramenta grátis da vitrine no "Já vem com" e no "Também combina", sem repetir' do
      sugeriveis = Autonomia::FerramentasProntas::Catalogo.chaves_sugeriveis

      ramos.each do |chave|
        fontes = described_class.buscar(chave).ferramentas.map(&:fonte)
        expect(fontes - sugeriveis).to be_empty
        expect(fontes.uniq).to eq(fontes)
      end
    end

    it 'só sugere cartão Premium na lista dos pagos' do
      cartoes = Autonomia::FerramentasProntas::Catalogo.premium_no_codigo.map(&:chave)

      expect(ramos.flat_map { |chave| described_class.buscar(chave).premium } - cartoes).to be_empty
    end

    it 'devolve nil para chave desconhecida, vazia ou que não é texto' do
      expect(described_class.buscar('seguro_de_vida')).to be_nil
      expect(described_class.buscar(nil)).to be_nil
      expect(described_class.buscar({ 'chave' => 'seguro_auto' })).to be_nil
    end
  end

  # #3020 — as perguntas em blocos: o ramo traz a lista inteira, e só o mínimo vem ligado.
  describe 'o modelo em blocos' do
    let(:modelo) { described_class.buscar('seguro_condominio') }
    let(:marca) { described_class::Marca.inicial(modelo) }

    it 'carrega com o roteiro, as ferramentas e cada pergunta no bloco dela' do
      expect(modelo.tipo).to eq('sdr')
      expect(modelo.roteiro.bytesize).to be <= described_class::Formato::ROTEIRO_MAX
      expect(modelo.perguntas.size).to be > described_class::ITENS_MAX
      expect(modelo.molde_das_perguntas.pluck('bloco').uniq.first(3)).to eq(['O pedido', 'Quem é e contato', 'Endereço'])
      expect(modelo.molde_das_perguntas).to all(include('bloco'))
    end

    it 'nasce só com o mínimo ligado: o resto fica guardado, desligado' do
      ligadas = marca['perguntas'].reject { |item| item['tirada'] }

      expect(ligadas.size).to eq(12)
      expect(ligadas.pluck('texto')).to include('Qual o CNPJ do próprio condomínio?', 'Qual o CEP do condomínio?')
      expect(marca['perguntas'].pluck('id')).to eq((1..modelo.perguntas.size).map { |numero| "p#{numero}" })
    end

    it 'manda ao agente só as ligadas, com a condição na frente da pergunta que tem uma' do
      textos = described_class::Marca.textos(marca, 'perguntas')

      expect(textos.size).to eq(12)
      expect(textos).to include('Se for de prédios: Quantos andares tem cada bloco, contando térreo e subsolos?')
      expect(textos).not_to include(a_string_including('extintores'))
    end

    it 'entrega à tela o lugar de cada pergunta, e nada a mais nos itens de um modelo de lista corrida' do
      da_tela = described_class::Marca.itens(marca, 'perguntas')
      andares = da_tela.find { |item| item['texto'].start_with?('Quantos andares') }

      expect(andares).to include('bloco' => 'O prédio', 'se' => 'for de prédios', 'segue' => true, 'tirada' => false)
      # O agente que nasceu de um modelo de lista corrida (antes do #3024) guarda as perguntas sem lugar.
      corrida = { 'perguntas' => [{ 'id' => 'p1', 'texto' => 'Qual o CNPJ?', 'tirada' => false }] }
      expect(described_class::Marca.itens(corrida, 'perguntas').first.keys).to eq(%w[id texto tirada])
    end
  end

  describe 'a conferência do arquivo' do
    let(:pasta) { Pathname(Dir.mktmpdir) }
    let(:original) { described_class::PASTA }
    let(:dados) { YAML.safe_load(File.read(original.join('seguro_garantia.yml'), encoding: 'UTF-8')) }
    let(:roteiro) { File.read(original.join('seguro_garantia.md'), encoding: 'UTF-8') }
    # O formato de antes do #3020, que o leitor ainda aceita: as perguntas numa lista corrida, sem blocos.
    let(:corrida) { dados.except('blocos').merge('perguntas' => ['Para que é a garantia?', 'Qual o CNPJ?']) }

    after { FileUtils.remove_entry(pasta) }

    def gravar(conteudo, texto = roteiro, chave: 'seguro_garantia')
      File.write(pasta.join("#{chave}.yml"), conteudo.is_a?(String) ? conteudo : conteudo.to_yaml)
      File.write(pasta.join("#{chave}.md"), texto) unless texto.nil?
    end

    def lidos
      described_class::Leitor.new(pasta).modelos
    end

    it 'aceita a cópia fiel do arquivo do ramo e a lista corrida de antes' do
      [dados, corrida].each do |conteudo|
        gravar(conteudo)
        expect(lidos.keys).to eq(['seguro_garantia'])
      end
    end

    it 'recusa o que não é YAML e segue sem o modelo, sem levantar' do
      gravar("chave: [sem fechar\n  tipo: sdr")

      expect(lidos).to eq({})
    end

    it 'recusa campo desconhecido, campo que falta e chave diferente do nome do arquivo' do
      [dados.merge('preco' => 'R$ 10'), dados.except('blocos'), dados.merge('chave' => 'outra')].each do |invalido|
        gravar(invalido)
        expect(lidos).to eq({})
      end
    end

    it 'recusa texto acima do limite e lista longa demais' do
      # A lista corrida segue no teto de 20; o de 200 é só do modelo em blocos.
      longa = corrida.merge('perguntas' => Array.new(described_class::ITENS_MAX + 1) { |i| "Pergunta #{i}?" })
      comprida = dados.merge('documentos' => ['a' * (described_class::ITEM_MAX + 1)])
      frase = dados.merge('ja_vem' => [{ 'fonte' => 'cnpj', 'usar_quando' => 'a' * 501 }])

      [longa, comprida, frase, dados.merge('teste' => %w[uma duas])].each do |invalido|
        gravar(invalido)
        expect(lidos).to eq({})
      end
    end

    # #3020
    it 'aceita as perguntas em blocos no lugar da lista corrida' do
      perguntas = [{ 'texto' => 'Qual o CNPJ?', 'ligada' => true },
                   { 'texto' => 'Qual a razão social?', 'se' => 'o CNPJ não trouxer', 'segue' => true }]
      gravar(dados.merge('blocos' => [{ 'nome' => 'A empresa', 'perguntas' => perguntas }]))

      expect(lidos['seguro_garantia'].molde_das_perguntas).to eq(
        [{ 'texto' => 'Qual o CNPJ?', 'tirada' => false, 'bloco' => 'A empresa' },
         { 'texto' => 'Qual a razão social?', 'tirada' => true, 'bloco' => 'A empresa', 'se' => 'o CNPJ não trouxer', 'segue' => true }]
      )
    end

    it 'recusa blocos fora do formato' do
      bloco = ->(perguntas, nome = 'A empresa') { { 'nome' => nome, 'perguntas' => perguntas } }
      ligada = { 'texto' => 'Qual o CNPJ?', 'ligada' => true }
      sem_lista = dados.except('blocos')
      invalidos = [
        corrida.merge('blocos' => [bloco.call([ligada])]),                                            # perguntas e blocos
        sem_lista.merge('blocos' => [bloco.call([{ 'texto' => 'Qual o CNPJ?' }])]),                   # nenhuma ligada
        sem_lista.merge('blocos' => [bloco.call([ligada]), bloco.call([ligada])]),                    # nome repetido
        sem_lista.merge('blocos' => [bloco.call([])]),                                                # bloco vazio
        sem_lista.merge('blocos' => [bloco.call([ligada.merge('segue' => true)])]),                   # a primeira segue
        sem_lista.merge('blocos' => [bloco.call([ligada, { 'texto' => 'Qual?' }, { 'texto' => 'E?', 'segue' => true, 'ligada' => true }])]),
        sem_lista.merge('blocos' => [bloco.call([ligada.merge('ordem' => 2)])]),                      # campo desconhecido
        sem_lista.merge('blocos' => [bloco.call([ligada.merge('ligada' => 'sim')])]),                 # não é sim ou não
        sem_lista.merge('blocos' => [bloco.call([ligada] * (described_class::PERGUNTAS_MAX + 1))])    # passa de 200
      ]

      invalidos.each do |invalido|
        gravar(invalido)
        expect(lidos).to eq({})
      end
    end

    it 'recusa Premium no "Já vem com" e no "Também combina"' do
      paga = { 'fonte' => 'raio_x_empresa', 'usar_quando' => 'Use quando o cliente informar o CNPJ.' }

      [dados.merge('ja_vem' => dados['ja_vem'] + [paga]), dados.merge('tambem' => [paga])].each do |invalido|
        gravar(invalido)
        expect(lidos).to eq({})
      end
    end

    it 'recusa ferramenta fora do catálogo, de uso interno, repetida ou que não é cartão Premium na lista dos pagos' do
      frase = 'Use quando o cliente pedir.'
      invalidos = [
        dados.merge('ja_vem' => [{ 'fonte' => 'nao_existe', 'usar_quando' => frase }]),
        dados.merge('ja_vem' => [{ 'fonte' => 'produtos_seguradoras', 'usar_quando' => frase }]),
        dados.merge('tambem' => [{ 'fonte' => dados['ja_vem'].first['fonte'], 'usar_quando' => frase }]),
        dados.merge('premium' => ['cnpj'])
      ]

      invalidos.each do |invalido|
        gravar(invalido)
        expect(lidos).to eq({})
      end
    end

    it 'recusa o roteiro que falta, grande demais ou sem um marcador sozinho na linha' do
      sem_marcador = roteiro.sub('{{DOCUMENTOS}}', 'os documentos: {{DOCUMENTOS}}')

      gravar(dados, nil)
      expect(lidos).to eq({})

      ["#{roteiro}\n#{'a' * 8_000}", sem_marcador, "#{roteiro}\n{{DOCUMENTOS}}"].each do |texto|
        gravar(dados, texto)
        expect(lidos).to eq({})
      end
    end

    it 'recusa o roteiro sem o trecho do conhecimento do ramo, sem as dúvidas comuns ou com marcador dentro dele' do
      saber = described_class::Conhecimento
      sem_trecho = roteiro.sub(saber::INICIO, 'O SEGURO:')
      sem_duvidas = roteiro.sub(saber::DUVIDAS, 'PERGUNTAS FREQUENTES')
      com_marcador = roteiro.sub(saber::INICIO, "#{saber::INICIO} [[a coletar: empresa]]")

      [sem_trecho, sem_duvidas, com_marcador].each do |texto|
        gravar(dados, texto)
        expect(lidos).to eq({})
      end
    end

    it 'deixa de fora só o modelo com defeito' do
      gravar(dados)
      gravar(dados.merge('chave' => 'quebrado', 'tipo' => 'insurance_quote'), chave: 'quebrado')

      expect(lidos.keys).to eq(['seguro_garantia'])
    end
  end

  describe '.liberado?' do
    let(:account) { create(:account) }

    around { |example| com_pacotes_ligados { example.run } }

    it 'libera só com o pacote seguros e a flag juntos' do
      expect(described_class.liberado?(account)).to be(false)

      account.enable_features!(described_class::FLAG)
      expect(described_class.liberado?(account)).to be(false)
      expect(described_class.liberados(account)).to eq([])

      conta_de_seguros(account)
      expect(described_class.liberado?(account)).to be(true)
      expect(described_class.liberados(account)).to match_array(ramos)
    end

    it 'não libera conta de seguros sem a flag, nem com o interruptor dos pacotes desligado' do
      conta_de_seguros(account)
      expect(described_class.liberado?(account)).to be(false)

      account.enable_features!(described_class::FLAG)
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') { expect(described_class.liberado?(account)).to be(false) }
      expect(described_class.liberado?(nil)).to be(false)
    end
  end
end
