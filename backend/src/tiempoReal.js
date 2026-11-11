/*
CP010 Actualización en tiempo real del catálogo, con Socket.IO.
Cuando cambia el inventario, el servidor avisa a todos los navegadores que
tienen abierto el catálogo o un detalle, y estos recargan solo lo necesario.
*/
const { Server } = require('socket.io');

let io = null;

function iniciarTiempoReal(servidorHttp) {
  io = new Server(servidorHttp);
}

// idProducto: el producto que cambió; null = pueden ser varios
function avisarCatalogo(idProducto = null) {
  io?.emit('catalogo:actualizado', { idProducto });
}

module.exports = { iniciarTiempoReal, avisarCatalogo };
