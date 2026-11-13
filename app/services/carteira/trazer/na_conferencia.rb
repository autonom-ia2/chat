# "Trazer minha lista" com seguros (E4, #2897): o que a conferência mostra a mais quando a planilha tem seguros. Quem
# monta a leitura para a tela (Relacionamentos::Trazer::Leitura, Exemplos, Problemas) pergunta aqui; sem a resposta
# "sim" numa conta com a carteira, `da` devolve nil e a tela recebe a leitura de sempre.
#
# Cada número diz se conta SEGUROS (linhas: uma linha é um seguro) ou PESSOAS, e nenhum mexe nos contadores de linha
# do importador:
# - `seguros`: quantos entram se a pessoa mandar trazer agora (ContactImports::Trazer::QuemEntra, a conta de sempre);
# - `pessoas`: de quantas pessoas são esses seguros (Carteira::Trazer::PessoasQueEntram); `clientes` passa a ser esse
#   número, porque quem entra com seguro vira cliente;
# - `pessoasQueJaEstavam`: dessas, quantas a conta já tinha, contado na leitura;
# - `porTipo`: os seguros que entram, por tipo (o ramo de cada linha com o tipo que a leitura decidiu);
# - `repetidos`: linhas iguais a outra, que a leitura tirou.
# Enquanto falta coluna obrigatória (`faltam`), as linhas ainda não foram conferidas como seguro e só o bloco existe.
#
# Os exemplos ganham os seguros de cada pessoa; linhas seguidas da mesma pessoa viram um exemplo só.
class Carteira::Trazer::NaConferencia
  RAMO = 'seguro_tipo'.freeze
  DA_PESSOA = %i[telefone email].freeze

  def self.da(importacao)
    colunas = Carteira::Trazer::ColunasDeSeguro.da(importacao)
    new(importacao, colunas) if colunas
  end

  attr_reader :colunas

  def initialize(importacao, colunas)
    @importacao = importacao
    @colunas = colunas
    @tipos = Carteira::Trazer::TipoDoRamo.new(importacao)
  end

  def bloco
    { destinos: Carteira::Trazer::ColunasDeSeguro::DESTINOS, faltam: @colunas.faltam }
  end

  # quem_entra: ContactImports::Trazer::QuemEntra.
  def resumo(quem_entra)
    return {} unless @colunas.completas?

    pessoas = Carteira::Trazer::PessoasQueEntram.new(@importacao, quem_entra).quantas
    contado = @importacao.validation_summary.to_h
    { seguros: quem_entra.quantas, pessoas: pessoas, clientes: pessoas, pessoasQueJaEstavam: contado['pessoas_que_ja_estavam'].to_i,
      porTipo: por_tipo(quem_entra), repetidos: contado['seguros_repetidos'].to_i }
  end

  # exemplos: [{ linha:, nome:, telefone:, email:, empresa:, cliente: }]; valores: { número da linha => extra_values }.
  def nos_exemplos(exemplos, valores)
    return exemplos unless @colunas.completas?

    exemplos.each_with_object([]) do |exemplo, pessoas|
      com_seguro = exemplo.merge(cliente: true, seguros: [seguro(valores.fetch(exemplo[:linha], {}))])
      anterior = pessoas.last
      next pessoas << com_seguro unless anterior && mesma_pessoa?(anterior, com_seguro)

      pessoas[-1] = anterior.merge(seguros: anterior[:seguros] + com_seguro[:seguros])
    end
  end

  private

  def por_tipo(quem_entra)
    zerado = Carteira::Apolice::TIPOS.index_with { 0 }
    quem_entra.por_valor(@colunas.chave(RAMO)).each_with_object(zerado) { |(ramo, linhas), soma| soma[@tipos.de(ramo)] += linhas }
  end

  def seguro(extra_values)
    lido = Carteira::Trazer::SeguroLido.call(@colunas.valores(extra_values))
    dados = lido.atributos
    { tipo: @tipos.de(lido.ramo), ramoOriginal: lido.ramo, seguradora: dados[:seguradora], numero: dados[:numero],
      comeca: dados[:inicio_vigencia]&.iso8601, termina: dados[:fim_vigencia]&.iso8601,
      valor: Carteira::Campos.em_reais(dados[:valor_centavos]), bem: dados[:bem] }
  end

  def mesma_pessoa?(uma, outra)
    DA_PESSOA.any? { |campo| uma[campo].present? && uma[campo] == outra[campo] }
  end
end
