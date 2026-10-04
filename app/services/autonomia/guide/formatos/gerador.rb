# Gera o formato de todas as ações do catálogo do Guia (#900).
#
# Roda no build (rake `autonomia:guia:formatos`) e no spec que confere se o
# JSON versionado está em dia — nunca numa requisição do Guia, que só lê o
# arquivo. Precisa do banco de pé só para o esquema das tabelas (tipo e padrão
# de cada coluna); nada é gravado.
class Autonomia::Guide::Formatos::Gerador
  Formatos = ::Autonomia::Guide::Formatos

  def formatos
    Formatos::RotasDeEscrita.todas.to_h { |rota| [rota.acao, formato(rota)] }
  end

  # Os parâmetros de cada leitura do catálogo (#942).
  def leituras
    Formatos::RotasDeLeitura.todas.to_h do |rota|
      klass = "#{rota.controller.camelize}Controller".safe_constantize if rota.controller.present?
      [rota.acao, klass ? Formatos::ParametrosDaLeitura.new(klass, rota).formato : sem_controller(rota).slice('controller', 'motivos')]
    end
  end

  private

  def formato(rota)
    klass = "#{rota.controller.camelize}Controller".safe_constantize
    return sem_controller(rota) unless klass

    Formatos::Acao.new(klass, rota).formato
  end

  def sem_controller(rota)
    { 'controller' => "#{rota.controller}##{rota.action}", 'completo' => false, 'motivos' => ['controller não encontrado'],
      'sem_corpo' => false }
  end
end
