module Autonomia
  module Agents
    module Knowledge
      module Processors
        # Mapa source_type -> classe de processador: Processors::Dispatcher.for(source).
        # #1426 — o atalho `Processors.for` saiu: ele só existia depois de este arquivo carregar, e com
        # carga sob demanda (dev, teste) o primeiro uso quebrava com NoMethodError.
        class Dispatcher
          MAP = {
            'link' => Link,
            'txt'  => Text,
            'md'   => Text,
            'json' => Json,
            'pdf'  => Pdf,
            'xlsx' => Xlsx,
            'docx' => Docx,
            'foto' => Foto
          }.freeze

          def self.for(source)
            klass = MAP[source.source_type.to_s]
            raise Base::UnsupportedFormat, "unsupported_source_type: #{source.source_type}" if klass.nil?

            klass.new(source)
          end
        end
      end
    end
  end
end
