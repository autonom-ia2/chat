<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIdioma } from '../../ficha/idioma';
import {
  SITUACOES_DA_COTACAO as S,
  VARIACOES as V,
  emReais,
  equipeFoiAvisada,
  mostraAProposta,
  situacaoDaCotacao,
  variacaoDaCotacao,
} from '../../carteira/cotacaoDaRenovacao';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2901 (E8) — "Cotação" na gaveta do seguro (a mesma da lista, da ficha e do
// painel da conversa): em que pé está a cotação da renovação, numa frase de
// gente (nunca o código do servidor), o preço da proposta e quanto ele subiu
// ou caiu em relação ao ano passado. Com a proposta pronta e ainda não
// enviada, quem pode (carteira/cotacaoDaRenovacao.js, `podeEnviarProposta`)
// tem "Enviar proposta": nada vai ao cliente antes desse clique. Quem manda é
// a gaveta, que diz o que houve no rodapé. Só existe no seguro que tem
// cotação: quem a usa só a monta quando há etapa (`cotacao.etapa`).
// #3057 (2ª rodada) — o botão "Enviar proposta" saiu daqui: ele é o azul do
// rodapé da gaveta (carteira/rodapeDoSeguro.js). Aqui fica só a linha que diz
// que nada vai ao cliente antes do toque.
const props = defineProps({
  seguro: { type: Object, required: true },
  podeEnviar: { type: Boolean, default: false },
});

const { t } = useI18n();
const textos = useTextosDoSeguro();
const idioma = useIdioma();
const idDoTitulo = useId();

const cotacao = computed(() => props.seguro.cotacao);
const situacao = computed(() => situacaoDaCotacao(cotacao.value));
const valor = centavos => textos.valor(emReais(centavos));

// As frases do catálogo, cada uma pela chave inteira: o nome de cada campo que
// faltou (pela chave de carteira/cotacaoDaRenovacao.js, `camposQueFaltam`), o
// motivo da cotação que não saiu e o da pergunta que não saiu.
const NOMES_DOS_CAMPOS = {
  PRODUTO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.PRODUTO'),
  QUOTATION_PREVIOUSINSURERCODE: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.QUOTATION_PREVIOUSINSURERCODE'),
  QUOTATION_PREVIOUSPOLICYNUMBER: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.QUOTATION_PREVIOUSPOLICYNUMBER'),
  QUOTATION_PREVIOUSPOLICYENDDATE: () =>
    t(
      'RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.QUOTATION_PREVIOUSPOLICYENDDATE'
    ),
  QUOTATION_BONUSCLASS: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.QUOTATION_BONUSCLASS'),
  INSURED_NAME: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.INSURED_NAME'),
  INSURED_DOCUMENT: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.INSURED_DOCUMENT'),
  INSURED_BIRTHDATE: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.INSURED_BIRTHDATE'),
  INSURED_GENDER: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.INSURED_GENDER'),
  ADDRESS_ZIPCODE: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.ADDRESS_ZIPCODE'),
  VEHICLE_PLATE: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.VEHICLE_PLATE'),
  RENOVACAO_SEGURADORAANTERIOR: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.RENOVACAO_SEGURADORAANTERIOR'),
  RENOVACAO_NUMEROAPOLICE: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.RENOVACAO_NUMEROAPOLICE'),
  RENOVACAO_FIMVIGENCIA: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.RENOVACAO_FIMVIGENCIA'),
  RENOVACAO_BONUS: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.RENOVACAO_BONUS'),
  SEGURADO_CPFCNPJ: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.SEGURADO_CPFCNPJ'),
  SEGURADO_NOME: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.SEGURADO_NOME'),
  SEGURADO_CEP: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.CAMPOS.SEGURADO_CEP'),
};
const MOTIVOS = {
  CONFERENCIA_CAIU: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.CONFERENCIA_CAIU'),
  SEM_CONEXAO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.SEM_CONEXAO'),
  SEM_AGENTE: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.SEM_AGENTE'),
  COTACAO_FALHOU: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.COTACAO_FALHOU'),
  SEM_PRECO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.SEM_PRECO'),
  SEM_PDF: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.SEM_PDF'),
  ENVIO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.MOTIVO.ENVIO'),
};
const MOTIVOS_DO_ENVIO = {
  CONTATO_RECUSOU: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.CONTATO_RECUSOU'),
  SEM_CAIXA: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.SEM_CAIXA'),
  SEM_MODELO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.SEM_MODELO'),
  SEM_TELEFONE: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.SEM_TELEFONE'),
  CAMPO_VAZIO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.CAMPO_VAZIO'),
  SEM_CARD: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIO.SEM_CARD'),
};
const SITUACOES_SIMPLES = {
  PERGUNTOU: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.PERGUNTOU'),
  PERGUNTA_NAO_SAIU: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.PERGUNTA_NAO_SAIU'),
  NADA_MUDOU: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.NADA_MUDOU'),
  MUDOU: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.MUDOU'),
  CLIENTE_CONTOU: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.CLIENTE_CONTOU'),
  COTANDO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.COTANDO'),
  NAO_SAIU_SEM_MOTIVO: () =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.NAO_SAIU_SEM_MOTIVO'),
  ANDANDO: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.ANDANDO'),
  INCERTA: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.INCERTA'),
};
const VARIACOES = {
  [V.SUBIU]: percentual =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.VARIACAO.SUBIU', { percentual }),
  [V.CAIU]: percentual =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.VARIACAO.CAIU', { percentual }),
  [V.IGUAL]: () => t('RELACIONAMENTOS_CARTEIRA.COTACAO.VARIACAO.IGUAL'),
};

// "nascimento do segurado, CEP e placa do veículo", no idioma do painel. Dois
// campos com o mesmo nome em português aparecem uma vez só.
const emLista = nomes =>
  new Intl.ListFormat(idioma.value, { type: 'conjunction' }).format(nomes);
const camposEscritos = ({ campos, outros }) => {
  const nomes = new Set(campos.map(campo => NOMES_DOS_CAMPOS[campo]()));
  if (outros) nomes.add(t('RELACIONAMENTOS_CARTEIRA.COTACAO.OUTROS_DADOS'));
  return emLista([...nomes]);
};

const daProposta = ({ premioCentavos, seguradora }) => ({
  valor: valor(premioCentavos),
  seguradora,
});
const propostaPronta = s =>
  s.seguradora
    ? t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.PRONTA', daProposta(s))
    : t(
        'RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.PRONTA_SEM_SEGURADORA',
        daProposta(s)
      );
const quando = s => ({ data: textos.dataInteira(s.enviadaEm) });

const FRASES = {
  [S.FALTAM]: s =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.FALTAM', {
      campos: camposEscritos(s),
    }),
  [S.NAO_SAIU]: s => MOTIVOS[s.motivo.toUpperCase()](),
  [S.PRONTA]: propostaPronta,
  [S.ENVIADA]: s =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.ENVIADA', quando(s)),
  [S.ENVIADA_SOZINHA]: s =>
    t('RELACIONAMENTOS_CARTEIRA.COTACAO.SITUACAO.ENVIADA_SOZINHA', quando(s)),
};
const frase = computed(() => {
  const { id } = situacao.value;
  return (FRASES[id] ?? SITUACOES_SIMPLES[id])(situacao.value);
});

