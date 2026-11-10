# DADOS DA EMPRESA PELO CNPJ (#2858): BrasilAPI, depois a Minha Receita, depois a OpenCNPJ (`cnpj/*.rb`). Cache de 1 dia:
# a situação cadastral muda, e a pergunta de quem atende é "está ativa hoje?".
# Só o que identifica a empresa vai ao agente: razão social, nome fantasia, situação, abertura, atividade principal,
# natureza, porte e cidade. Ficam de fora sócios, e-mail e telefone: o agente responde a qualquer um no WhatsApp.
module Autonomia::FerramentasProntas::Fontes::Cnpj
  def self.formatado(cnpj)
    "#{cnpj[0, 2]}.#{cnpj[2, 3]}.#{cnpj[5, 3]}/#{cnpj[8, 4]}-#{cnpj[12, 2]}"
  end

  # `campos`: o nosso nome -> o nome do campo na resposta da fonte. Sem razão social, a resposta não serve (a fonte
  # mudou o formato): falha, e a reserva tenta. Situação e porte vão em maiúsculas em todas as fontes.
  def self.enxuto(cnpj, dado, campos:, atividade:)
    valores = campos.to_h { |nosso, deles| [nosso.to_s, dado[deles].to_s.strip.presence] }
    raise Autonomia::FerramentasProntas::Provedor::Falha, 'resposta_invalida' if valores['razao_social'].nil?

    %w[situacao porte].each { |campo| valores[campo] = valores[campo]&.upcase }
    principal = atividade.transform_values { |valor| valor.to_s.strip.presence }.compact.presence
    { 'cnpj' => formatado(cnpj) }.merge(valores.compact).merge({ 'atividade_principal' => principal }.compact)
  end

  CNPJ = Autonomia::FerramentasProntas::Parametro.new(
    nome: 'cnpj', descricao: 'O CNPJ como o cliente escreveu (14 posições, com ou sem pontuação).'
  ) { |valor| Autonomia::FerramentasProntas::Parametro.cnpj(valor) }

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'cnpj', slug: 'pronta_cnpj', nome: 'Dados da empresa',
    descricao: 'Consulta oficial e gratuita dos dados públicos de uma empresa pelo CNPJ: razão social, situação ' \
               'cadastral, data de abertura, atividade principal, porte e cidade.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'empresa', descricao: 'os dados públicos da empresa', obrigatorios: [CNPJ],
        provedores: [BrasilApi, MinhaReceita, OpenCnpj], validade: 1.day, prazo_por_fonte: 4, prazo_total: 9
      )
    ],
    limite_diario: 200,
    termos: 'BrasilAPI, Minha Receita e OpenCNPJ: gratuitas, sem chave, dados abertos da Receita. Cache de 1 dia.'
  )
end
