import {
  exemploDaData,
  formatoDaData,
  textoDaData,
  valorDaData,
} from '../../ficha/dataDoCampo';
import { errosDoFormulario } from '../../ficha/errosDoFormulario';

// #3082 — a data do campo personalizado segue o idioma do painel, não o do
// navegador: em português, dia/mês/ano; em inglês, mês/dia/ano.
describe('data do campo no formato do idioma do painel', () => {
  it('lê a ordem e o separador do idioma', () => {
    expect(formatoDaData('pt-BR')).toEqual({
      ordem: ['day', 'month', 'year'],
      separador: '/',
    });
    expect(formatoDaData('en').ordem).toEqual(['month', 'day', 'year']);
  });

  it('mostra a data gravada no formato do idioma', () => {
    expect(textoDaData('1990-05-12', 'pt-BR')).toBe('12/05/1990');
    expect(textoDaData('1990-05-12', 'en')).toBe('05/12/1990');
    expect(textoDaData('1990-05-12T00:00:00Z', 'pt-BR')).toBe('12/05/1990');
  });

  it('mostra como está o que não é uma data gravada', () => {
    expect(textoDaData('12 de maio', 'pt-BR')).toBe('12 de maio');
    expect(textoDaData('', 'pt-BR')).toBe('');
    expect(textoDaData(null, 'pt-BR')).toBe('');
  });

  it('o que a pessoa escreve vira AAAA-MM-DD', () => {
    expect(valorDaData('03/08/1985', 'pt-BR')).toBe('1985-08-03');
    expect(valorDaData('3/8/1985', 'pt-BR')).toBe('1985-08-03');
    expect(valorDaData('03081985', 'pt-BR')).toBe('1985-08-03');
    expect(valorDaData('03-08-1985', 'pt-BR')).toBe('1985-08-03');
    expect(valorDaData('08/03/1985', 'en')).toBe('1985-08-03');
  });

  it('vazio sobe vazio; o que não é um dia de verdade sobe como foi escrito', () => {
    expect(valorDaData('  ', 'pt-BR')).toBe('');
    expect(valorDaData('31/02/1990', 'pt-BR')).toBe('31/02/1990');
    expect(valorDaData('03/08/85', 'pt-BR')).toBe('03/08/85');
    expect(valorDaData('03/08', 'pt-BR')).toBe('03/08');
  });

  it('mostra o jeito de escrever com as letras do idioma', () => {
    const letras = { day: 'dd', month: 'mm', year: 'aaaa' };
    expect(exemploDaData('pt-BR', letras)).toBe('dd/mm/aaaa');
    expect(exemploDaData('en', letras)).toBe('mm/dd/aaaa');
  });
});

describe('conferência do formulário: data do campo personalizado', () => {
  const base = { nome: 'Ana', email: '', cpf: '' };
  const tipos = { aniversario: 'date' };

  it('trava a data mudada que não é um dia de verdade', () => {
    const erros = errosDoFormulario(
      { ...base, atributos: {} },
      { ...base, atributos: { aniversario: '31/02/1990' } },
      tipos
    );
    expect(erros).toEqual({ 'atributo:aniversario': 'DATA' });
  });

  it('não trava a data certa nem a antiga que ninguém mexeu', () => {
    expect(
      errosDoFormulario(
        { ...base, atributos: {} },
        { ...base, atributos: { aniversario: '1985-08-03' } },
        tipos
      )
    ).toEqual({});
    expect(
      errosDoFormulario(
        { ...base, atributos: { aniversario: '12 de maio' } },
        { ...base, atributos: { aniversario: '12 de maio' } },
        tipos
      )
    ).toEqual({});
  });
});
