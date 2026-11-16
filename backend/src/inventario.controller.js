/*
Módulo Gestión de inventario (GI002 a GI008). Solo la administradora:
todas estas rutas pasan antes por requiereAdmin (ver rutas.js).
Después de cada cambio se avisa al catálogo en vivo (CP010).
*/
const { ejecutarSP, sql } = require('./ejecutarSP');
const ErrorApp = require('./ErrorApp');
const { aEntero, aNumero, aTexto, agruparTallas, idsDeConsulta } = require('./convertir');
const { rutaRelativa, borrarArchivo } = require('./subirImagen');
const { avisarCatalogo } = require('./tiempoReal');

// [{ idTalla, cantidad }] del navegador -> el JSON que esperan los SP.
// Los valores van tal como llegan: el SP rechaza negativos, letras y decimales
function tallasAJson(tallas) {
  if (!Array.isArray(tallas)) {
    return null; // el SP responde 50025
  }
  return JSON.stringify(
    tallas.map((talla) => ({ idTalla: talla?.idTalla, cantidad: talla?.cantidad }))
  );
}

// GET /api/admin/opciones-producto   categorías y tallas para el formulario
async function opciones(req, res) {
  const [categorias, tallas] = await ejecutarSP('spListarOpcionesProducto');

  res.json({ ok: true, datos: { categorias, tallas } });
}

// GET /api/admin/productos?busqueda=blusa&categoria=1&tallas=2,3   (GI004, GI008)
async function listar(req, res) {
  const [productos, tallas, categorias, todasLasTallas, [total]] = await ejecutarSP(
    'spListarInventario',
    {
      inBusqueda: [sql.NVarChar(100), aTexto(req.query.busqueda)],
      inIdCategoria: [sql.Int, aEntero(req.query.categoria)],
      inTallasJson: [sql.NVarChar(sql.MAX), idsDeConsulta(req.query.tallas)],
    }
  );

  res.json({
    ok: true,
    datos: {
      productos: agruparTallas(productos, tallas),
      filtros: { categorias, tallas: todasLasTallas },
      // 0 -> "Aún no hay productos registrados en el inventario" (GI004)
      // >0 con productos vacío -> "No se han encontrado productos..." (GI008)
      totalInventario: total.TotalInventario,
    },
  });
}

// GET /api/admin/productos/:id   datos para el formulario de modificar (GI005)
async function obtener(req, res) {
  const [[producto], tallas] = await ejecutarSP('spObtenerProductoInventario', {
    inIdProducto: [sql.Int, aEntero(req.params.id)],
  });

  res.json({ ok: true, datos: { ...producto, tallas } });
}

// POST /api/admin/productos   (GI002)
// cuerpo: { nombre, descripcion, idCategoria, precio, tallas: [{ idTalla, cantidad }] }
async function agregar(req, res) {
  const { nombre, descripcion, idCategoria, precio, tallas } = req.body ?? {};

  const [[fila]] = await ejecutarSP('spAgregarProducto', {
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inDescripcion: [sql.NVarChar(500), aTexto(descripcion)],
    inIdCategoria: [sql.Int, aEntero(idCategoria)],
    inPrecio: [sql.Decimal(12, 2), aNumero(precio)],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasAJson(tallas)],
  });

  avisarCatalogo(fila.IdProducto);
  res.status(201).json({
    ok: true,
    mensaje: 'El producto ha sido agregado.',
    datos: { idProducto: fila.IdProducto }, // con este id se sube la foto (GI003)
  });
}

// PUT /api/admin/productos/:id   (GI005)
// cuerpo: el formulario completo, igual que al agregar
async function modificar(req, res) {
  const idProducto = aEntero(req.params.id);
  const { nombre, descripcion, idCategoria, precio, tallas } = req.body ?? {};

  await ejecutarSP('spModificarProducto', {
    inIdProducto: [sql.Int, idProducto],
    inNombre: [sql.NVarChar(100), aTexto(nombre)],
    inDescripcion: [sql.NVarChar(500), aTexto(descripcion)],
    inIdCategoria: [sql.Int, aEntero(idCategoria)],
    inPrecio: [sql.Decimal(12, 2), aNumero(precio)],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasAJson(tallas)],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'El producto ha sido actualizado con éxito.' });
}

// PUT /api/admin/productos/:id/existencias   (GI007)
// cuerpo: { tallas: [{ idTalla, cantidad }] }   solo las tallas que cambian
async function actualizarExistencias(req, res) {
  const idProducto = aEntero(req.params.id);

  await ejecutarSP('spActualizarExistencias', {
    inIdProducto: [sql.Int, idProducto],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasAJson(req.body?.tallas)],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'La disponibilidad fue actualizada.' });
}

// POST /api/admin/productos/:id/foto   formulario multipart con el campo "foto" (GI003)
async function subirFoto(req, res) {
  if (!req.file) {
    throw new ErrorApp(50036); // no se envió ninguna imagen
  }

  const idProducto = aEntero(req.params.id);
  const ruta = rutaRelativa(req.file);

  // si el SP falla, manejarErrores borra la foto recién subida
  const [[fila]] = await ejecutarSP('spActualizarImagenProducto', {
    inIdProducto: [sql.Int, idProducto],
    inRutaImagen: [sql.NVarChar(260), ruta],
  });

  // la foto anterior ya no se usa
  if (fila.RutaImagenAnterior && fila.RutaImagenAnterior !== ruta) {
    await borrarArchivo(fila.RutaImagenAnterior);
  }

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'La foto fue guardada.', datos: { rutaImagen: ruta } });
}

// DELETE /api/admin/productos/:id   (GI006)
// la confirmación "¿Confirma que desea eliminar este producto?" la hace el frontend
async function eliminar(req, res) {
  const idProducto = aEntero(req.params.id);

  await ejecutarSP('spEliminarProducto', {
    inIdProducto: [sql.Int, idProducto],
  });

  avisarCatalogo(idProducto);
  res.json({ ok: true, mensaje: 'El producto fue eliminado exitosamente.' });
}

module.exports = {
  opciones,
  listar,
  obtener,
  agregar,
  modificar,
  actualizarExistencias,
  subirFoto,
  eliminar,
};
