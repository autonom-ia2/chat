module Autonomia
  module Agents
    module Knowledge
      module Processors
        # Mapa source_type -> classe de processador. Contrato público (spec): Processors.for(source).
        # O método vive na classe Dispatcher (zeitwerk: dispatcher.rb -> Processors::Dispatcher) e é
        # exposto como Processors.for por conveniência/compatibilidade com o spec.
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

        def self.for(source)
          Dispatcher.for(source)
        end
      end
    end
  end
end
