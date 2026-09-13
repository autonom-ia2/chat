require 'rails_helper'

# A FRONTEIRA DE SAÍDA, DOS DOIS LADOS (entrega das frases do especialista, 12/09/2026).
#
# `vetar` julga a frase que o MODELO escreveu: reprovar custa uma frase, porque existe constante de
# recuo para cada papel. `depurar` trata o texto FINAL, onde reprovar custaria a cotação do cliente:
# ela conserta e deixa passar.
#
# A PENEIRA ANTERIOR ERRAVA NOS DOIS SENTIDOS, e isso foi medido com Ruby antes de trocá-la:
# `/\b[a-z][a-z0-9]*\.[a-z][a-zA-Z0-9]*\b/` cortava `p.ex.`, `hub2you.ai`, `pdf.confira`,
# `contato@corretora.com.br` — e deixava passar `Já pedi.Aguarde` (acento quebra o `\b`) e
# `Ok.vou ver` (maiúscula). A daqui é uma lista fechada, derivada dos grupos que o código já declara.
module FrasesDaPeneira
  # CADA ACEITA É UMA FRASE QUE UM DOS QUATORZE PAPÉIS PRECISA PODER DIZER. Uma regra que as coma
  # empurra o papel para a constante, e aí a frase do especialista nunca chega ao cliente.
  ACEITAS = {
    'espera' => 'Já estou buscando os preços com as companhias e te trago aqui.',
    'abertura do primeiro lote' => 'Chegaram os primeiros:',
    'abertura de mais um' => 'Chegou mais uma:',
    'abertura de mais alguns' => 'Chegaram mais algumas:',
    'legenda do comparativo' => 'Segue o comparativo completo.',
    'sem veículo' => 'Para seguir eu preciso da placa do seu carro, ou do chassi se ele ainda não tem placa.',
    'ramo desconhecido' => 'Esse tipo de seguro eu ainda não consigo cotar por aqui.',
    'falhou' => 'Não consegui finalizar agora. Um atendente assume daqui.',
    'abreviação com ponto, que a peneira anterior comia' => 'Me diga o que preferir (p.ex. uma franquia maior).',
    'domínio, que a peneira anterior comia' => 'Qualquer coisa, estou em autonomia.ai.'
  }.freeze

  # CADA RECUSA É UMA REGRA, E CADA REGRA TEM UM DONO. As quatro primeiras são a decisão do CEO de
  # 12/09/2026 (nenhuma frase carrega número, contagem, valor, prazo, nome de seguradora, e o
  # travessão sai); as duas de identificador são o incidente de 08/09 (`insured.document` no
  # WhatsApp de um cliente); a crase é o modelo copiando o acento grave do manual; o vocabulário de
  # sistema é o que `Declaracao::ACEITA` já proíbe.
  RECUSAS = {
    'caminho de campo do formulário' => 'Faltou o insured.document',
    'caminho de campo de outro grupo' => 'Preciso do vehicle.plate',
    'caminho de campo do formulário dos outros ramos' => 'Confere o segurado.cpfCnpj',
    'folha camelCase' => 'Me manda o cpfCnpj',
    'folha camelCase no meio da frase' => 'Confere o valorMercado da bike',
    'vocabulário de sistema (o que o cliente leu em 08/09)' => 'Sua cotação está em conferência',
    'vocabulário de sistema, segunda palavra' => 'O status ainda é processando',
    'crase, que o modelo copia para o WhatsApp' => 'Mande o campo `dados` como JSON',
    'contagem' => 'Chegaram 3 opções:',
    'prazo' => 'Em até 5 minutos eu volto',
    'valor em reais' => 'Preço a partir de R$ 2.358,84',
    'moeda sem número' => 'O preço sai em R$, não em dólar',
    'travessão' => 'Comparativo — todas as opções',
    'meia-risca' => 'Comparativo – todas as opções',
    'vazia' => '   ',
    'ausente' => nil
  }.freeze
end

