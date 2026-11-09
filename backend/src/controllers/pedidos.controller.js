/*
CU2: confirmar la orden (GP011 a GP014).
CU3: atención de pedidos por la administradora (GP015 a GP017, GP019).
CU5: historial del cliente (GP018) e historial de ventas (GI009).
*/
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const ErrorApp = require('../utils/ErrorApp');
const { aEntero, aTexto, aFecha, ipDe } = require('../utils/convertir');
const { rutaRelativa, rutaAbsoluta } = require('../middlewares/subirImagen');
const { procesarNotificaciones } = require('../servicios/correo');
const { avisarCatalogo, avisarNuevoPedido, avisarEstadoPedido } = require('../servicios/tiempoReal');

// POST /api/pedidos  (GP014, con GP011, GP012 y GP013)
// formulario multipart: idMetodoPago, idMetodoEntrega, idDireccion (si es envío)
// y el archivo "comprobante" (solo si es SINPE Móvil)
async function crear(req, res) {
  const { idMetodoPago, idMetodoEntrega, idDireccion } = req.body ?? {};

  // si algo falla, manejarErrores borra el comprobante subido.
  // si el producto ya no está disponible, la respuesta trae en "datos"
  // la lista de productos que fallaron (GP014 flujo alternativo)
  const [[pedido]] = await ejecutarSP('spConfirmarOrden', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdMetodoPago: [sql.Int, aEntero(idMetodoPago)],
    inIdMetodoEntrega: [sql.Int, aEntero(idMetodoEntrega)],
    inIdDireccion: [sql.Int, aEntero(idDireccion)],
    inRutaComprobante: [sql.VarChar(260), req.file ? rutaRelativa(req.file) : null],
  });

  avisarCatalogo(); // las existencias bajaron (CP010)
  avisarNuevoPedido(pedido.IdPedido); // aviso a la administradora (sección 2.5)

  res.status(201).json({
    ok: true,
    mensaje: `Su pedido #${pedido.IdPedido} fue registrado y está pendiente de confirmación.`,
    datos: pedido,
  });
}

// GET /api/pedidos?estado=1
// la administradora ve todos (GP015); el cliente solo los suyos (GP018)
async function listar(req, res) {
  const [pedidos] = await ejecutarSP('spListarPedido', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdEstadoPedido: [sql.Int, aEntero(req.query.estado)],
  });

  res.json({ ok: true, datos: pedidos });
}

// GET /api/pedidos/:id  (GP015 detalle, GP018 detalle)
async function obtener(req, res) {
  const idPedido = aEntero(req.params.id);

  const [[pedido], productos, historial, siguientesEstados] = await ejecutarSP('spObtenerPedido', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdPedido: [sql.Int, idPedido],
  });

  // la ruta del archivo no se expone: el comprobante se pide por su propia
  // ruta protegida, que vuelve a revisar quién lo pide
  const { RutaComprobante, ...datosPedido } = pedido;

  res.json({
    ok: true,
    datos: {
      ...datosPedido,
      urlComprobante: RutaComprobante ? `/api/pedidos/${idPedido}/comprobante` : null,
      productos,
      historial,
      siguientesEstados, // vacío para el cliente
    },
  });
}

// GET /api/pedidos/:id/comprobante  (GP015)
// los comprobantes tienen datos personales: no son públicos como las fotos
async function verComprobante(req, res) {
  const [[pedido]] = await ejecutarSP('spObtenerPedido', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdPedido: [sql.Int, aEntero(req.params.id)],
  });

  const archivo = rutaAbsoluta(pedido.RutaComprobante);
  if (!archivo) {
    // GP015 flujo alternativo: pago en efectivo, no hay comprobante
    throw new ErrorApp(50024, null, 'Este pedido no tiene comprobante: el pago es en efectivo al retirar en el taller.');
  }

  res.sendFile(archivo);
}

// PUT /api/admin/pedidos/:id/estado  (GP016, GP017)
// cuerpo: { idEstado, motivo }   motivo es obligatorio para Rechazado y Cancelado
async function cambiarEstado(req, res) {
  const idPedido = aEntero(req.params.id);

  const [[resultado]] = await ejecutarSP('spCambiarEstadoPedido', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdPedido: [sql.Int, idPedido],
    inIdEstadoNuevo: [sql.Int, aEntero(req.body?.idEstado)],
    inMotivo: [sql.NVarChar(300), aTexto(req.body?.motivo)],
  });

  procesarNotificaciones(); // el correo sale ya, sin hacer esperar la respuesta (GP019)
  avisarEstadoPedido(resultado.IdUsuarioCliente, idPedido, resultado.Estado);
  if (resultado.DevuelveInventario) {
    avisarCatalogo(); // rechazado o cancelado: volvieron existencias
  }

  res.json({ ok: true, mensaje: `El pedido #${idPedido} pasó al estado "${resultado.Estado}".` });
}

// GET /api/admin/ventas?desde=2026-11-01&hasta=2026-11-30  (GI009)
async function historialVentas(req, res) {
  const [ventas, [resumen]] = await ejecutarSP('spHistorialVentas', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inFechaInicio: [sql.Date, aFecha(req.query.desde)],
    inFechaFin: [sql.Date, aFecha(req.query.hasta)],
  });

  res.json({ ok: true, datos: { ventas, resumen } });
}

module.exports = { crear, listar, obtener, verComprobante, cambiarEstado, historialVentas };
