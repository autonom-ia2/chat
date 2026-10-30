/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { PELES, fornecerPele } from '../pele';
import {
  anexarArquivos,
  indicesDeDocumento,
  usePeleDaResposta,
} from '../usePeleDaResposta';
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
});

describe('idiomaDoPainel', () => {
  it('troca o "_" do painel pelo "-" do Intl', () => {
    expect(idiomaDoPainel('pt_BR')).toBe('pt-BR');
    expect(idiomaDoPainel('en')).toBe('en');
    expect(idiomaDoPainel(undefined)).toBe('en');
  });
});

describe('anexarArquivos (#1702)', () => {
  it('cada arquivo entra pelo caminho de sempre, com o tipo escolhido no "+"', () => {
    const onFileUpload = vi.fn();
    const foto = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });
    const pdf = new File(['y'], 'proposta.pdf', { type: 'application/pdf' });
    anexarArquivos(
      { arquivos: [foto, pdf], comoDocumento: true },
      onFileUpload
    );
    expect(onFileUpload).toHaveBeenCalledTimes(2);
    expect(onFileUpload).toHaveBeenNthCalledWith(1, {
      name: 'foto.jpg',
      type: 'image/jpeg',
      size: 1,
      file: foto,
      comoDocumento: true,
    });
  });
});

describe('indicesDeDocumento (#1702)', () => {
  it('diz a posição de cada anexo que vai como documento', () => {
    expect(
      indicesDeDocumento([
        { comoDocumento: true },
        {},
        { comoDocumento: false },
        { comoDocumento: true },
      ])
    ).toEqual([0, 3]);
    expect(indicesDeDocumento([])).toEqual([]);
  });
});