RSpec.describe Autonomia::Agents::Tools::TextoAoCliente do
  describe '.vetar' do
    FrasesDaPeneira::ACEITAS.each do |papel, frase|
      it "aceita a frase de #{papel}" do
        expect(described_class.vetar(frase)).to eq(frase)
      end
    end

    FrasesDaPeneira::RECUSAS.each do |regra, frase|
      it "recusa por #{regra}" do
        expect(described_class.vetar(frase)).to be_nil
      end
    end

    it 'recusa a frase longa demais, que estouraria o teto do texto composto' do
      expect(described_class.vetar('a' * (described_class::MAX_FRASE + 1))).to be_nil
      expect(described_class.vetar('a' * described_class::MAX_FRASE)).to be_present
    end

    it 'apara o que aceita' do
      expect(described_class.vetar("  Já estou vendo isso.  \n")).to eq('Já estou vendo isso.')
    end

    # O QUE A PENEIRA NOVA REPROVA E A ANTIGA NÃO REPROVAVA PELO MESMO MOTIVO, dito para não virar
    # surpresa: `hub2you.ai` é recusado, mas pela regra do DÍGITO, não pela do caminho de campo. E
    # `Já pedi.Aguarde` — ponto sem espaço — PASSA, de propósito: cobrir isso era o que comia
    # `p.ex.` e os domínios. Quem cobre má pontuação é o manual, não a guarda.
    it 'recusa o dominio com digito pela regra do digito, e aceita o ponto sem espaco' do
      expect(described_class.vetar('Estou no hub2you.ai')).to be_nil
      expect(described_class.vetar('Já pedi.Aguarde')).to eq('Já pedi.Aguarde')
    end

    # A LISTA DE GRUPOS VEM DO CÓDIGO QUE JÁ OS DECLARA, e não de uma cópia que envelhece sozinha.
    # Grupo novo no formulário sem entrada aqui é caminho de campo que passa.
    it 'cobre todo grupo que o formulario e a entrada declaram' do
      declarados = Autonomia::Insurance::Parametros::GRUPOS.keys | Autonomia::Insurance::QuoteInput::GRUPOS_DE_AUTO

      declarados.each do |grupo|
        expect(described_class.vetar("Me manda o #{grupo}.campo")).to be_nil, "#{grupo} não está na peneira"
      end
    end
  end

  describe '.depurar' do
    def depurar(texto)
      described_class.depurar(texto, teto: 3_000)
    end

    # ELA NÃO DESCARTA — é a mudança de 12/09/2026, e o motivo é de dinheiro: a entrega é
    # "abertura + dezessete preços + aviso" numa string só.
    it 'redige o caminho de campo e entrega o resto' do
      texto = depurar("Primeiros preços:\n\n• *Ezze*: R$ 2.050,40 no total\n\ninsured.document")

      expect(texto).to include('R$ 2.050,40')
      expect(texto).not_to include('insured.document')
    end

    it 'nao mexe em numero, moeda nem no link do comparativo' do
      texto = "Comparativo com todas as opções:\nhttps://portal.exemplo.test/cotacao/9.pdf"

      expect(depurar(texto)).to eq(texto)
      expect(depurar('• *Azul*: R$ 2.610,00 no total')).to eq('• *Azul*: R$ 2.610,00 no total')
    end

    it 'troca travessao e meia-risca por hifen' do
      expect(depurar('Porto Seguro — Cia de Seguros')).to eq('Porto Seguro - Cia de Seguros')
      expect(depurar('Porto – Cia')).to eq('Porto - Cia')
    end

    it 'corta no teto de quem chama' do
      expect(described_class.depurar('a' * 50, teto: 10).length).to eq(10)
    end

    it 'devolve nil quando nao sobra texto' do
      expect(depurar('   ')).to be_nil
    end

    # IDEMPOTÊNCIA É REQUISITO, não conveniência: a ferramenta depura para calcular a identidade da
    # entrega e o `Progress` depura de novo antes de publicar. Um segundo passo que mudasse o texto
    # daria token gravado ≠ token publicado, e o fecho perguntaria por uma mensagem inexistente.
    it 'e idempotente' do
      cru = "  Comparativo — placa ABC1D23, veja insured.document  \n"

      uma = depurar(cru)

      expect(depurar(uma)).to eq(uma)
    end
  end
end
