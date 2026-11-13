# A busca de uma consulta pronta (#2934, ConsultasProntas): a mesma Execucao das Ferramentas prontas dos agentes (#2858),
# numa ferramenta que não é salva, como o "Experimente" da vitrine faz. Vale tudo o que vale para o agente: provedores
# em ordem com reserva, cache, o limite do dia da conta naquela fonte (o mesmo que os agentes gastam), o corte e o log
# sem o valor consultado. Serve ao motor (PassoConsultar), ao "Fazer um teste" do editor e ao "Buscar agora" do ensaio.
#
# Volta a mesma Resposta da ConsultaDeFora, com `dados` já prontos para a pessoa: { caminho => texto }, só os que
# vieram (o preço em reais, a data no formato daqui, sim ou não).
class Autonomia::Automacao::ConsultaPronta
  Resposta = ::Autonomia::Automacao::ConsultaDeFora::Resposta
  ConsultasProntas = ::Autonomia::Automacao::ConsultasProntas
  # O que a ferramenta respondeu, no motivo que a pessoa lê (autonomia.automacao.motivos.*).
  SITUACOES = { 'nao_encontrado' => 'consulta_pronta_nao_achou', 'pedido_invalido' => 'consulta_pronta_dado_invalido',
                'documento_invalido' => 'consulta_pronta_dado_invalido' }.freeze

  # `entradas`: { 'cep' => '01310-100' }, já montadas (ConsultasProntas.entradas_montadas) ou digitadas no teste.
  def initialize(conta, pronta, entradas)
    @conta = conta
    @pronta = pronta
    @entradas = entradas.to_h.transform_keys(&:to_s)
  end

  def buscar
    return falhou('consulta_pronta_desligada') if @pronta.nil?

    falta = ConsultasProntas.falta(@conta, @pronta)
    return falhou("consulta_pronta_#{falta}") if falta
    return falhou('consulta_pronta_sem_dado') if @pronta.entradas.any? { |entrada| @entradas[entrada].to_s.strip.empty? }

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    lido(JSON.parse(executar), inicio)
  end

  private

  # A Execucao exige o acesso da conta na fonte (a chave interna do contador e do limite); nasce aqui se ainda não existe,
  # como no "Experimente".
  def executar
    ::Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @conta.id, fonte: @pronta.fonte)
    ferramenta = ::Autonomia::Agents::Tool.new(account: @conta, fonte_pronta: @pronta.fonte)
    ::Autonomia::FerramentasProntas::Execucao.new(tool: ferramenta, params: argumentos).call
  end

  def argumentos
    entradas = @pronta.entradas.index_with { |entrada| @entradas[entrada].to_s.strip }
    { ::Autonomia::FerramentasProntas::Fonte::PARAMETRO_DA_CONSULTA => @pronta.consulta }.merge(@pronta.fixos, entradas)
  end

  def lido(resposta, inicio)
    situacao = resposta['situacao']
    return falhou(SITUACOES.fetch(situacao, 'consulta_pronta_sem_resposta'), inicio) unless situacao == 'encontrado'

    dados = @pronta.dados.each_with_object({}) do |dado, lidos|
      valor = Formato.texto(::Autonomia::Automacao::ConsultaDeFora.valor_em(resposta['dados'], dado.caminho), dado.formato)
      lidos[dado.caminho] = valor if valor.present?
    end
    return falhou('consulta_pronta_nao_achou', inicio) if dados.empty?

    Resposta.new(codigo: 200, ms: ms(inicio), dados: dados)
  end

  def falhou(motivo, inicio = nil) = Resposta.new(motivo: motivo, ms: inicio && ms(inicio), dados: nil)

  def ms(inicio) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round

  # O valor de uma consulta pronta como texto para a pessoa. Sem expressão regular: o parser de data e o formatador de
  # número do Rails.
  module Formato
    # Cada formato é um método deste módulo; `:texto` (o padrão) só aceita valor simples.
    FORMATOS = %i[dinheiro data mes sim_ou_nao lista].freeze

    module_function

    def texto(valor, formato)
      return if valor.nil? || valor == ''
      return public_send(formato, valor) if FORMATOS.include?(formato)

      valor.is_a?(Array) || valor.is_a?(Hash) ? nil : valor.to_s
    end

    def sim_ou_nao(valor) = I18n.t("#{ConsultasProntas::T}.#{valor == true ? 'sim' : 'nao'}")

    def lista(valor) = Array(valor).map(&:to_s).join(', ')

    def dinheiro(valor)
      numero = Float(valor, exception: false)
      return valor.to_s if numero.nil?

      ActiveSupport::NumberHelper.number_to_currency(numero, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n')
    end

    # "1966-08-01" => "01/08/1966".
    def data(valor)
      Date.iso8601(valor.to_s).strftime('%d/%m/%Y')
    rescue Date::Error
      valor.to_s
    end

    # "2026-11" => "11/2026".
    def mes(valor)
      ano, numero = valor.to_s.split('-')
      numero.present? ? "#{numero}/#{ano}" : valor.to_s
    end
  end
end
