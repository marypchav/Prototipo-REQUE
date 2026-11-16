/*
Error "esperado" de la aplicación: lleva el código, el mensaje para el
usuario y el estado HTTP. Cualquier otro error se trata como 50000.
*/
const { mensajeDe, estadoHttpDe } = require('./codigosError');

class ErrorApp extends Error {
  constructor(codigo, datos = null, mensaje = null) {
    super(mensaje || mensajeDe(codigo));
    this.name = 'ErrorApp';
    this.codigo = codigo;
    this.estadoHttp = estadoHttpDe(codigo);
    this.datos = datos;
  }
}

module.exports = ErrorApp;
