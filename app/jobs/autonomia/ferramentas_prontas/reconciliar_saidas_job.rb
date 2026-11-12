# A reconciliação dos IPs próprios das consultas grátis (#2942), a cada 10 minutos, na fila low. Separada da do
# WhatsApp (`WhatsappProxy::ReconcileJob`, #1516): uma não espera a outra.
#   - o IP de uma conta que sumiu da Webshare, saiu da fatia ou foi de molho é trocado já (só das contas com a flag; sem IP
#     livre, fica para a consulta seguinte, que sai pelo IP do servidor);
#   - alerta o IP da fatia que sumiu do plano, a fatia sem nenhum IP livre (`fatia_vazia`) e com menos de MINIMO_LIVRES
#     (`fatia_quase_vazia`). A conferência da fatia contra a reservada roda junto (`Fatia#fora_da_reservada`);
#   - a Webshare fora: alerta e tenta na próxima rodada.
# Sem fatia nesta stack e sem nenhuma conta com IP: não faz nada (a stack não usa o recurso).
class Autonomia::FerramentasProntas::ReconciliarSaidasJob < ApplicationJob
  queue_as :low

  MINIMO_LIVRES = 3

  def perform
    return unless fatia.configurada? || Autonomia::FerramentasProntas::ProxyDaConta.exists?

    lista = Autonomia::FerramentasProntas::Saida::ListaDaWebshare.proxies(fresca: true)
    trocar_os_que_nao_servem(lista)
    avisar_da_fatia(lista)
  rescue Webshare::Client::Error => e
    alerta.avisar!('webshare_indisponivel', "lista do plano datacenter indisponível (#{e.message})", nivel: :error)
  end

  private

  def trocar_os_que_nao_servem(lista)
    Autonomia::FerramentasProntas::ProxyDaConta.find_each do |registro|
      next if fatia.vivo(registro, lista) || !Autonomia::FerramentasProntas::Saida.ligada?(registro.account_id)

      Autonomia::FerramentasProntas::Saida.trocar!(registro.account_id, lista)
    rescue Autonomia::FerramentasProntas::Saida::SemIp => e
      Rails.logger.warn("[autonomia][pronta][saida] conta=#{registro.account_id} sem IP para trocar (#{e.message})")
    end
  end

  def avisar_da_fatia(lista)
    sumidos = fatia.enderecos - lista.map(&:address)
    if sumidos.any?
      alerta.avisar!('ip_da_fatia_sumiu', "#{sumidos.size} IP(s) de #{fatia::FATIA} sumiram do plano (#{fatia.mascarar(sumidos)})",
                     nivel: :error)
    end
    avisar_das_vagas(fatia.livres(lista, usados: Autonomia::FerramentasProntas::ProxyDaConta.pluck(:proxy_address)).size)
  end

  def avisar_das_vagas(livres)
    if livres.zero?
      alerta.avisar!('fatia_vazia', "nenhum IP livre em #{fatia::FATIA}: conta nova sai sem IP próprio", nivel: :error)
    elsif livres < MINIMO_LIVRES
      alerta.avisar!('fatia_quase_vazia', "só #{livres} IP(s) livre(s) em #{fatia::FATIA}")
    end
  end

  def fatia
    Autonomia::FerramentasProntas::Saida::Fatia
  end

  def alerta
    Autonomia::FerramentasProntas::Saida::Alerta
  end
end
