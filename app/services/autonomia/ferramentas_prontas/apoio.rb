# O APOIO DE UMA CONSULTA (#2858, regra "QI 70" do Rodrigo, 11/11/2026): outra consulta da MESMA fonte que a plataforma
# faz sozinha para deduzir um dado técnico, em vez de o agente perguntar ao cliente. Exemplo: o preço da FIPE recebe a
# marca e o modelo pelo nome, e o código sai das listas de marcas e de modelos (`Fontes::Fipe::PeloNome`).
#
# Mesmo caminho da `Execucao`, sem o contador (a consulta do agente já contou no limite do dia): o cache da fonte, os
# provedores em ordem, o mesmo cliente HTTP (hosts, prazo final e teto) da consulta que pediu o apoio.
class Autonomia::FerramentasProntas::Apoio
  Provedor = Autonomia::FerramentasProntas::Provedor
  Cache = Autonomia::FerramentasProntas::Cache

  # Nenhum provedor respondeu: a consulta do agente vira "não consegui", com os motivos de cada um.
  class SemResposta < StandardError
    attr_reader :motivos

    def initialize(motivos)
      @motivos = motivos
      super('sem_resposta')
    end
  end

  def initialize(fonte, cliente)
    @fonte = fonte
    @cliente = cliente
  end

  # -> os dados da fonte (do cache ou do primeiro provedor que responder), ou nil quando a fonte diz que não tem.
  def dados(nome_da_consulta, params)
    consulta = @fonte.consulta(nome_da_consulta)
    cache = Cache.new(@fonte, consulta, params)
    guardado = cache.ler
    return guardado['situacao'] == Cache::ENCONTRADO ? guardado['dados'] : nil if guardado

    dos_provedores(consulta, params, cache)
  end

  private

  def dos_provedores(consulta, params, cache)
    falhas = []
    consulta.provedores.select { |provedor| provedor.aplica?(consulta, params) }.each do |provedor|
      dados = provedor.new(@cliente, prazo: consulta.prazo_por_fonte).consultar(consulta, consulta.para_a_fonte(params))
      cache.encontrado(dados, validade: provedor.validade)
      return dados
    rescue Provedor::NaoEncontrado
      raise SemResposta, falhas if falhas.any?

      cache.nao_encontrado
      return nil
    rescue Provedor::Falha => e
      falhas << "#{provedor.nome}.#{e.motivo}"
    end
    raise SemResposta, falhas.presence || ['sem_provedor']
  end
end
