/*
Actualizaciones en tiempo real con Socket.IO (CP010 y sección 3.3 de la ERS).

Eventos que recibe el navegador:
    catalogo:actualizado  -> a todos: cambió el inventario, recargar el catálogo
    pedido:nuevo          -> a la administradora: entró un pedido nuevo (2.5)
    pedido:actualizado    -> a la administradora: un pedido cambió de estado
    pedido:estado         -> al cliente dueño: su pedido cambió de estado

En el frontend:
    <script src="/socket.io/socket.io.js"></script>
    const socket = io();
    socket.on('catalogo:actualizado', () => cargarCatalogo());

Cada navegador se identifica con la misma cookie de sesión: así la
administradora entra al cuarto "admin" y cada cliente a "usuario:<id>".
*/
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const { NOMBRE_COOKIE } = require('../middlewares/autenticacion');

let io = null;

function usuarioDesdeCookie(encabezado = '') {
  const par = encabezado
    .split(';')
    .map((parte) => parte.trim())
    .find((parte) => parte.startsWith(`${NOMBRE_COOKIE}=`));

  if (!par) {
    return null;
  }
  try {
    return jwt.verify(decodeURIComponent(par.slice(NOMBRE_COOKIE.length + 1)), config.jwt.secreto);
  } catch {
    return null;
  }
}

function iniciarTiempoReal(servidorHttp) {
  io = new Server(servidorHttp);

  io.on('connection', (socket) => {
    const usuario = usuarioDesdeCookie(socket.handshake.headers.cookie);
    if (!usuario) {
      return; // visitante sin sesión: solo recibe los avisos del catálogo
    }
    socket.join(`usuario:${usuario.idUsuario}`);
    if (usuario.esAdministrador) {
      socket.join('admin');
    }
  });
}

function avisarCatalogo(idProducto = null) {
  io?.emit('catalogo:actualizado', { idProducto });
}

function avisarNuevoPedido(idPedido) {
  io?.to('admin').emit('pedido:nuevo', { idPedido });
}

function avisarEstadoPedido(idUsuarioCliente, idPedido, estado) {
  io?.to(`usuario:${idUsuarioCliente}`).emit('pedido:estado', { idPedido, estado });
  io?.to('admin').emit('pedido:actualizado', { idPedido, estado });
}

module.exports = { iniciarTiempoReal, avisarCatalogo, avisarNuevoPedido, avisarEstadoPedido };
