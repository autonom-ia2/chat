# ENDEREÇO PELO CEP, E O CEP PELO ENDEREÇO (#2858): BrasilAPI, com o ViaCEP de reserva (`cep/brasil_api.rb`,
# `cep/via_cep.rb`). O endereço de um CEP muda pouco: 30 dias de cache. Termos: as duas são gratuitas e sem chave; o
# ViaCEP pede uso moderado e bloqueia por abuso, e o cache e o limite por conta são a moderação. Só o endereço vai ao
# agente (sem coordenada nem código de serviço).
#
# Regra "QI 70" do Rodrigo (11/11/2026): o cliente diz a rua, não o CEP.
#   - por_endereco: o CEP pela rua e pela cidade (a UF sai dela, `Municipios`), no ViaCEP (`/ws/UF/cidade/rua/json/`,
#     a única das duas com essa busca). Rua longa tem um CEP por faixa de número: vêm até MAX_CEPS, com o bairro e a
#     faixa (`complemento`), para o agente escolher pelo número que o cliente disse;
#   - `Cep::Referencia.cep_da_cidade`: um CEP qualquer da cidade, para a fonte que pede o CEP só para saber a cidade.
module Autonomia::FerramentasProntas::Fontes::Cep
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  MAX_CEPS = 10
  # O ViaCEP recusa a rua com menos de 3 letras.
  MIN_LOGRADOURO = 3

  # `campos`: cep (8 dígitos), logradouro, bairro, cidade, uf. O CEP volta formatado; o vazio sai.
  def self.enxuto(campos)
    cep = campos.fetch(:cep)
    campos.merge(cep: "#{cep[0, 5]}-#{cep[5, 3]}").transform_keys(&:to_s).compact
  end

  # A pontuação que o ViaCEP recusa no nome da rua (responde 400): "Av. Brasil" vai como "Av Brasil" (varredura F02).
  PONTUACAO = '.,;:/\\#()"\''.freeze

  def self.logradouro(valor)
    texto = Parametro.texto_curto(valor.to_s.tr(PONTUACAO, ' '))
    texto if texto && texto.delete(' ').length >= MIN_LOGRADOURO
  end

  # O nome de cada CEP da rua, para a tela e para o agente: a rua, a faixa de número e o bairro ("Avenida Paulista, de
  # 612 a 1510 - lado par, Bela Vista"). Sem ele, a lista era só a contagem.
  def self.com_nome(item)
    nome = [item['logradouro'], item['complemento'], item['bairro']].compact_blank.join(', ')
    nome.present? ? { 'nome' => nome }.merge(item) : item
  end

  # Os CEPs da rua -> a resposta, com o mais parecido com a rua procurada primeiro e, na mesma rua, o CEP da rua (a
  # faixa de número) antes do especial (`especial?`): o ViaCEP manda os de prédio primeiro (a Paulista tem 50).
  def self.lista(municipio, logradouro, ceps)
    lista = Autonomia::FerramentasProntas::Lista
    ordem = lista.em_ordem(ceps, logradouro, desempate: ->(item) { especial?(item['cep']) ? 1 : 0 }) { |item| item['logradouro'] }
    { 'cidade' => municipio.nome, 'uf' => municipio.uf }.merge(lista.cortar(ordem.map { |item| com_nome(item) }, 'ceps', MAX_CEPS))
  end

  # Na estrutura do CEP dos Correios, o sufixo de 900 a 999 é CEP especial (grande usuário: um prédio, um órgão; caixa
  # postal; CEP promocional), não o da rua.
  SUFIXO_ESPECIAL = 900

  def self.especial?(cep)
    cep.to_s.delete('-')[5, 3].to_i >= SUFIXO_ESPECIAL
  end

  CEP = Parametro.new(
    nome: 'cep', descricao: 'Na consulta endereco: o CEP como o cliente escreveu (8 dígitos, com ou sem traço).',
    deduza: 'se o cliente disse a rua e a cidade, use a consulta por_endereco; senão, pergunte a ele o CEP.'
  ) { |valor| Parametro.digitos(valor, 8) }
  LOGRADOURO = Parametro.new(nome: 'logradouro', descricao: 'Na consulta por_endereco: o nome completo da rua, sem abreviar ' \
                                                            '(ex.: Avenida Paulista, não av paulista).',
                             pergunte: 'o nome da rua') { |valor| logradouro(valor) }
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'Na consulta por_endereco: a cidade da rua.', pergunte: 'a cidade do endereço') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Municipios.parametro_uf

  POR_ENDERECO = 'o CEP de uma rua; pede logradouro e cidade (a uf sai da cidade). Rua longa tem um CEP por faixa de ' \
                 'número: escolha pelo número e pelo bairro que o cliente disse; sem o número, mostre as opções.'.freeze

  # A rua que o ViaCEP não achou: quase sempre o nome abreviado ou incompleto (varredura F03, "av paulista").
  RUA_NAO_ENCONTRADA = 'Nenhum CEP com essa rua nessa cidade. Mande de novo com o nome completo da rua, sem abreviar ' \
                       '(Avenida Paulista, não av paulista), e confira a cidade; se ainda não achar, pergunte ao cliente o ' \
                       'CEP. Não invente.'.freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'cep', slug: 'pronta_cep', nome: 'Endereço pelo CEP', consulta_padrao: 'endereco',
    descricao: 'Consulta oficial e gratuita do endereço de um CEP (rua, bairro, cidade e UF), e do CEP de uma rua.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'endereco', descricao: 'o endereço do CEP; pede cep', obrigatorios: [CEP], provedores: [BrasilApi, ViaCep],
        validade: 30.days, prazo_por_fonte: 3, prazo_total: 6
      ),
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'por_endereco', descricao: POR_ENDERECO, obrigatorios: [LOGRADOURO, CIDADE], opcionais: [UF], provedores: [ViaCep],
        validade: 30.days, prazo_por_fonte: 4, prazo_total: 4, regra: ->(params) { Municipios.falta(params['uf'], params['cidade']) },
        nao_encontrado: RUA_NAO_ENCONTRADA
      )
    ],
    limite_diario: 500,
    termos: 'BrasilAPI e ViaCEP: gratuitas, sem chave; o ViaCEP bloqueia uso abusivo. Só o ViaCEP acha o CEP pela rua. ' \
            'Cache de 30 dias.'
  )
end
