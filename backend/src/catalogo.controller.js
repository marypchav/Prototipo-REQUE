/*
Módulo Catálogo de productos (CP001 a CP011). Todo es público (CP009):
ninguna ruta pide sesión y ninguna modifica datos (CP001 restricción 3).
*/
const { ejecutarSP, sql } = require('./ejecutarSP');
const { aEntero, agruparTallas } = require('./convertir');

// un valor que no sea número queda null y el SP responde 50010
function tallasDeConsulta(valor) {
  if (valor === undefined || valor === null || String(valor).trim() === '') {
    return null;
  }
  const ids = String(valor)
    .split(',')
    .map((parte) => aEntero(parte.trim()));
  return JSON.stringify(ids);
}

// GET /api/catalogo?categoria=1&tallas=2,3 (CP001 a CP007)
// los dos filtros son opcionales y se pueden combinar (CP007 restricción 3)
async function listar(req, res) {
  const [productos, tallas, categoriasFiltro, tallasFiltro] = await ejecutarSP('spListarCatalogo', {
    inIdCategoria: [sql.Int, aEntero(req.query.categoria)],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasDeConsulta(req.query.tallas)],
  });

  res.json({
    ok: true,
    datos: {
      productos: agruparTallas(productos, tallas), // cada tarjeta con sus tallas disponibles
      filtros: {
        categorias: categoriasFiltro, // solo las que tienen productos (CP007)
        tallas: tallasFiltro, // solo las que tienen existencias (CP006)
      },
    },
  });
}

// GET /api/productos/:id (CP008, y el enlace compartido de CP011)
// si el producto no existe o fue eliminado responde 404 con "Este producto ya no está disponible." (CP008 y CP011 alternos)
async function obtener(req, res) {
  const [[producto], tallas] = await ejecutarSP('spObtenerProducto', {
    inIdProducto: [sql.Int, aEntero(req.params.id)],
  });

  res.json({ ok: true, datos: { ...producto, tallas } });
}

module.exports = { listar, obtener };
