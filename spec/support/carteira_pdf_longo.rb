# E6 (#2899): a apólice fictícia de 160 páginas dos specs do leitor ("PDF de 160 páginas não manda 160 páginas ao
# modelo"). É montada na hora, uma vez por processo de teste, para o repositório não carregar um PDF grande. Tudo
# inventado; o CPF tem dígito verificador inválido de propósito. Os dados do seguro estão nas páginas 1 e 2, o CPF do
# segurado aparece nas páginas 1, 2 e 160, e o resto são condições gerais sem dado de seguro nenhum.
module CarteiraPdfLongo
  TOTAL = 160
  COMECO = [
    ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO RESIDENCIAL', '',
     'Apólice nº: RS-0114.000777', 'Ramo: 0114 - Compreensivo Residencial', 'Vigência: 01/02/2027 a 01/02/2028', '',
     'SEGURADO', 'Nome: Renata Amostra Lima        CPF: 987.654.321-99', '',
     'IMÓVEL SEGURADO', 'Rua do Modelo, 45, apto 12 - Bairro Exemplo - Cidade Exemplo/EX', '',
     'Prêmio total: R$ 890,40'],
    ['DADOS PARA CONTATO DO SEGURADO', 'Renata Amostra Lima        CPF: 987.654.321-99',
     'Telefone: (31) 96666-0008        E-mail: renata.amostra@exemplo.invalid', '',
     'CORRETOR', 'Corretora Amostra de Seguros Ltda. - (11) 3000-0002']
  ].freeze
  FIM = ['ANEXO - DADOS DE COBRANÇA', 'Titular: Renata Amostra Lima        CPF: 987.654.321-99', 'Débito em conta, todo dia 10.'].freeze

  def self.paginas
    meio = (COMECO.size + 1...TOTAL).map do |numero|
      ['CONDIÇÕES GERAIS DO SEGURO RESIDENCIAL', "Página #{numero} de #{TOTAL}", '',
       "Cláusula #{numero}: texto de exemplo das condições gerais, sem dado de nenhum seguro em particular."]
    end
    COMECO + meio + [FIM]
  end

  # O caminho do PDF, montado na primeira vez em que alguém pede e apagado quando o processo termina.
  def self.caminho
    @caminho ||= montar
  end

  def self.montar
    Prawn::Fonts::AFM.hide_m17n_warning = true
    caminho = File.join(Dir.tmpdir, "carteira_apolice_longa_#{Process.pid}.pdf")
    Prawn::Document.generate(caminho, page_size: 'A4', margin: 48, compress: true) do |documento|
      documento.font_size 10
      paginas.each_with_index do |linhas, indice|
        documento.start_new_page unless indice.zero?
        linhas.each { |linha| linha.empty? ? documento.move_down(8) : documento.text(linha) }
      end
    end
    at_exit { FileUtils.rm_f(caminho) }
    caminho
  end
  private_class_method :montar
end
