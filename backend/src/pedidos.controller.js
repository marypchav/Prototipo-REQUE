/*
Módulo Gestión de pedidos: órdenes y pedidos.

Del cliente (pasan por requiereCliente):
    GP011, GP012 Opciones de pago y entrega para la orden
    GP013, GP014 Confirmar orden (con el comprobante de SINPE Móvil)
    GP018 Historial de pedidos y detalle de cada uno

De la administradora (pasan por requiereAdmin):
    GP015 Lista de pedidos, detalle y comprobante
    GP016, GP017 Cambiar estado (confirmar, rechazar, avanzar, cancelar)
    GP019 Cada cambio deja un correo en cola (ver notificaciones.js)

Los comprobantes NO son públicos: se entregan por estas rutas, después de
que spObtenerPedido revisa que quien pide sea el dueño o la administradora.
*/
const { ejecutarSP, sql } = require('./ejecutarSP');
const ErrorApp = require('./ErrorApp');
const { aEntero, aTexto } = require('./convertir');
const { rutaRelativa, borrarArchivo, rutaAbsolutaComprobante } = require('./subirImagen');
const { avisarCatalogo } = require('./tiempoReal');
const { enviarPendientes } = require('./notificaciones');

// avisa al catálogo en vivo (CP010) de cada producto cuyas existencias cambiaron
function avisarProductos(filas) {
  for (const { IdProducto } of filas ?? []) {
    avisarCatalogo(IdProducto);
  }
}

// lee un pedido con permisos (spObtenerPedido decide si quien pide lo puede ver)
async function leerPedido(idUsuario, idPedido) {
  const [[pedido], productos, historial, estadosSiguientes] = await ejecutarSP('spObtenerPedido', {
    inIdUsuario: [sql.Int, idUsuario],
    inIdPedido: [sql.Int, aEntero(idPedido)],
  });
  return { pedido, productos, historial, estadosSiguientes };
}

// el navegador nunca recibe la ruta del archivo en el servidor, solo la URL de la API
function sinRutaDeComprobante(pedido, urlComprobante) {
  const { RutaComprobante, ...resto } = pedido;
  return { ...resto, urlComprobante: RutaComprobante ? urlComprobante : null };
}

// entrega el archivo del comprobante del pedido, si quien pide lo puede ver
async function enviarComprobante(req, res) {
  const { pedido } = await leerPedido(req.usuario.idUsuario, req.params.id);
  const archivo = rutaAbsolutaComprobante(pedido.RutaComprobante);

  if (!archivo) {
    throw new ErrorApp(50037); // pago en efectivo: no hay comprobante
  }

  res.set('Cache-Control', 'private, no-store'); // datos de pago: que no queden en caché
  await new Promise((resolver, rechazar) => {
    res.sendFile(archivo, (error) => {
      if (!error) return resolver();
      // el registro existe pero el archivo ya no está en disco
      rechazar(error.code === 'ENOENT' ? new ErrorApp(50037) : error);
    });
  });
}

/* =====================================================================
   Del cliente
   ===================================================================== */

// GET /api/cliente/orden/opciones   (GP011, GP012)
// metodosEntrega con FlagRequiereDireccion y CostoEnvio (NULL = a coordinar)
// metodosPago con FlagSoloRetiro (efectivo) y FlagRequiereComprobante (SINPE)
// direcciones vacío = GP012 flujo alterno: primero agregar una dirección
async function opcionesOrden(req, res) {
  const [metodosEntrega, metodosPago, direcciones] = await ejecutarSP('spListarOpcionesOrden', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, datos: { metodosEntrega, metodosPago, direcciones } });
}