// #3043 (E8.1) — faltou algo que a apólice traz escrito: a frase de baixo
// ensina o caminho (anexar o PDF da apólice ou corrigir o seguro à mão).
const ensinaOCaminho = computed(
  () => situacao.value.id === S.FALTAM && situacao.value.daApolice
);

// A pergunta "Algo mudou?" que não saiu diz por quê, quando a tela sabe.
const porQueNaoSaiu = computed(() =>
  situacao.value.id === S.PERGUNTA_NAO_SAIU && situacao.value.motivo
    ? MOTIVOS_DO_ENVIO[situacao.value.motivo.toUpperCase()]()
    : ''
);
const proposta = computed(() => {
  if (!mostraAProposta(cotacao.value)) return '';
  return cotacao.value.seguradora
    ? t('RELACIONAMENTOS_CARTEIRA.COTACAO.PROPOSTA', daProposta(cotacao.value))
    : t(
        'RELACIONAMENTOS_CARTEIRA.COTACAO.PROPOSTA_SEM_SEGURADORA',
        daProposta(cotacao.value)
      );
});
const variacao = computed(() => {
  const achada = variacaoDaCotacao(cotacao.value);
  return achada
    ? VARIACOES[achada.id](textos.percentual(achada.percentual))
    : '';
});
const avisada = computed(() => equipeFoiAvisada(situacao.value));
</script>

<template>
  <section
    data-carteira="cotacao-do-seguro"
    :data-etapa="cotacao.etapa"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-3"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ t('RELACIONAMENTOS_CARTEIRA.COTACAO.TITULO') }}
    </h3>
    <p
      data-carteira="situacao-da-cotacao"
      class="m-0 text-base break-words text-n-slate-12"
    >
      {{ frase }}
    </p>
    <p
      v-if="ensinaOCaminho"
      data-carteira="como-completar"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_CARTEIRA.COTACAO.COMO_COMPLETAR') }}
    </p>
    <p
      v-if="porQueNaoSaiu"
      data-carteira="por-que-nao-saiu"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ porQueNaoSaiu }}
    </p>
    <p
      v-if="proposta"
      data-carteira="proposta-da-cotacao"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ proposta }}
    </p>
    <p
      v-if="variacao"
      data-carteira="variacao-da-cotacao"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ variacao }}
    </p>
    <p
      v-if="avisada"
      data-carteira="equipe-avisada"
      class="m-0 text-sm break-words text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_CARTEIRA.COTACAO.AVISADA') }}
    </p>
    <p
      v-if="podeEnviar"
      data-carteira="enviar-apoio"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_CARTEIRA.COTACAO.ENVIAR_APOIO') }}
    </p>
  </section>
</template>
