/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { PELES, fornecerPele } from '../pele';
import { abrirSeletorDeArquivo, usePeleDaResposta } from '../usePeleDaResposta';
import { idiomaDoPainel } from '../dataDaConversa';

// Monta o hook dentro de uma "conversa" que fornece (ou não) a pele.
const usar = ({ pele, conversa = {} }) => {
  let resultado;
  const Filho = defineComponent({
    setup() {
      resultado = usePeleDaResposta();
      return () => null;
    },
  });
  const Conversa = defineComponent({
    setup() {
      if (pele !== undefined) fornecerPele(computed(() => pele));
      return () => h(Filho);
    },
  });
  const store = createStore({
    getters: { getSelectedChat: () => conversa },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: {
      pt_BR: { CONVERSA_CANAL: { CAIXA: { DIGITE: 'Digite uma mensagem' } } },
    },
  });
  mount(Conversa, { global: { plugins: [store, i18n] } });
  return resultado;
};

describe('usePeleDaResposta (#1702)', () => {
  it('sem pele (chave desligada ou outro canal): nada muda na caixa', () => {
    const r = usar({ pele: undefined });
    expect(r.ehWhatsapp.value).toBe(false);
    expect(r.textoDoCampo.value).toBe('');
    expect(r.soTexto.value).toBe(false);
    expect(Object.values(r.classesDaResposta.value).every(v => v === '')).toBe(
      true
    );
  });

  it('com a pele do WhatsApp: texto do app e classes da barra', () => {
    const r = usar({ pele: PELES.WHATSAPP });
    expect(r.ehWhatsapp.value).toBe(true);
    expect(r.textoDoCampo.value).toBe('Digite uma mensagem');
    expect(r.classesDaResposta.value.enviar).not.toBe('');
  });

  it('número reserva fora das 24 h: só texto', () => {
    const r = usar({
      pele: PELES.WHATSAPP,
      conversa: { whatsapp_api_reply: true },
    });
    expect(r.soTexto.value).toBe(true);
  });
});

describe('idiomaDoPainel', () => {
  it('troca o "_" do painel pelo "-" do Intl', () => {
    expect(idiomaDoPainel('pt_BR')).toBe('pt-BR');
    expect(idiomaDoPainel('en')).toBe('en');
    expect(idiomaDoPainel(undefined)).toBe('en');
  });
});

describe('abrirSeletorDeArquivo (#1702)', () => {
  let campo;
  beforeEach(() => {
    campo = document.createElement('input');
    campo.type = 'file';
    campo.id = 'conversationAttachment';
    campo.setAttribute('accept', 'image/*,audio/*,.pdf');
    campo.click = vi.fn();
    document.body.appendChild(campo);
  });
  afterEach(() => campo.remove());

  it('Documento abre o seletor de sempre', () => {
    abrirSeletorDeArquivo();
    expect(campo.click).toHaveBeenCalled();
    expect(campo.getAttribute('accept')).toBe('image/*,audio/*,.pdf');
  });

  it('Fotos e vídeos filtra a mídia e devolve o filtro de sempre depois', () => {
    abrirSeletorDeArquivo('image/*,video/*');
    expect(campo.getAttribute('accept')).toBe('image/*,video/*');
    campo.dispatchEvent(new Event('change'));
    expect(campo.getAttribute('accept')).toBe('image/*,audio/*,.pdf');
  });

  it('desistir também devolve o filtro de sempre', () => {
    abrirSeletorDeArquivo('image/*,video/*');
    campo.dispatchEvent(new Event('cancel'));
    expect(campo.getAttribute('accept')).toBe('image/*,audio/*,.pdf');
  });
});