// POST /api/cliente/pedidos   (GP013, GP014)
// formulario multipart: idMetodoPago, idMetodoEntrega, idDireccion y el
// archivo "comprobante" (solo con SINPE Móvil)
async function confirmarOrden(req, res) {
  const { idMetodoPago, idMetodoEntrega, idDireccion } = req.body ?? {};
  const ruta = req.file ? rutaRelativa(req.file) : null;

  // si el SP falla, manejarErrores borra el comprobante recién subido.
  // 50055 trae la lista de productos que ya no alcanzan (GP014 flujo alterno 1)
  const [[orden], productosCambiados] = await ejecutarSP('spConfirmarOrden', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdMetodoPago: [sql.Int, aEntero(idMetodoPago)],
    inIdMetodoEntrega: [sql.Int, aEntero(idMetodoEntrega)],
    inIdDireccion: [sql.Int, aEntero(idDireccion)],
    inRutaComprobante: [sql.NVarChar(260), ruta],
  });

  // pago en efectivo: el SP no guarda comprobante aunque llegue uno
  if (req.file && !orden.RutaComprobante) {
    await borrarArchivo(req.file.path);
  }

  // GP014 postcondición 2: el catálogo se actualiza con las nuevas existencias
  avisarProductos(productosCambiados);

  // GP014 paso 2.5: confirmación con el número de pedido
  res.status(201).json({
    ok: true,
    mensaje: `Su orden fue registrada con el número de pedido ${orden.IdPedido}. Queda pendiente de confirmación.`,
    datos: {
      idPedido: orden.IdPedido,
      subtotalProductos: orden.SubtotalProductos,
      costoEnvio: orden.CostoEnvio, // null = envío a coordinar
      total: orden.Total,
    },
  });
}

// GET /api/cliente/pedidos   (GP018)   vacío = "Aún no ha realizado pedidos"
async function listarDelCliente(req, res) {
  const [pedidos] = await ejecutarSP('spListarPedidosCliente', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, datos: { pedidos } });
}

// GET /api/cliente/pedidos/:id   (GP018)   otro cliente -> 404, sin revelar nada
async function obtenerDelCliente(req, res) {
  const { pedido, productos, historial } = await leerPedido(req.usuario.idUsuario, req.params.id);

  res.json({
    ok: true,
    datos: {
      pedido: sinRutaDeComprobante(pedido, `/api/cliente/pedidos/${pedido.IdPedido}/comprobante`),
      productos,
      historial, // GP019 restricción 2: los cambios de estado quedan visibles aquí
    },
  });
}

/* =====================================================================
   De la administradora
   ===================================================================== */

// GET /api/admin/pedidos?estado=1   (GP015)
// pedidos vacío sin filtro = "Aún no hay pedidos registrados"
async function listarAdmin(req, res) {
  const [pedidos, estados] = await ejecutarSP('spListarPedidosAdmin', {
    inIdEstadoPedido: [sql.Int, aEntero(req.query.estado)],
  });

  res.json({ ok: true, datos: { pedidos, estados } });
}

// GET /api/admin/pedidos/:id   (GP015, GP016, GP017)
// estadosSiguientes: a cuáles puede pasar. FlagRequiereMotivo = pedir motivo
async function obtenerAdmin(req, res) {
  const { pedido, productos, historial, estadosSiguientes } = await leerPedido(
    req.usuario.idUsuario,
    req.params.id
  );

  res.json({
    ok: true,
    datos: {
      pedido: sinRutaDeComprobante(pedido, `/api/admin/pedidos/${pedido.IdPedido}/comprobante`),
      productos,
      historial,
      estadosSiguientes,
    },
  });
}

// PUT /api/admin/pedidos/:id/estado   (GP016, GP017)
// cuerpo: { idEstado, motivo }   motivo obligatorio para Rechazado y Cancelado
async function cambiarEstado(req, res) {
  const { idEstado, motivo } = req.body ?? {};

  const [[cambio], productosDevueltos] = await ejecutarSP('spCambiarEstadoPedido', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIdPedido: [sql.Int, aEntero(req.params.id)],
    inIdEstadoNuevo: [sql.Int, aEntero(idEstado)],
    inMotivo: [sql.NVarChar(300), aTexto(motivo)],
  });

  // Rechazado o Cancelado: las existencias regresan al catálogo (CP010)
  avisarProductos(productosDevueltos);

  // GP019: el correo sale ya; si falla, queda en cola y se reintenta solo
  enviarPendientes().catch((error) => console.error('Error al enviar correos:', error.message));

  res.json({
    ok: true,
    mensaje: `El pedido ${cambio.IdPedido} cambió al estado "${cambio.Estado}". Se le avisará al cliente por correo.`,
    datos: { idPedido: cambio.IdPedido, idEstadoPedido: cambio.IdEstadoPedido, estado: cambio.Estado },
  });
}

module.exports = {
  opcionesOrden,
  confirmarOrden,
  listarDelCliente,
  obtenerDelCliente,
  listarAdmin,
  obtenerAdmin,
  cambiarEstado,
  enviarComprobante,
};
