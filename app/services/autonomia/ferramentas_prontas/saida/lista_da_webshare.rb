# A lista do plano datacenter da Webshare, com a credencial de cada IP, para as consultas grátis (#2942). Reaproveita o
# cliente do WhatsApp Híbrido (`Webshare::Client.new(pool: :datacenter)`, #1516), sem mudar nada nele.
# A lista fica SÓ na memória deste processo, por VALIDADE: nunca no Redis, no banco ou no log (o `Webshare::Proxy` não
# mostra a credencial em inspect, to_s nem JSON). A Webshare fora: o erro é lembrado por ESPERA, para cada consulta não
# esperar o prazo do cliente de novo; a consulta sai pelo IP do servidor (`Saida#sem_ip_proprio`).
module Autonomia::FerramentasProntas::Saida::ListaDaWebshare
  VALIDADE = 3.minutes.to_i
  ESPERA = 1.minute.to_i
  TRAVA = Mutex.new

  class << self
    # `fresca: true` (a reconciliação) busca de novo, mesmo com a lista na validade.
    def proxies(fresca: false)
      TRAVA.synchronize do
        raise @falha if !fresca && @falha && recente?(@falhou_em, ESPERA)
        return @lista if !fresca && @lista && recente?(@lida_em, VALIDADE)

        buscar
      end
    end

    # A credencial pode ter mudado (o proxy recusou o túnel): a próxima consulta busca de novo.
    def esquecer!
      TRAVA.synchronize { @lista = @lida_em = @falha = @falhou_em = nil }
    end

    private

    def buscar
      @lista = Webshare::Client.new(pool: :datacenter).proxies
      @lida_em = agora
      @falha = nil
      @lista
    rescue Webshare::Client::Error => e
      @lista = nil
      @falha = e
      @falhou_em = agora
      raise
    end

    def recente?(instante, segundos)
      instante && agora - instante < segundos
    end

    def agora
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
